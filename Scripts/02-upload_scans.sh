#!/bin/bash
# This script is part of the virusfinder scanning pipeline
## this script should be run once there batch of scans has been processed
## it will collect and downsize page 1 and page 2 of scans and then upload to the virusfinder server
## then it will collect the automatically determined answers and transfer them to the database

gnome-terminal --title "collecting and uploading scan images" -- \
               bash -c "~/AutoOMR/Scripts/image_upload.sh Scans_processed 2>&1 | tee -a Logs/02-upload_scans.log"
