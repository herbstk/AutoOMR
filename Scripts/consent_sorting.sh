#!/bin/bash
# This script is part of the virusfinder scanning pipeline
## this script should be invoked by a runner script and usually shouldn't be run on its own
## it will walk through the failed scans and will collect consents

for d in "$1"/*; do
    if [[ -d "$d" ]]; then
        d_failed="$d/processed_failed"
        if [[ ! -d "$d_failed" ]]; then
            echo "Processing failed scans in directory $d..."
            cd "$d_failed"
            python3 ~/AutoOMR/consent_sorter.py -d -v "$d/processed_failed_consents"
        else
            echo "Failed scans in directory $d already have been sorted. Skipping..."
        fi
    fi
done
sleep 5
