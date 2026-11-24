# MeetTouchBar

Native macOS Touch Bar integration for Google Meet calls on MacBook Pro (2016-2020).

## Features
- **Microphone Toggle**: Visual red highlight when unmuted
- **Camera Toggle**: Visual blue highlight when active
- **Raise / Lower Hand**: Visual orange indicator
- **Instant Emoji Reactions**: Heart, Like, Party, Clap, Laugh, Wow, Sad, Think, Dislike
- **Focus Meet Tab**: Jump directly to the active meeting tab from any app
- **Low Resource**: Completely dormant when no meetings are active (0.0% CPU)

## How it works
1. **MeetTouchBar.app**: Native macOS daemon controlling the Touch Bar via AppKit DFR APIs.
2. **MeetTouchBar Bridge**: Lightweight Chrome/Brave extension communicating call status with the app over local IPC.

## Installation
1. Download `MeetTouchBar-v1.0.0.zip` from [Releases](https://github.com/mvmbmy0-gif/MeetTouchBar/releases).
2. Unzip the archive.
3. Move `MeetTouchBar.app` to `/Applications` or your home directory and launch it.
4. In your browser (Chrome/Brave/Edge), open `chrome://extensions`, enable **Developer mode**, click **Load unpacked**, and select the `Extension` folder.

## Building from source
```bash
./build.sh
```
