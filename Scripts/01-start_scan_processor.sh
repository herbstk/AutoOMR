#!/bin/bash
# This script is part of the virusfinder scanning pipeline
## this file should be executed after initialization of the working directory
## it starts the scan processor pipeline

cd Scanning
gnome-terminal --title "scan processor (press Ctrl-C to STOP)" -- \
               bash -c "python3 ~/AutoOMR/auto_omr.py -v -d ~/AutoOMR/Templates ../Scans_processed 2>&1 | tee -a ../Logs/01-start_scan_processor.log"
