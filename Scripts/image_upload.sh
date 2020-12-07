#!/bin/bash
# This script is part of the virusfinder scanning pipeline
## this script should is invoked by a runner script and usually shouldn't be run on its own
## it will collect and downsize page 1 and page 2 of scans and then upload to the virusfinder server

for d in "$1"/*; do
    if [[ -d "$d" ]]; then
        if [[ ! -f "$d"/uploaded_images ]]; then
            echo "Uploading images for directory $d..."
            TMPDIR=$(mktemp -d);
            find "$d" -name '*-[1,2].png' -type f | \
                xargs -I{} sh -c \
                      'nf="$0/$(basename {})"; echo $nf; convert -resize 816x1161 {} - > $nf' $TMPDIR
            scp $TMPDIR/*.png kherbst@virusfinder.de:~/p_q_scans/
            touch "$d"/uploaded_images
        else
            echo "Images in directory $d already have been uploaded. Skipping..."
        fi
    fi
done
sleep 5
