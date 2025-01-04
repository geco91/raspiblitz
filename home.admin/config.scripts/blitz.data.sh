#!/bin/bash
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 >&2 echo "# managing the data drive(s) with new bootable setups for RaspberryPi, VMs and Laptops"
 >&2 echo "# blitz.data.sh status"
 >&2 echo "# blitz.data.sh [tempmount|explore|unmount]"
 >&2 echo "# blitz.data.sh setup"
 echo "error='missing parameters'"
 exit 1
fi

###################
# BASICS
###################

# For the new data drive setup starting v1.12.0 we have 4 areas of data can be stored in different configurations
# A) INSTALL    - inital install medium (SDcard, USB thumbdrive)
# B) SYSTEM     - root drive of the linux system
# C) DATA       - critical & configuration data of system & apps (formally app_data)
# D) STORAGE    - data that is temp or can be redownloaded or generated like blockhain or indexes (formally app_storage)

# On a old RaspiBlitz setup INTSALL+SYSTEM would be the same on the sd card and DATA+STORAGE on the USB conncted HDD.
# On RaspberryPi5+NVMe or Laptop the SYSTEM is one partition while DATA+STORAGE on another, while INSTALL is started once from SD or thumb drive.
# On a VM all 4 areas can be on separate virtual ext4 drives, stored eg by Proxmox with different redundancies & backup strategies. 

# This script should help to setup & manage those different configurations.

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# gather info on hardware
source <(/home/admin/config.scripts/blitz.hardware.sh status)
if [ ${#computerType} -eq 0 ]; then
  echo "error='hardware not detected'"
  exit 1
fi

# when a drive is mounted on /mnt/data or /mnt/hdd assume the system was already setup
systemSetup=0
combinedDataStorage=-1
mountpoint -q /mnt/data
if [ $? -eq 0 ]; then
  systemSetup=1
  combinedDataStorage=0
fi
mountpoint -q /mnt/hdd
if [ $? -eq 0 ]; then
  systemSetup=1
  combinedDataStorage=1
fi

# output and exit if just status action
if [ "$1" = "status" ]; then
  echo "systemSetup='${systemSetup}'"
  if [ ${combinedDataStorage} -gt -1 ]; then
    echo "combinedDataStorage='${combinedDataStorage}'"
  fi
  exit 0
fi



