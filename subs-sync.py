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
    return round(random.uniform(3, 10), 2)  # Shortened delay for testing

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
        
        # Check if the URL contains '@' before splitting
        if '@' in url:
            sub_dir_name = url.split('@')[1]
            sub_dir = os.path.join(main_dir, sub_dir_name)
            os.makedirs(sub_dir, exist_ok=True)
            print(f"Created directory: {sub_dir}")
        else:
            print(f"Invalid URL format (missing '@'): {url}")

# Create directories for 'archive' and 'casual'
create_directories(base_path, archive)
create_directories(base_path, casual)

def download_videos(url, category, dateafter=None):
    error_count = 0
    while error_count < 3:
        delay = randomised_delay()
        print(f"Sleeping for {delay} seconds before downloading {url}")
        sleep(delay)  # because YouTube doesn't like it when you download too fast
        
        command = [
            'yt-dlp',
            '--output', f"{base_path}/{category}/%(uploader)s/%(title)s.%(ext)s",
            '--cookies', cookies_file,
            '--verbose',
            '--format', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]',
            url
        ]
        if dateafter:
            command.extend(['--dateafter', dateafter])
        
        print(f"Running command: {' '.join(command)}")
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=600)  # Timeout after 10 minutes
      
            print(f"Command output:\n{result.stdout}")
            print(f"Command error (if any):\n{result.stderr}")
            
            if "Video unavailable. This content isn’t available." in result.stderr:
                error_count += 1
                print(f"Error: Video unavailable. Attempt {error_count}/3")
                if error_count == 3:
                    print("Stopping process for 24 hours due to repeated 'Video unavailable' errors.")
                    sleep(24 * 60 * 60)  # Sleep for 24 hours
            elif "Sign in to confirm you’re not a bot" in result.stderr:
                print("Error: Sign in required. Please check your cookies.")
                break
            else:
                break
        except subprocess.TimeoutExpired:
            print(f"Command timed out. Retrying...")
            error_count += 1
            if error_count == 3:
                print("Stopping process for 24 hours due to repeated timeouts.")
                sleep(24 * 60 * 60)  # Sleep for 24 hours

def initial_seeding_download(url, category, is_archive=False):
    current_date = datetime.now()
    while True:
        if not is_archive:
            dateafter = (current_date - timedelta(days=30)).strftime('%Y%m%d')
            download_videos(url, category, dateafter)
            # Check if there are no more videos to download
            result = subprocess.run(['yt-dlp', '--dateafter', dateafter, url], capture_output=True, text=True)
            if "No more videos to download" in result.stdout:
                print(f"No more videos to download for {url}")
                break
        else:
            download_videos(url, category)
            # Check if there are no more videos to download
            result = subprocess.run(['yt-dlp', url], capture_output=True, text=True)
            if "No more videos to download" in result.stdout:
                print(f"No more videos to download for {url}")
                break
        current_date -= timedelta(days=30)

for url, category in archive.items():
    if initial_seeding:
        initial_seeding_download(url, category, is_archive=True)
    else:
        dateafter = (datetime.now() - timedelta(days=1)).strftime('%Y%m%d')
        download_videos(url, category, dateafter)

for url, category in casual.items():
    if initial_seeding:
        dateafter = (datetime.now() - timedelta(days=30)).strftime('%Y%m%d')
        download_videos(url, category, dateafter)
    else:
        dateafter = (datetime.now() - timedelta(days=1)).strftime('%Y%m%d')
        download_videos(url, category, dateafter)
    
    # Delete old files in casual directories if not initial seeding
    if not initial_seeding:
        sub_dir_name = url.split('@')[1]
        sub_dir = os.path.join(base_path, category, sub_dir_name)
        delete_old_files(sub_dir)