# Make YouTube Great Again

YouTube (aka.CorpoTube) became absolutely unwatchable recently - it's worse than cable/satellite TVs EVER WERE.
Let me give you an example from one channel that shall remain nameless:
A video about LG monitor/tv (they don't have to send it back, so yes, they just received MANY thousands of dollars under the table), sponsored by... Intel (so there are at least two mentions of that during the video), then... "word from our sponsor...Ridge Wallet" (didn't Intel sponsor that a second ago???), and then... YouTube pre-roll/mid-rolls. That's the sad state of once great service.

Another even worse element is the "social" aspect of YT - almost every time I go to the comment section, I have the urge to drive a screwdriver through my eyeball.

And of course - if you dare to use ad-block, piHole, VPN or anything else that disrupts Google's nefarious activities, you'll be battered with verifications, CAPTCHAs etc...

# Solution #1
Vote with your legs - walk away from channels that are more focused on sponsor plugs than actual content.
Better yet, focus on limiting your screen time with YouTube. Go outside, go to a gym... 

# Solution #2
There are some channels that are still worth watching - they might have sponsor plugs but it's not obnoxious and the content is worth it.
What is not worth it is the comments section (most of the time) and driving screen addiction.

Soo.... what do we do?
Fortunately, there is an awesome project - yt-dlp [https://github.com/yt-dlp](https://github.com/yt-dlp)
Install it using the appropriate installer for your OS and you are sorted - you can download complete channels and watch the content at your own pace, without YT ads or an urge to read the comments and loose faith in humanity.

# Why this project exist?
I came up with an idea of reducing my visits to youtube.com as much as it's possible but without losing touch with the channels worth watching.
So, using yt-dlp's functionality of downloading only videos from a specific period, I can "synchronise" my local archive with the channel's content.

# How to use it?
Install yt-dlp by yourself. I initially tried to use Python's modules but due to recent requirements from Python (vENV) which makes it more and more convoluted and confusing for casual users who just want to install something and forget about it, I opted for more involved approach:
* install yt-dlp following [https://github.com/yt-dlp/yt-dlp?tab=readme-ov-file#installation](https://github.com/yt-dlp/yt-dlp?tab=readme-ov-file#installation)
* install python if you don't have it already (everyhing 3.x should be working fine, I'm not using any fancy solutions that would require a bleeding edge version)
* clone this repo
* install in your browser a plugin called "get cookies.txt LOCALLY" (unless you know how to extract cookies from your browser! yt-dlp's solution of `yt-dlp --cookies-from-browser chrome --cookies cookies.txt https://www.youtube.com/` works SOMETIMES - the plugin solution works every time)
* open subs-sync.pl in a text editor and just read the in-line documentation. All you need to know is there, but in short:
* populate the 'archive' and 'casual' dictionaries with your favourite channels and assign them a category.
* log in to youtube in chrome/brave and extract the cookies and save them to cookies.txt
* adjust `base_path = "."` line and put the absolute path to a location where you want the videos to be saved (by default it will be the same directory where subs-sync.py resides - that's what the dot means)
* execute `python3 subs-sync.py` and check the output
* script will create a directory for each category you assigned to any of the videos (in my example it would be: knowledge, politics, history, Computer Science and so on)
* script will create a sub-directory with the name of the channel and will put all the videos it manages to download into that sub-directory
* for the `casual` category, videos will be retained for only 30 days, but you can adjust that by changing the value of `retention_period = 30`
