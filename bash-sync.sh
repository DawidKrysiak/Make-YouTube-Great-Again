#!/bin/bash

# Setup logging
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sync_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Load configuration from config.json
CONFIG_FILE="./config/config.json"
CONFIG=$(cat "$CONFIG_FILE")
INITIAL_SEEDING=$(echo "$CONFIG" | jq -r '.initial_seeding')
RETENTION_PERIOD=$(echo "$CONFIG" | jq -r '.retention_period')
COOKIES_FILE=$(echo "$CONFIG" | jq -r '.cookies_file')
BASE_PATH=$(echo "$CONFIG" | jq -r '.base_path')
ARCHIVE_FILE="./config/download_archive.txt"

log "=== Starting YouTube Sync ==="

# Clear arrays to avoid any potential caching issues
ARCHIVE_URLS=()
ARCHIVE_CATEGORIES=()
CASUAL_URLS=()
CASUAL_CATEGORIES=()

# Load URLs from text files
load_urls() {
    local file_path=$1
    local urls_var=$2
    local categories_var=$3
    while IFS='|' read -r url category; do
        if [[ -n "$url" && -n "$category" ]]; then
            eval "$urls_var+=(\"$url\")"
            eval "$categories_var+=(\"$category\")"
        else
            echo "Invalid line format (missing '|'): $url|$category"
        fi
    done < "$file_path"
}

# Load URLs into arrays
load_urls "./config/archive.txt" ARCHIVE_URLS ARCHIVE_CATEGORIES
load_urls "./config/casual.txt" CASUAL_URLS CASUAL_CATEGORIES

# Create directories
create_directories() {
    local base_path=$1
    local urls_var=$2
    local categories_var=$3
    eval "local urls=(\"\${$urls_var[@]}\")"
    eval "local categories=(\"\${$categories_var[@]}\")"
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
            '--sleep-interval' '3'
            '--max-sleep-interval' '69'
            '--sleep-subtitles' '1'
            '--format' 'best[ext=mp4]'
            '--no-playlist'
            '--download-archive' "$ARCHIVE_FILE"
            '--print' 'after_move:Downloaded: %(filepath)s'
            '--no-warnings'
            '--js-runtimes' 'node,deno'
            '--remote-components' 'ejs:npm'
            '--no-continue'
            '--no-part'
            '--extractor-args' 'youtubetab:skip=authcheck'
            "$url"
        )
        if [[ -n "$dateafter" ]]; then
            command+=('--dateafter' "$dateafter")
        fi

        log "Starting download of $url"
        local output
        output=$("${command[@]}" 2>&1)
        local result=$?
        echo "$output" | tee -a "$LOG_FILE"

        if [[ $result -ne 0 ]]; then
            log "Download failed for $url"
            if echo "$output" | grep -q "Premieres"; then
                log "Skipping premiere video: $url"
                return 0
            elif echo "$output" | grep -q "VPN/Proxy Detected"; then
                log "Skipping video due to VPN/Proxy detection: $url"
                return 0
            elif echo "$output" | grep -q "This channel does not have a streams tab"; then
                log "Skipping video due to missing streams tab: $url"
                return 0
            elif echo "$output" | grep -q "This video is available to this channel's members"; then
                log "Skipping members-only video: $url"
                return 0
            elif echo "$output" | grep -q "This live event will begin"; then
                log "Skipping scheduled streams: $url"
                return 0
            elif echo "$output" | grep -q "Playlists that require authentication"; then
                log "Skipping video due to authentication requirement: $url"
                return 0
            elif echo "$output" | grep -q "Network is unreachable"; then
                log "Network error. Retrying in 5 seconds..."
                sleep 5
                attempt=$((attempt + 1))
            elif echo "$output" | grep -q "Read timed out"; then
                log "Read timed out. Retrying in 5 seconds..."
                sleep 5
                attempt=$((attempt + 1))
            else
                log "Failed to download after $retries attempts: $url"
                return 1
            fi
        else
            log "Successfully downloaded from $url"
            return 0
        fi
    done
    log "Failed to download after $retries attempts: $url"
    return 1
}

# Process archive URLs
log "Processing ${#ARCHIVE_URLS[@]} archive URLs"
for i in "${!ARCHIVE_URLS[@]}"; do
    url=${ARCHIVE_URLS[$i]}
    category=${ARCHIVE_CATEGORIES[$i]}
    log "Processing archive URL: $url with category: $category"
    if [[ "$INITIAL_SEEDING" == "false" ]]; then
        dateafter=$(date -d "yesterday" +%Y%m%d)
        download_videos "$url" "$category" "$dateafter"
    else
        download_videos "$url" "$category"
    fi
    log "Finished processing archive URL: $url"
done

# Process casual URLs
log "Processing ${#CASUAL_URLS[@]} casual URLs"
for i in "${!CASUAL_URLS[@]}"; do
    url=${CASUAL_URLS[$i]}
    category=${CASUAL_CATEGORIES[$i]}
    log "Processing casual URL: $url with category: $category"
    if [[ "$INITIAL_SEEDING" == "true" ]]; then
        dateafter=$(date -d "30 days ago" +%Y%m%d)
        download_videos "$url" "$category" "$dateafter"
    else
        dateafter=$(date -d "yesterday" +%Y%m%d)
        download_videos "$url" "$category" "$dateafter"
    fi

    # Delete old files in casual directories
    sub_dir_name=$(echo "$url" | cut -d'@' -f2)
    sub_dir="$BASE_PATH/$category/$sub_dir_name"
    delete_old_files "$sub_dir"
    log "Finished processing casual URL: $url"
done

log "=== YouTube Sync Completed ==="