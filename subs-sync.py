import os
import json
from datetime import datetime, timedelta
from time import sleep
import random
import re
import logging
from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError
import urllib3

# Setup logging with timestamped log files (matching bash-sync.sh)
log_dir = './logs'
os.makedirs(log_dir, exist_ok=True)
log_file = os.path.join(log_dir, f"sync_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Console handler
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_formatter = logging.Formatter('[%(asctime)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
console_handler.setFormatter(console_formatter)

# File handler for all logs
file_handler = logging.FileHandler(log_file)
file_handler.setLevel(logging.INFO)
file_formatter = logging.Formatter('[%(asctime)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
file_handler.setFormatter(file_formatter)

# Add handlers to the logger
logger.addHandler(console_handler)
logger.addHandler(file_handler)

logging.info("=== Starting YouTube Sync ===")

# Load configuration from config.json
with open('./config/config.json', 'r') as config_file:
    config = json.load(config_file)

initial_seeding = config['initial_seeding']
retention_period = config['retention_period']
cookies_file = config['cookies_file']
base_path = config['base_path']
archive_log = "./config/download_archive.txt"

def load_urls(file_path):
    entries = []
    with open(file_path, 'r') as file:
        for line in file:
            line = line.strip()
            if line:  # Check if the line is not empty
                url, category = line.split('|')
                entries.append((url, category))

    random.shuffle(entries)

    urls = {}
    for url, category in entries:
        urls[url] = category

    return urls

archive = load_urls('./config/archive.txt')
casual = load_urls('./config/casual.txt')

def randomised_delay():
    return round(random.uniform(3, 30), 2)

# Function to delete files older than a month
def delete_old_files(directory):
    now = datetime.now()
    cutoff = now - timedelta(days=retention_period)
    for filename in os.listdir(directory):
        file_path = os.path.join(directory, filename)
        if os.path.isfile(file_path):
            file_modified = datetime.fromtimestamp(os.path.getmtime(file_path))
            if file_modified < cutoff:
                os.remove(file_path)
                logging.info(f"Deleted old file: {file_path}")

# Function to clean up titles from special characters
def clean_title(title):
    return re.sub(r'[\\/*?:"<>|]', "", title)

# Function to check if a video with the same title already exists (failover for lost archive)
def check_existing_title(video_info, output_dir):
    """Check if a file with the same title (any extension) already exists."""
    try:
        title = clean_title(video_info.get('title', ''))
        if not title:
            return None
        
        # Search for files with the same title but any extension
        if os.path.exists(output_dir):
            for filename in os.listdir(output_dir):
                # Remove extension from filename
                name_without_ext = os.path.splitext(filename)[0]
                if name_without_ext == title:
                    return os.path.join(output_dir, filename)
        return None
    except Exception as e:
        logging.warning(f"Error checking existing title: {e}")
        return None

# Create directories for the categories
def create_directories(base_path, data):
    for url, category in data.items():
        # Create the main directory
        main_dir = os.path.join(base_path, category)
        os.makedirs(main_dir, exist_ok=True)

        # Extract the sub-directory name from the URL (strip any /tab suffix)
        sub_dir_name = url.split('@')[1].split('/')[0]
        sub_dir = os.path.join(main_dir, sub_dir_name)
        os.makedirs(sub_dir, exist_ok=True)

        logging.info(f"Created directory: {sub_dir}")

# Create directories for 'archive' and 'casual'
create_directories(base_path, archive)
create_directories(base_path, casual)

def normalize_channel_url(url):
    """Append /videos to bare channel URLs to avoid multi-tab traversal (Videos+Shorts+Live)."""
    if re.match(r'https?://www\.youtube\.com/@[^/]+/?$', url):
        return url.rstrip('/') + '/videos'
    return url

def download_videos(url, category, dateafter=None, retries=3):
    url = normalize_channel_url(url)
    delay = randomised_delay()
    logging.info(f"Sleeping for {delay} seconds")
    sleep(delay)  # because YouTube doesn't like it when you download too fast
    logging.info("wake up")
    logging.info(f"Starting download of {url}")

    # First, extract video info to check if it already exists (failover for lost archive)
    info_opts = {
        'quiet': True,
        'no_warnings': True,
        'extract_flat': True,
        'cookiefile': cookies_file,
    }
    
    if dateafter:
        info_opts['dateafter'] = dateafter
    
    try:
        with YoutubeDL(info_opts) as ydl:  # type: ignore
            info = ydl.extract_info(url, download=False)
            if info:
                # Handle both single videos and playlists
                entries = info.get('entries', [info]) if 'entries' in info else [info]
                
                for entry in entries:
                    if entry and entry.get('id'):
                        video_id = entry.get('id')
                        uploader = entry.get('uploader', 'Unknown')
                        output_dir = os.path.join(base_path, category, uploader)
                        
                        # Check if file with same title already exists
                        existing_file = check_existing_title(entry, output_dir)
                        if existing_file:
                            logging.info(f"⚠️  Video already exists: {existing_file}")
                            logging.info(f"Adding video ID {video_id} to archive to prevent future checks")
                            # Add to archive to skip in future
                            with open(archive_log, 'a') as f:
                                f.write(f"youtube {video_id}\n")
    except Exception as e:
        logging.debug(f"Could not pre-check video info: {e}")

    ydl_opts = {
        'outtmpl': f"{base_path}/{category}/%(uploader)s/{clean_title('%(title)s')}.%(ext)s",
        'cookiefile': cookies_file,
        'sleep_interval': 3,
        'max_sleep_interval': 69,
        'sleep_subtitles': 1,
        'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]',
        'noplaylist': True,
        'download_archive': archive_log,
        'quiet': False,
        'no_warnings': True,
        'nopart': True,
        'nocontinue': True,
        'logger': MyLogger(),
        'progress_hooks': [my_hook],
        'extractor_args': {'youtubetab': {'skip': 'authcheck'}},
        'js_runtimes': {'node': {}, 'deno': {}},
        'remote_components': ['ejs:npm'],
    }

    if dateafter:
        ydl_opts['dateafter'] = dateafter

    attempt = 0
    while attempt < retries:
        try:
            with YoutubeDL(ydl_opts) as ydl:  # type: ignore
                result = ydl.download([url])
            return result == 0
        except DownloadError as e:
            if "Premieres" in str(e):
                logging.warning(f"Skipping premiere video: {url}")
                return False
            elif "VPN/Proxy Detected" in str(e):
                logging.warning(f"Skipping video due to VPN/Proxy detection: {url}")
                return False
            elif "This channel does not have a streams tab" in str(e):
                logging.warning(f"Skipping video due to missing streams tab: {url}")
                return False
            elif "This video is available to this channel's members" in str(e):
                logging.warning(f"Skipping members-only video: {url}")
                return False
            elif "This live event will begin" in str(e):
                logging.warning(f"Skipping scheduled streams: {url}")
                return False
            elif "Playlists that require authentication" in str(e):
                logging.warning(f"Skipping video due to authentication requirement: {url}")
                return False
            elif isinstance(e.exc_info[1], urllib3.exceptions.NewConnectionError):
                logging.error(f"Network error: {e}. Retrying in 1 minute...")
                sleep(60)
                attempt += 1
            elif "Read timed out" in str(e):
                logging.error(f"Read timed out error: {e}. Retrying in 5 seconds...")
                sleep(5)
                attempt += 1
            elif "Network is unreachable" in str(object=e):
                logging.error(f"Network is unreachable error: {e}. Retrying in 5 seconds...")
                sleep(5)
                attempt += 1
            else:
                print(e)
                pass

    logging.error(f"Failed to download video after {retries} attempts: {url}")
    return False

# Permanent error phrases that mean a video will never become available
_PERMAFAIL_PHRASES = [
    "Join this channel to get access to members-only content",
    "This video is available to this channel's members",
    "This video is private",
    "Video unavailable",
    "This video has been removed",
    "This video is not available",
    "This video contains content from",  # copyright block
]

class MyLogger(object):
    def debug(self, msg):
        logging.info(msg)  # Log debug messages as info to see yt-dlp output

    def warning(self, msg):
        logging.warning(f"WARNING: {msg}")

    def error(self, msg):
        logging.error(f"ERROR: {msg}")
        # If a video will permanently fail, write it to the download archive so it
        # is never attempted again on future runs (prevents "walking in circles").
        if any(phrase in msg for phrase in _PERMAFAIL_PHRASES):
            match = re.search(r'\[youtube(?::[a-z]+)?\] ([A-Za-z0-9_-]{11}): ', msg)
            if match:
                video_id = match.group(1)
                logging.info(f"Archiving {video_id} (permanent failure – will be skipped on future runs)")
                try:
                    with open(archive_log, 'a') as f:
                        f.write(f"youtube {video_id}\n")
                except Exception as exc:
                    logging.warning(f"Could not write to download archive: {exc}")

def my_hook(d):
    if d['status'] == 'finished':
        filename = d.get('filename', 'unknown')
        logging.info(f'Downloaded: {filename}')
    elif d['status'] == 'error':
        logging.error('Error occurred during download')
    elif d['status'] == 'downloading':
        # Show progress information
        if '_percent_str' in d:
            percent = d.get('_percent_str', 'N/A')
            speed = d.get('_speed_str', 'N/A')
            eta = d.get('_eta_str', 'N/A')
            logging.info(f"Downloading: {percent} at {speed} ETA: {eta}")

logging.info(f"Processing {len(archive)} archive URLs")
for url, category in archive.items():
    logging.info(f"Processing archive URL: {url} with category: {category}")
    dateafter = None
    if not initial_seeding:
        dateafter = (datetime.now() - timedelta(days=1)).strftime('%Y%m%d')

    download_videos(url, category, dateafter)
    logging.info(f"Finished processing archive URL: {url}")

logging.info(f"Processing {len(casual)} casual URLs")
for url, category in casual.items():
    logging.info(f"Processing casual URL: {url} with category: {category}")
    dateafter = None
    if initial_seeding:
        dateafter = (datetime.now() - timedelta(days=30)).strftime('%Y%m%d')
    else:
        dateafter = (datetime.now() - timedelta(days=1)).strftime('%Y%m%d')

    download_videos(url, category, dateafter)

    # Delete old files in casual directories
    sub_dir_name = url.split('@')[1].split('/')[0]
    sub_dir = os.path.join(base_path, category, sub_dir_name)
    delete_old_files(sub_dir)
    logging.info(f"Finished processing casual URL: {url}")

logging.info("=== YouTube Sync Completed ===")