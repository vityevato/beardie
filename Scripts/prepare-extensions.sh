#!/bin/bash

#  prepare-extensions.sh
#  BeardedSpice
#
#  Created by Roman Sokolov on 08.01.2018.
#  Copyright © 2018 GPL v3 http://www.gnu.org/licenses/gpl.html

if [ ! "$1" == "build" ]; then
echo "================================================="
echo "Prepare browser extensions..."
echo "================================================="
fi

EXTENSIONS="${SRCROOT}/BrowserExtensions"
EXTENSION_CHROME="${EXTENSIONS_BUILD_DIR}/Beardie.chrome"

rm -Rf "${EXTENSIONS_BUILD_DIR}"
mkdir -pv "${EXTENSIONS_BUILD_DIR}"

echo " "
echo "Prepare Google Chrome browser extension..."
echo "-------------------------------------------------"
rm -Rf "${EXTENSION_CHROME}"
mkdir -pv "${EXTENSION_CHROME}"
cp -vR "${EXTENSIONS}/chrome/" "${EXTENSION_CHROME}/" || exit 1
cp -vR "${EXTENSIONS}/sharedFiles/shared" "${EXTENSION_CHROME}/shared"
cp -vR "${EXTENSIONS}/sharedFiles/icon" "${EXTENSION_CHROME}/icon"

echo "Apply env vars to manifest.json"
Template=$( cat "${EXTENSION_CHROME}/manifest.json" | sed "s/\"/\\\\\"/g" )
eval "echo \"$Template\"" > "${EXTENSION_CHROME}/manifest.json" || exit 1

echo "Copy constant.js to extension folder"
cp -fpv "${XC_CONSTANT_JS_FILE}" "${EXTENSION_CHROME}/constants.js" || exit 1

/usr/bin/ditto -c -k "$EXTENSION_CHROME" "${EXTENSION_CHROME}.zip"

echo " "
echo "Prepare Now Playing Chrome extension..."
echo "-------------------------------------------------"
EXTENSION_NP="${EXTENSIONS_BUILD_DIR}/Beardie-NowPlaying.chrome"
rm -Rf "${EXTENSION_NP}"
mkdir -pv "${EXTENSION_NP}"
cp -vR "${EXTENSIONS}/nowplaying/chrome/" "${EXTENSION_NP}/" || exit 1
cp -vR "${EXTENSIONS}/nowplaying/shared" "${EXTENSION_NP}/shared"
cp -vR "${EXTENSIONS}/nowplaying/icons" "${EXTENSION_NP}/icons"
Template=$( cat "${EXTENSION_NP}/manifest.json" | sed "s/\"/\\\\\"/g" )
eval "echo \"$Template\"" > "${EXTENSION_NP}/manifest.json" || exit 1
cp -fpv "${XC_CONSTANT_JS_FILE}" "${EXTENSION_NP}/constants.js" || exit 1
/usr/bin/ditto -c -k "$EXTENSION_NP" "${EXTENSION_NP}.zip"

echo "Done"

if [ ! "$1" == "build" ]; then
echo " "
echo "-------------------------------------------------"
echo "Reveal in Finder"
echo "-------------------------------------------------"
APPLESCRIPTFOROPENFOLDER="
tell application \"Finder\"
activate
reveal (\"${EXTENSIONS_BUILD_DIR}/\" as POSIX file)
end tell
"

echo "$APPLESCRIPTFOROPENFOLDER" | osascript
fi
