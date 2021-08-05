#!/bin/bash

#  extruct-pause-names.sh
#  Beardie
#
#  Created by Roman Sokolov on 04.08.2021.
#  Copyright © 2021 GPL v3 http://www.gnu.org/licenses/gpl.html

LOCALES="/System/Applications/Podcasts.app/Contents/Resources/"

OUTPUT=$(dirname $0)/Podcasts-Pause-Names.h
echo "#define PODCASTS_PAUSE_NAMES @[\\" > "$OUTPUT"

for d in "$LOCALES/"*.lproj;
do
plutil -p "$d/Localizable.strings" | grep \"EPISODE_ACTION_PAUSE\" | python3 -c 'import re, sys
for line in sys.stdin.readlines():
    result = re.search(r"\=>\s(\".+\")", line)
    if result != None:
        print("@{},\\".format(result.group(1)))' >> "$OUTPUT"
done

echo "]" >> "$OUTPUT"
