#!/bin/bash

APP_NAME="subs-sync.py"

if ! pgrep -f "$APP_NAME" > /dev/null; then
    echo "$APP_NAME is not running. Starting the application."
    # Start the application
    cd /home/< user >/Make-YouTube-Great-Again && /usr/bin/python3 subs-sync.py & # Use the correct command line to start your application
else
    echo "$APP_NAME is already running."
fi