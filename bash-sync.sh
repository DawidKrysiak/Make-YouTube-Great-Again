#!/bin/bash

# Setup logging
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sync_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Parse command line arguments
PLAYLIST_MODE=false
MUSIC_ONLY=false
SINGLE_URL=""
SINGLE_CATEGORY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --playlist)
            PLAYLIST_MODE=true
            shift
            ;;
        --music-only)
            MUSIC_ONLY=true
            shift
            ;;
        --url)
            SINGLE_URL="$2"
            shift 2
            ;;
        --category)
            SINGLE_CATEGORY="$2"
            shift 2
            ;;
        *)
            log "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -n "$SINGLE_URL" && -z "$SINGLE_CATEGORY" ]]; then
    echo "--category is required when --url is provided"
    exit 1
fi

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

shuffle_url_pairs() {
    local urls_var=$1
    local categories_var=$2

    eval "local count=\${#$urls_var[@]}"
    if [[ $count -le 1 ]]; then
        return
    fi

    for ((i=count-1; i>0; i--)); do
        j=$((RANDOM % (i + 1)))

        eval "local url_i=\${$urls_var[i]}"
        eval "local url_j=\${$urls_var[j]}"
        eval "local category_i=\${$categories_var[i]}"
        eval "local category_j=\${$categories_var[j]}"

        eval "$urls_var[i]=\"\$url_j\""
        eval "$urls_var[j]=\"\$url_i\""
        eval "$categories_var[i]=\"\$category_j\""
        eval "$categories_var[j]=\"\$category_i\""
    done
}

# Load URLs into arrays
load_urls "./config/archive.txt" ARCHIVE_URLS ARCHIVE_CATEGORIES
load_urls "./config/casual.txt" CASUAL_URLS CASUAL_CATEGORIES
shuffle_url_pairs ARCHIVE_URLS ARCHIVE_CATEGORIES
shuffle_url_pairs CASUAL_URLS CASUAL_CATEGORIES

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
        local sub_dir_name
        if [[ "$url" == *@* ]]; then
            sub_dir_name=$(echo "$url" | cut -d'@' -f2 | cut -d'/' -f1)
        else
            sub_dir_name=$(echo "$url" | grep -oE 'list=[A-Za-z0-9_-]+' | cut -d= -f2)
            [[ -z "$sub_dir_name" ]] && sub_dir_name="playlist"
        fi
        local sub_dir="$main_dir/$sub_dir_name"
        mkdir -p "$sub_dir"
        echo "Created directory: $sub_dir"
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

