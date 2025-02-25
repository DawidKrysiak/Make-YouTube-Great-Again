import os
import json
from datetime import datetime, timedelta
from time import sleep
import random
import re
from yt_dlp import YoutubeDL, DownloadError
import urllib3

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
                print(f"Deleted old file: {file_path}")

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

        print(f"Created directory: {sub_dir}")

# Create directories for 'archive' and 'casual'
create_directories(base_path, archive)
create_directories(base_path, casual)

def download_videos(url, category, dateafter=None, retries=3):
    delay = randomised_delay()
    print(f"Sleeping for {delay} seconds")
    sleep(delay)  # because YouTube doesn't like it when you download too fast
    print("wake up")

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
        'no_warnings': False,
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
                print(f"Skipping premiere video: {url}")
                return False
            elif "VPN/Proxy Detected" in str(e):
                print(f"Skipping video due to VPN/Proxy detection: {url}")
                return False
            elif "This channel does not have a streams tab" in str(e):
                print(f"Skipping video due to missing streams tab: {url}")
                return False
            elif isinstance(e.exc_info[1], urllib3.exceptions.NewConnectionError):
                print(f"Network error: {e}. Retrying in 1 minute...")
                sleep(60)
                attempt += 1
            else:
                raise e

    print(f"Failed to download video after {retries} attempts: {url}")
    return False

class MyLogger(object):
    def debug(self, msg):
        if msg.startswith('[download]'):
            print(msg)
        elif msg.startswith('[youtube]'):
            print(msg)
        elif msg.startswith('[info]'):
            print(msg)

    def warning(self, msg):
        print(f"WARNING: {msg}")

    def error(self, msg):
        print(f"ERROR: {msg}")

def my_hook(d):
    if d['status'] == 'finished':
        print('Done downloading, now converting ...')
    elif d['status'] == 'error':
        print('Error occurred during download')
    elif d['status'] == 'downloading':
        print(f"Downloading: {d['_percent_str']} at {d['_speed_str']} ETA: {d['_eta_str']}")

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