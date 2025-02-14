#!/bin/bash

# Load configuration from config.json
CONFIG_FILE="./config/config.json"
CONFIG=$(cat "$CONFIG_FILE")
INITIAL_SEEDING=$(echo "$CONFIG" | jq -r '.initial_seeding')
RETENTION_PERIOD=$(echo "$CONFIG" | jq -r '.retention_period')
COOKIES_FILE=$(echo "$CONFIG" | jq -r '.cookies_file')
BASE_PATH=$(echo "$CONFIG" | jq -r '.base_path')

# Load URLs from text files
load_urls() {
    local file_path=$1
    declare -A urls
    while IFS='|' read -r url category; do
        if [[ -n "$url" && -n "$category" ]]; then
            urls["$url"]=$category
        else
            echo "Invalid line format (missing '|'): $url|$category"
        fi
    done < "$file_path"
    echo "${!urls[@]}"
    echo "${urls[@]}"
}

# Load URLs into associative arrays
declare -A ARCHIVE_ARRAY
while IFS='|' read -r url category; do
    if [[ -n "$url" && -n "$category" ]]; then
        ARCHIVE_ARRAY["$url"]=$category
    else
        echo "Invalid line format (missing '|'): $url|$category"
    fi
done < "./config/archive.txt"

declare -A CASUAL_ARRAY
while IFS='|' read -r url category; do
    if [[ -n "$url" && -n "$category" ]]; then
        CASUAL_ARRAY["$url"]=$category
    else
        echo "Invalid line format (missing '|'): $url|$category"
    fi
done < "./config/casual.txt"

# Create directories
create_directories() {
    local base_path=$1
    declare -n data=$2
    for url in "${!data[@]}"; do
        local category=${data[$url]}
        local main_dir="$base_path/$category"
        mkdir -p "$main_dir"
        if [[ "$url" == *@* ]]; then
            local sub_dir_name=$(echo "$url" | cut -d'@' -f2)
            local sub_dir="$main_dir/$sub_dir_name"
            mkdir -p "$sub_dir"
            echo "Created directory: $sub_dir"
        else
            echo "Invalid URL format (missing '@'): $url"
        fi
    done
}

# Create directories for 'archive' and 'casual'
create_directories "$BASE_PATH" ARCHIVE_ARRAY
create_directories "$BASE_PATH" CASUAL_ARRAY

# Randomized delay
randomized_delay() {
    echo $(awk -v min=3 -v max=10 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
}

# Delete old files
delete_old_files() {
    local directory=$1
    local now=$(date +%s)
    local cutoff=$(($now - $RETENTION_PERIOD * 24 * 60 * 60))
    for filename in "$directory"/*; do
        if [[ -f "$filename" ]]; then
            local file_modified=$(stat -c %Y "$filename")
            if [[ $file_modified -lt $cutoff ]]; then
                rm "$filename"
                echo "Deleted old file: $filename"
            fi
        fi
    done
}

# Download videos
download_videos() {
    local url=$1
    local category=$2
    local dateafter=$3
    local error_count=0
    while [[ $error_count -lt 3 ]]; do
        local delay=$(randomized_delay)
        echo "Sleeping for $delay seconds before downloading $url"
        sleep $delay

        local command=(
            'yt-dlp'
            '--output' "$BASE_PATH/$category/%(uploader)s/%(title)s.%(ext)s"
            '--cookies' "$COOKIES_FILE"
            '--verbose'
            '--format' 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]'
            "$url"
        )
        if [[ -n "$dateafter" ]]; then
            command+=('--dateafter' "$dateafter")
        fi

        echo "Running command: ${command[*]}"
        "${command[@]}"

        local result=$?
        if [[ $result -ne 0 ]]; then
            echo "Command failed with exit code $result"
            error_count=$((error_count + 1))
            if [[ $error_count -eq 3 ]]; then
                echo "Stopping process for 24 hours due to repeated errors."
                sleep 86400  # Sleep for 24 hours
            fi
        else
            break
        fi
    done
}

# Initial seeding download
initial_seeding_download() {
    local url=$1
    local category=$2
    local is_archive=$3
    local current_date=$(date +%Y%m%d)
    while true; do
        if [[ "$is_archive" == "false" ]]; then
            local dateafter=$(date -d "$current_date -30 days" +%Y%m%d)
            download_videos "$url" "$category" "$dateafter"
            local result
            result=$(yt-dlp --dateafter "$dateafter" "$url" 2>&1)
            if echo "$result" | grep -q "No more videos to download"; then
                echo "No more videos to download for $url"
                break
            fi
        else
            download_videos "$url" "$category"
            local result
            result=$(yt-dlp "$url" 2>&1)
            if echo "$result" | grep -q "No more videos to download"; then
                echo "No more videos to download for $url"
                break
            fi
        fi
        current_date=$(date -d "$current_date -30 days" +%Y%m%d)
    done
}

# Process archive URLs
for url in "${!ARCHIVE_ARRAY[@]}"; do
    category=${ARCHIVE_ARRAY[$url]}
    echo "Processing archive URL: $url with category: $category"
    if [[ "$INITIAL_SEEDING" == "true" ]]; then
        initial_seeding_download "$url" "$category" "true"
    else
        dateafter=$(date -d "yesterday" +%Y%m%d)
        download_videos "$url" "$category" "$dateafter"
    fi
done

# Process casual URLs
for url in "${!CASUAL_ARRAY[@]}"; do
    category=${CASUAL_ARRAY[$url]}
    echo "Processing casual URL: $url with category: $category"
    if [[ "$INITIAL_SEEDING" == "true" ]]; then
        dateafter=$(date -d "30 days ago" +%Y%m%d)
        download_videos "$url" "$category" "$dateafter"
    else
        dateafter=$(date -d "yesterday" +%Y%m%d)
        download_videos "$url" "$category" "$dateafter"
    fi

    # Delete old files in casual directories if not initial seeding
    if [[ "$INITIAL_SEEDING" == "false" ]]; then
        sub_dir_name=$(echo "$url" | cut -d'@' -f2)
        sub_dir="$BASE_PATH/$category/$sub_dir_name"
        delete_old_files "$sub_dir"
    fi
done