#!/bin/bash

APP_PATH=$1

if [ "$APP_PATH" == "" ]; then
echo "Needs app path as argument"
exit 1
fi

INFO_PLIST=${APP_PATH}/Contents/Info.plist
# retrieve version and build number from the app itself
build_number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
version=$(/usr/libexec/PlistBuddy -c "Print :BSVersion" "$INFO_PLIST")
channel=$(/usr/libexec/PlistBuddy -c "Print :BSConfiguration" "$INFO_PLIST")
TAG=v$version.$build_number.$channel

execdir="$( cd "$( dirname "$0" )/" && pwd )"
pushd "$execdir/.."
git tag $TAG || exit 1
git push origin $TAG  || exit 1 
popd