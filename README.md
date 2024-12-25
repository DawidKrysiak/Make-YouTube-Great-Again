# Make YouTube Great Again

YouTube (aka.CorpoTube) has become unwatchable recently - it's worse than cable/satellite TVs ever were.
Let me give you an example from one channel that shall remain nameless:
A video about some stupidly expensive monitor/tv wall thingy (they don't have to send it back, so yes, they just received MANY thousands of dollars under the table), sponsored by... Intel (so there are at least two mentions of that during the video), then... "word from our sponsor...Ridge Wallet" (didn't Intel sponsor that a second ago???), and then... YouTube pre-roll/mid-rolls. That's the sad state of once great service.

Another even worse element is YT's "social" aspect - almost every time I go to the comment section, I have the urge to drive a screwdriver through my eyeball.

And of course - if you dare to use ad-block, piHole, VPN or anything else that disrupts Google's nefarious activities, you'll be battered with verifications, CAPTCHAs etc...

# Solution #1
Vote with your legs - walk away from channels more focused on sponsor plugs than actual content.
Better yet, focus on limiting your screen time with YouTube. Go outside, go to a gym... 

# Solution #2
Some channels are still worth watching - they might have sponsor plugs but it's not obnoxious and the content is worth it.
What is not worth it is the comments section (most of the time) and driving screen addiction.

Soo.... what do we do?
Fortunately, there is an awesome project - yt-dlp [https://github.com/yt-dlp](https://github.com/yt-dlp)
Install it using the appropriate installer for your OS and you are sorted - you can download complete channels and watch the content at your own pace, without YT ads or an urge to read the comments and loose faith in humanity.

# Why this project exist?
I came up with the idea of reducing my visits to youtube.com as much as it's possible but without losing touch with the channels worth watching.
So, using yt-dlp's functionality of downloading only videos from a specific period, I can "synchronise" my local archive with the channel's content.

# How to use it?
Install yt-dlp by yourself. I initially tried to use Python's modules but due to recent requirements from Python (vENV) which make it more and more convoluted and confusing for casual users who just want to install something and forget about it, I opted for more involved approach:
* install yt-dlp following [https://github.com/yt-dlp/yt-dlp?tab=readme-ov-file#installation](https://github.com/yt-dlp/yt-dlp?tab=readme-ov-file#installation)
* Install Python if you don't have it already (everything 3.x should be working fine, I'm not using any fancy solutions that would require a bleeding edge version)
* clone this repo
* install in your browser a plugin called "get cookies.txt LOCALLY" (unless you know how to extract cookies from your browser! yt-dlp's solution of `yt-dlp --cookies-from-browser chrome --cookies cookies.txt https://www.youtube.com/` works SOMETIMES - the plugin solution works every time).

**OK, FULL STOP.**

That part is probably the most difficult and frustrating part of this whole project and took me longer to figure out than writing the actual code (not even joking!).
You have to understand that YouTube will do ANYTHING to make sure you only consume their content the way THEY want you to and they will go above and beyond to make your life miserable if you don't.
The solution that works for me (for now):
* Set up your browser extension to allow it to work in incognito mode (in my case it was my password manager and `get cookies.txt LOCALLY`)
* open an incognito session
* log in to YT
* open a video and let it play 
* using the `get cookies.txt LOCALLY` extension, download the cookies and put them in `cookies.txt` file
* close the incognito window. 

That process ensures that those cookies will not be imediately invalidated by Youtube - content comes from a unique login session that is never overwritten by your activity because... you will never log in to that unique incognito session ever again (if you download the cookies from the normal session, cookies might be useless in a couple of MINUTES!)

* populate the 'archive.txt' and 'casual.txt' files with your favourite channels and assign them a category. The format is `URL`|`category`. For example:

```
https://www.youtube.com/@AllThingsSecured|knowledge
https://www.youtube.com/@BaumgartnerRestoration|art
```
* open config.json in a text editor and adjust the variables:
    * `"initial_seeding": false` - this variable should be set to `true` before you run the app for the first time - it ensures that the app will download ALL videos from `archive` category and the last 30 days from `causal` category. Once it's done, switch  it back to `false` so when it's triggered, only downloads videos from the last 24h
    * `"retention_period": 30` - this variable defines the retetion period of the `casual` videos after which those will be deleted. This variable does not apply to `archive` category which by definition - retains EVERYTHING FOREVER. If you don't want to retain a certain channel any longer, just move the URL from  `archive.txt` to `casual.txt` and the next time you run the script, it will take care of the files for you.
    * adjust `"base_path" : "."` line and put the absolute path to a location where you want the videos to be saved (by default it will be the same directory where subs-sync.py resides - that's what the dot means), but realistically it should be a path to a drive/location with plenty of storage
* execute `python3 subs-sync.py` and check the output
* the script will create a directory for each category you assigned to any of the videos (in my example it would be: knowledge, politics, history, Computer Science and so on)
* the script will create a sub-directory with the name of the channel and will put all the videos it manages to download into that sub-directory
* once the initial seeding is complete, turn the `initial_seeding` to `false` and set up a cron job (or scheduled task on Windows) to run the script daily
* enjoy content with no ads and comments

