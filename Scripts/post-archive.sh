#!/bin/bash

execdir="$( cd "$( dirname "$0" )/" && pwd )"


echo " "
echo "Copy extensions to xCode build folder..."
echo "-------------------------------------------------"

DST_PATH="${ARCHIVE_PATH}/Products/${EXTENSION_BUILD_NAME}"
mkdir -pv "${DST_PATH}"
cp -v "${EXTENSIONS_BUILD_DIR}/"*.zip "${DST_PATH}/" || exit 1

echo "Done"
touch "${ARCHIVE_PATH}"
