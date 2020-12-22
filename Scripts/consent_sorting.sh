#!/bin/bash
# This script is part of the virusfinder scanning pipeline
## this script should be invoked by a runner script and usually shouldn't be run on its own
## it will walk through the failed scans and will collect consents

for d in "$1"/*; do
    if [[ -d "$d" ]]; then
        if [[ ! -d "$2/$d/processed_failed_consents" ]]; then
            echo "Processing failed scans in directory $d..."
            mkdir -p "$2/$d/processed_failed_consents"
            python3 ~/AutoOMR/consent_sorter.py -d -v "$d/processed_failed" "$2/$d/processed_failed_consents"
        else
            echo "Failed scans in directory $d already have been sorted. Skipping..."
        fi
    fi
done
sleep 5
