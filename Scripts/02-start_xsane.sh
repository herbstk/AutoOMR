#!/bin/bash
# This script is part of the virusfinder scanning pipeline
## this file should be executed after initialization of the working directory
## it starts the xsane scanning application

## TODO CAN ONE SET THE MULTIPAGE SCANNING DIRECTORY?

xsane --device-settings ~/AutoOMR/Brother:ADS-2400N.drc &
