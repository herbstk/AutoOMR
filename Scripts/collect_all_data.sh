#!/bin/bash
# This script is part of the virusfinder scanning pipeline
## this script should is invoked by a runner script and usually shouldn't be run on its own
## it will collect and downsize page 1 and page 2 of scans and then upload to the virusfinder server

for d in "$1"/*; do
    if [[ -d "$d" ]]; then
        if [[ ! -f "$d"/uploaded_answers ]]; then
            echo "Uploading answers for directory $d..."
            Rscript ~/AutoOMR/Scripts/collect_and_upload_data.R $d
            touch "$d"/uploaded_answers
        else
            echo "Answers of directory $d already have been uploaded. Skipping..."
        fi
    fi
done
sleep 5




