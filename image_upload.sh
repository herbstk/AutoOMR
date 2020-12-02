#!/bin/bash
TMPDIR=$(mktemp -d);
export $TMPDIR
find . -name '*-[1,2].png' -exec sh -c 'nf="$(basename {})"; echo $nf; convert -resize 816x1161 {} - > "$TMPDIR/$nf"' \;

scp $TMPDIR/* kherbst@virusfinder.de:~/p_q_scans/
