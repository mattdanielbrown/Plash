#!/bin/bash

set -e

echo "Building Flux Release..."
xcodebuild -project Flux.xcodeproj -scheme Flux -configuration Release clean build

echo "Killing running Flux app..."
killall Flux 2>/dev/null || true

echo "Removing old version from Applications..."
rm -rf /Applications/Flux.app

echo "Copying new version to Applications..."
cp -R ~/Library/Developer/Xcode/DerivedData/Flux-*/Build/Products/Release/Flux.app /Applications/

echo "Launching Flux..."
open /Applications/Flux.app

echo "Done!"
