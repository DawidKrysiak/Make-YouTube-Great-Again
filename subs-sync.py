import os
import subprocess
import json
from datetime import datetime, timedelta
from time import sleep
import random

# Load configuration from config.json
with open('./config/config.json', 'r') as config_file:
    config = json.load(config_file)

initial_seeding = config['initial_seeding']
retention_period = config['retention_period']
cookies_file = config['cookies_file']
base_path = config['base_path']
ARCHIVE_FILE = "./config/download_archive.txt"

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

def download_videos(url, category, dateafter=None):
    delay = randomised_delay()
    print(f"Sleeping for {delay} seconds")
    sleep(delay)  # because YouTube doesn't like it when you download too fast
    print("wake up")
    command = [
        'yt-dlp',
        '--output', f"{base_path}/{category}/%(uploader)s/%(title)s.%(ext)s",
        '--cookies', cookies_file,
        '--sleep-interval', '3',
        '--max-sleep-interval', '69',
        '--sleep-subtitles', '1',
        '--format', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]',
        '--no-playlist',
        '--download-archive', ARCHIVE_FILE,
        url
    ]
    if dateafter:
        command.extend(['--dateafter', dateafter])

    print(f"Running command: {' '.join(command)}")
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    stdout, stderr = process.communicate()

    print(stdout)
    print(stderr)

    if "no more videos to download" in stdout.lower() or "no more videos to download" in stderr.lower():
        print("No more videos to download for this URL.")
        return True

    return process.returncode == 0

for url, category in archive.items():
    dateafter = None
    if not initial_seeding:
        dateafter = (datetime.now() - timedelta(days=1)).strftime('%Y%m%d')
    if download_videos(url, category, dateafter):
        break

for url, category in casual.items():
    dateafter = None
    if initial_seeding:
        dateafter = (datetime.now() - timedelta(days=30)).strftime('%Y%m%d')
    else:
        dateafter = (datetime.now() - timedelta(days=1)).strftime('%Y%m%d')
    if download_videos(url, category, dateafter):
        break

    # Delete old files in casual directories
    sub_dir_name = url.split('@')[1]
    sub_dir = os.path.join(base_path, category, sub_dir_name)
    delete_old_files(sub_dir)