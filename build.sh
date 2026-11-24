#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building MeetTouchBar..."
mkdir -p MeetTouchBar.app/Contents/MacOS

clang -fobjc-arc -O2 \
    -framework Cocoa \
    -framework Carbon \
    -framework ApplicationServices \
    -F /System/Library/PrivateFrameworks \
    -framework DFRFoundation \
    main.m -o MeetTouchBar.app/Contents/MacOS/MeetTouchBar

cp MeetTouchBar.app/Contents/MacOS/MeetTouchBar ./MeetTouchBar
echo "Build complete: MeetTouchBar.app"