# Check if video with exact filename already exists (failover for lost archive)
check_existing_video() {
    local video_id=$1
    local expected_path=$2
    
    # Get the base filename without extension
    local base_path="${expected_path%.*}"
    local directory=$(dirname "$base_path")
    local basename_no_ext=$(basename "$base_path")
    
    # Check if exact file exists
    if [[ -f "$expected_path" ]]; then
        log "⚠️  Video already exists: $expected_path"
        log "Adding video ID $video_id to archive to prevent future checks"
        echo "youtube $video_id" >> "$ARCHIVE_FILE"
        return 0
    fi
    
    # Check for files with same base name but different extensions
    if [[ -d "$directory" ]]; then
        for file in "$directory"/*; do
            if [[ -f "$file" ]]; then
                local file_without_ext="${file%.*}"
                local file_basename_no_ext=$(basename "$file_without_ext")
                
                if [[ "$file_basename_no_ext" == "$basename_no_ext" ]]; then
                    log "⚠️  Video already exists: $file"
                    log "Adding video ID $video_id to archive to prevent future checks"
                    echo "youtube $video_id" >> "$ARCHIVE_FILE"
                    return 0
                fi
            fi
        done
    fi
    return 1
}

# Normalize channel URL - append /videos to bare channel URLs to avoid multi-tab traversal
normalize_channel_url() {
    local url=$1
    if [[ "$url" =~ ^https?://www\.youtube\.com/@[^/]+/?$ ]]; then
        echo "${url%/}/videos"
    else
        echo "$url"
    fi
}

# Archive permanently-failed video IDs so they are never retried
archive_permafail_from_output() {
    local output="$1"
    while IFS= read -r line; do
        for phrase in \
            "Join this channel to get access to members-only content" \
            "This video is available to this channel's members" \
            "This video is private" \
            "Video unavailable" \
            "This video has been removed" \
            "This video is not available" \
            "This video contains content from"; do
            if [[ "$line" == *"$phrase"* ]]; then
                local video_id
                video_id=$(echo "$line" | grep -oE '\[youtube(:[a-z]+)?\] [A-Za-z0-9_-]{11}' | grep -oE '[A-Za-z0-9_-]{11}$')
                if [[ -n "$video_id" ]]; then
                    log "Archiving $video_id (permanent failure - will be skipped on future runs)"
                    echo "youtube $video_id" >> "$ARCHIVE_FILE"
                fi
                break
            fi
        done
    done <<< "$output"
}

# Download videos
download_videos() {
    local url=$1
    local category=$2
    local dateafter=$3
    local playlist_mode=${4:-false}
    local music_only=${5:-false}
    local retries=3
    local attempt=0

    if [[ "$playlist_mode" == "false" ]]; then
        url=$(normalize_channel_url "$url")
    fi

    # First, extract video info to check if it already exists (failover for lost archive)
    local info_command=(
        'yt-dlp'
        '--print' '%(id)s|%(filepath)s'
        '--output' "$BASE_PATH/$category/%(uploader)s/%(title)s.%(ext)s"
        '--no-warnings'
        '--skip-download'
        '--cookies' "$COOKIES_FILE"
    )
    
    if [[ -n "$dateafter" ]]; then
        info_command+=('--dateafter' "$dateafter")
    fi
    
    info_command+=("$url")
    
    # Extract video info with expected filenames
    local video_info
    video_info=$("${info_command[@]}" 2>/dev/null)
    
    if [[ -n "$video_info" ]]; then
        # Parse output: each line is "video_id|expected_filepath"
        while IFS='|' read -r video_id expected_path; do
            if [[ -n "$video_id" && -n "$expected_path" ]]; then
                # Check if file with same name already exists
                if check_existing_video "$video_id" "$expected_path"; then
                    continue
                fi
            fi
        done <<< "$video_info"
    fi

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
            '--download-archive' "$ARCHIVE_FILE"
            '--print' 'after_move:Downloaded: %(filepath)s'
            '--no-warnings'
            '--js-runtimes' 'node,deno'
            '--remote-components' 'ejs:npm'
            '--no-continue'
            '--no-part'
            '--extractor-args' 'youtubetab:skip=authcheck'
        )
        if [[ "$playlist_mode" == "false" ]]; then
            command+=('--no-playlist')
        fi
        if [[ "$music_only" == "true" ]]; then
            command+=(
                '--format' 'bestaudio/best'
                '--extract-audio'
                '--audio-format' 'mp3'
                '--audio-quality' '0'
            )
        else
            command+=(
                '--format' 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]'
                '--write-subs'
                '--no-write-auto-sub'
                '--sub-langs' 'en,pl'
                '--sub-format' 'srt/best'
            )
        fi
        if [[ -n "$dateafter" ]]; then
            command+=('--dateafter' "$dateafter")
        fi
        command+=("$url")

        log "Starting download of $url"
        local output
        output=$("${command[@]}" 2>&1)
        local result=$?
        echo "$output" | tee -a "$LOG_FILE"
        archive_permafail_from_output "$output"

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
            elif echo "$output" | grep -qE "416|Range Not Satisfiable"; then
                log "Skipping video with HTTP 416 error (corrupted partial download): $url"
                return 0
            elif echo "$output" | grep -q "The page needs to be reloaded"; then
                attempt=$((attempt + 1))
                if [[ $attempt -lt $retries ]]; then
                    log "YouTube requested a page reload. Retrying in 10 seconds... ($attempt/$retries)"
                    sleep 10
                else
                    log "YouTube repeatedly requested a page reload for $url"
                fi
            elif echo "$output" | grep -q "Network is unreachable"; then
                log "Network error. Retrying in 5 seconds..."
                sleep 5
                attempt=$((attempt + 1))
            elif echo "$output" | grep -q "Read timed out"; then
                log "Read timed out. Retrying in 5 seconds..."
                sleep 5
                attempt=$((attempt + 1))
            else
                attempt=$((attempt + 1))
                if [[ $attempt -lt $retries ]]; then
                    log "Unhandled download error. Retrying in 10 seconds... ($attempt/$retries)"
                    sleep 10
                else
                    log "Failed to download after $retries attempts: $url"
                    return 1
                fi
            fi
        else
            log "Successfully downloaded from $url"
            return 0
        fi
    done
    log "Failed to download after $retries attempts: $url"
    return 1
}

# Clean up old files before downloading new ones
if [[ -n "$SINGLE_URL" ]]; then
    # One-off download — skip config file loops entirely
    log "One-off download: $SINGLE_URL -> $SINGLE_CATEGORY"
    download_videos "$SINGLE_URL" "$SINGLE_CATEGORY" "" "$PLAYLIST_MODE" "$MUSIC_ONLY"
else
    log "=== Cleaning up old files ==="
    for i in "${!CASUAL_URLS[@]}"; do
        url=${CASUAL_URLS[$i]}
        category=${CASUAL_CATEGORIES[$i]}
        sub_dir_name=$(echo "$url" | cut -d'@' -f2 | cut -d'/' -f1)
        sub_dir="$BASE_PATH/$category/$sub_dir_name"
        delete_old_files "$sub_dir"
    done

    # Process archive URLs
    log "Processing ${#ARCHIVE_URLS[@]} archive URLs"
    for i in "${!ARCHIVE_URLS[@]}"; do
        url=${ARCHIVE_URLS[$i]}
        category=${ARCHIVE_CATEGORIES[$i]}
        log "Processing archive URL: $url with category: $category"
        if [[ "$INITIAL_SEEDING" == "false" ]]; then
            dateafter=$(date -d "yesterday" +%Y%m%d)
            download_videos "$url" "$category" "$dateafter" "$PLAYLIST_MODE" "$MUSIC_ONLY"
        else
            download_videos "$url" "$category" "" "$PLAYLIST_MODE" "$MUSIC_ONLY"
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
            download_videos "$url" "$category" "$dateafter" "$PLAYLIST_MODE" "$MUSIC_ONLY"
        else
            dateafter=$(date -d "yesterday" +%Y%m%d)
            download_videos "$url" "$category" "$dateafter" "$PLAYLIST_MODE" "$MUSIC_ONLY"
        fi
        log "Finished processing casual URL: $url"
    done
fi

log "=== YouTube Sync Completed ==="