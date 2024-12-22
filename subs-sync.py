import os
import subprocess
from datetime import datetime, timedelta

# This variable can be True or False.
# If True, the script will download all the videos from the channels specified in the 'archive' and 'casual' dictionaries.
# If False, the script will download only the latest videos from the channels specified in the 'archive' and 'casual' dictionaries.

initial_seeding = False

# The 'archive' and 'casual' dictionaries contain the URLs of the YouTube channels that you want to sync.
# Archive contains channels that you want to archive in their entirety and retain forever.
# Casual contains channels that you want to sync only the latest videos and delete them after a period of time.

retention_period = 30

# The 'cookies_file' variable contains the path to the cookies file that you have saved from your browser.
cookies_file = 'cookies.txt'

"""
Below are the URLs of the YouTube channels that you want to sync.
The URLs are mapped to the categories that you want to sync them to.
The categories are the names of the directories where the videos will be saved.
The reason for two dictionaires is that you may want to sync some channels in a different way.
For me, archive contains channels that I want to archive in their entirety.
Caual contains channels that I want to sync only the latest videos and probably delete them after a few months.
"""


archive = {
        "https://www.youtube.com/@TheFatFiles" : "history",
        "https://www.youtube.com/@the_fat_electrician" : "history",
        "https://www.youtube.com/@amazingpolishhistory" : "history",
        "https://www.youtube.com/@WorldHistoryVideos" : "history"
    }

casual = {
        "https://www.youtube.com/@AllThingsSecured" : "knowledge",
        "https://www.youtube.com/@BaumgartnerRestoration" : "art",
        "https://www.youtube.com/@CGPGrey" : "knowledge",
        "https://www.youtube.com/@CinemaStix" : "entertainment",
        "https://www.youtube.com/@CinemaWins" : "entertainment",
        "https://www.youtube.com/@CinemaSins" : "entertainment",
        "https://www.youtube.com/@HistoryMatters" : "history",
        "https://www.youtube.com/@historyofeverythingpodcast" : "history",
        "https://www.youtube.com/@HistoryoftheEarth" : "history",
        "https://www.youtube.com/@historypop" : "history",
        "https://www.youtube.com/@HistoryScope" : "history",
        "https://www.youtube.com/@HistoryTime" : "history",
        "https://www.youtube.com/@HooverInstitution" : "journalism",    
    }

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

# Specify the base path where directories will be created. Dot means 'wherever the script is'

base_path = "."

# Create directories for 'archive' and 'casual'
create_directories(base_path, archive)
create_directories(base_path, casual)

def download_videos(url, category, dateafter=None):
    command = [
        'yt-dlp',
        '--output', f"{base_path}/{category}/%(uploader)s/%(title)s.%(ext)s",
        '--cookies', cookies_file,
        '--verbose',
        url
    ]
    if dateafter:
        command.extend(['--dateafter', dateafter])
    subprocess.run(command)

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