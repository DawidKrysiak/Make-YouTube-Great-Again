#!/bin/bash

# Load configuration from config.json
CONFIG_FILE="./config/config.json"
CONFIG=$(cat "$CONFIG_FILE")
INITIAL_SEEDING=$(echo "$CONFIG" | jq -r '.initial_seeding')
RETENTION_PERIOD=$(echo "$CONFIG" | jq -r '.retention_period')
COOKIES_FILE=$(echo "$CONFIG" | jq -r '.cookies_file')
BASE_PATH=$(echo "$CONFIG" | jq -r '.base_path')
ARCHIVE_FILE="./config/download_archive.txt"

# Clear arrays to avoid any potential caching issues
ARCHIVE_URLS=()
ARCHIVE_CATEGORIES=()
CASUAL_URLS=()
CASUAL_CATEGORIES=()

# Load URLs from text files
load_urls() {
    local file_path=$1
    local -n urls=$2
    local -n categories=$3
    while IFS='|' read -r url category; do
        if [[ -n "$url" && -n "$category" ]]; then
            urls+=("$url")
            categories+=("$category")
        else
            echo "Invalid line format (missing '|'): $url|$category"
        fi
    done < "$file_path"
}

# Load URLs into arrays
load_urls "./config/archive.txt" ARCHIVE_URLS ARCHIVE_CATEGORIES
load_urls "./config/casual.txt" CASUAL_URLS CASUAL_CATEGORIES

# Debugging output to check loaded URLs
echo "Loaded archive URLs:"
for i in "${!ARCHIVE_URLS[@]}"; do
    echo "URL: ${ARCHIVE_URLS[$i]}, Category: ${ARCHIVE_CATEGORIES[$i]}"
done

echo "Loaded casual URLs:"
for i in "${!CASUAL_URLS[@]}"; do
    echo "URL: ${CASUAL_URLS[$i]}, Category: ${CASUAL_CATEGORIES[$i]}"
done

# Create directories
create_directories() {
    local base_path=$1
    local -n urls=$2
    local -n categories=$3
    for i in "${!urls[@]}"; do
        local url=${urls[$i]}
        local category=${categories[$i]}
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
create_directories "$BASE_PATH" ARCHIVE_URLS ARCHIVE_CATEGORIES
create_directories "$BASE_PATH" CASUAL_URLS CASUAL_CATEGORIES

# Randomized delay
randomized_delay() {
    echo $(awk -v min=3 -v max=30 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
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
    local retries=3
    local attempt=0

    while [[ $attempt -lt $retries ]]; do
        local delay=$(randomized_delay)
        echo "Sleeping for $delay seconds before downloading $url"
        sleep $delay

        local command=(
            'yt-dlp'
            '--output' "$BASE_PATH/$category/%(uploader)s/%(title)s.%(ext)s"
            '--cookies' "$COOKIES_FILE"
            '--verbose'
            '--format' 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]'
            '--yes-playlist'
            '--download-archive' "$ARCHIVE_FILE"
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
            if grep -q "Premieres" <<< "$result"; then
                echo "Skipping premiere video: $url"
                return
            elif grep -q "VPN/Proxy Detected" <<< "$result"; then
                echo "Skipping video due to VPN/Proxy detection: $url"
                return
            elif grep -q "This channel does not have a streams tab" <<< "$result"; then
                echo "Skipping video due to missing streams tab: $url"
                return
            elif grep -q "Network is unreachable" <<< "$result"; then
                echo "Network error: $result. Retrying in 1 minute..."
                sleep 60
                attempt=$((attempt + 1))
            else
                attempt=$((attempt + 1))
                if [[ $attempt -eq $retries ]]; then
                    echo "Stopping process for 24 hours due to repeated errors."
                    sleep 86400  # Sleep for 24 hours
                fi
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
for i in "${!ARCHIVE_URLS[@]}"; do
    url=${ARCHIVE_URLS[$i]}
    category=${ARCHIVE_CATEGORIES[$i]}
    echo "Processing archive URL: $url with category: $category"
    if [[ "$INITIAL_SEEDING" == "true" ]]; then
        initial_seeding_download "$url" "$category" "true"
    else
        dateafter=$(date -d "yesterday" +%Y%m%d)
        download_videos "$url" "$category" "$dateafter"
    fi
    echo "Finished processing archive URL: $url"
done

# Process casual URLs
for i in "${!CASUAL_URLS[@]}"; do
    url=${CASUAL_URLS[$i]}
    category=${CASUAL_CATEGORIES[$i]}
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
    echo "Finished processing casual URL: $url"
done