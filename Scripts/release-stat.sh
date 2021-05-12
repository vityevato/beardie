#!/bin/bash

TAG=$( curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/Stillness-2/beardie/tags | python3 -c 'import sys, json; arr=(json.load(sys.stdin)); print( arr[0]["name"])' )
echo "Release tag: $TAG"
curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/Stillness-2/beardie/releases/tags/$TAG | python3 -c 'import sys, json; dict=(json.load(sys.stdin)); print("\n".join([ "Downloads {} = {}".format(asset["name"], asset["download_count"]) for asset in dict["assets"]]))'