#!/bin/bash

echo "Creating XC Config Constants Header File: ${XC_CONSTANT_HEADER_FILE}"
/usr/bin/env | /usr/bin/grep -e "^[[:blank:]]*${XC_PREFIX_FOR_CONSTANTS}" | /usr/bin/sed 's/\(.*\)=\(.*\)/#define \1    @"\2"/' > "${XC_CONSTANT_HEADER_FILE}"

echo "Creating XC Config Constants JS File: ${XC_CONSTANT_JS_FILE}"
echo "const BSConstants = {" > "${XC_CONSTANT_JS_FILE}"
/usr/bin/env | /usr/bin/grep -e "^[[:blank:]]*${XC_PREFIX_FOR_BROWSER_CONSTANTS}" | /usr/bin/sed 's/\(.*\)=\(.*\)/\1: "\2",/' >> "${XC_CONSTANT_JS_FILE}"
echo "}" >> "${XC_CONSTANT_JS_FILE}"

echo "Creating tag.txt with tag name for this build: ${BEARDIE_LOCAL_BUILD_DIR}/tag.txt"
echo "v${BS_VERSION}.${BS_BUILD}.${CONFIGURATION}"> ${BEARDIE_LOCAL_BUILD_DIR}/tag.txt
