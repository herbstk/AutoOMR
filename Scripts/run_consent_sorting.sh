#!/bin/bash
# This script is part of the virusfinder scanning pipeline
## this script should be run after a batch has been analysed
## it will sort consents out of the processed_failed directory

gnome-terminal --title "collecting consent scans" -- \
               bash -c "~/AutoOMR/Scripts/consent_sorting.sh Scans_processed 2>&1 | tee -a Logs/run_consent_sorting.log"
