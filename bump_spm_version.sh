#!/bin/bash

VERSION_REGEX="^[0-9]+.[0-9]+.[0-9]+$"

if [ -z "$1" ]; then
  echo "NEW_VERSION was not provided"
  exit 1
elif [[ ! $1 =~ $VERSION_REGEX ]]; then
  echo "Invalid version number: $1"
  exit 2
else
  NEW_VERSION=$1  
fi

for FILE in $(grep -lR "minimumVersion = " *.xcodeproj)
do
  sed -Ei '' -e "s/minimumVersion = [0-9]+\.[0-9]+\.[0-9]+/minimumVersion = $NEW_VERSION/g" $FILE
done
