import os
import json
from datetime import datetime, timedelta
from time import sleep
import random
import re
import logging
from yt_dlp import YoutubeDL, DownloadError
import urllib3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

# Handler for logging INFO level messages to info.log
info_handler = logging.FileHandler('info.log')
info_handler.setLevel(logging.INFO)
info_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
info_handler.setFormatter(info_formatter)

# Handler for logging ERROR level messages to errors.log
error_handler = logging.FileHandler('errors.log')
error_handler.setLevel(logging.ERROR)
error_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
error_handler.setFormatter(error_formatter)

# Add handlers to the logger
logger.addHandler(info_handler)
logger.addHandler(error_handler)

# Load configuration from config.json
with open('./config/config.json', 'r') as config_file:
    config = json.load(config_file)

initial_seeding = config['initial_seeding']
retention_period = config['retention_period']
cookies_file = config['cookies_file']
base_path = config['base_path']
archive_log = "./config/download_archive.txt"

def load_urls(file_path):
    urls = {}
    with open(file_path, 'r') as file:
        for line in file:
            line = line.strip()
            if line:  # Check if the line is not empty
                url, category = line.split('|')
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

# Create directories for the categories
def create_directories(base_path, data):
    for url, category in data.items():
        # Create the main directory
        main_dir = os.path.join(base_path, category)
        os.makedirs(main_dir, exist_ok=True)

        # Extract the sub-directory name from the URL
        sub_dir_name = url.split('@')[1]
        sub_dir = os.path.join(main_dir, sub_dir_name)
        os.makedirs(sub_dir, exist_ok=True)

        logging.info(f"Created directory: {sub_dir}")

# Create directories for 'archive' and 'casual'
create_directories(base_path, archive)
create_directories(base_path, casual)

def download_videos(url, category, dateafter=None, retries=3):
    delay = randomised_delay()
    logging.info(f"Sleeping for {delay} seconds")
    sleep(delay)  # because YouTube doesn't like it when you download too fast
    logging.info("wake up")

    ydl_opts = {
        'outtmpl': f"{base_path}/{category}/%(uploader)s/{clean_title('%(title)s')}.%(ext)s",
        'cookiefile': cookies_file,
        'sleep_interval': 3,
        'max_sleep_interval': 69,
        'sleep_subtitles': 1,
        'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]',
        'noplaylist': True,
        'download_archive': archive_log,
        'quiet': True,
        'no_warnings': True,
        'logger': MyLogger(),
        'progress_hooks': [my_hook],
    }

    if dateafter:
        ydl_opts['dateafter'] = dateafter

    attempt = 0
    while attempt < retries:
        try:
            with YoutubeDL(ydl_opts) as ydl:
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
            elif isinstance(e.exc_info[1], urllib3.exceptions.NewConnectionError):
                logging.error(f"Network error: {e}. Retrying in 1 minute...")
                sleep(60)
                attempt += 1
            elif "Read timed out" in str(e):
                logging.error(f"Read timed out error: {e}. Retrying in 5 seconds...")
                sleep(5)
                attempt += 1
            else:
                raise e

    logging.error(f"Failed to download video after {retries} attempts: {url}")
    return False

class MyLogger(object):
    def debug(self, msg):
        pass  # Do nothing for debug messages

    def warning(self, msg):
        logging.warning(f"WARNING: {msg}")

    def error(self, msg):
        logging.error(f"ERROR: {msg}")

def my_hook(d):
    if d['status'] == 'finished':
        logging.info('Done downloading, now converting ...')
    elif d['status'] == 'error':
        logging.error('Error occurred during download')
    elif d['status'] == 'downloading':
        pass  # Do nothing for downloading messages

for url, category in archive.items():
    dateafter = None
    if not initial_seeding:
        dateafter = (datetime.now() - timedelta(days=1)).strftime('%Y%m%d')
    
    download_videos(url, category, dateafter)

for url, category in casual.items():
    dateafter = None
    if initial_seeding:
        dateafter = (datetime.now() - timedelta(days=30)).strftime('%Y%m%d')
    else:
        dateafter = (datetime.now() - timedelta(days=1)).strftime('%Y%m%d')

    download_videos(url, category, dateafter)

    # Delete old files in casual directories
    sub_dir_name = url.split('@')[1]
    sub_dir = os.path.join(base_path, category, sub_dir_name)
    delete_old_files(sub_dir)