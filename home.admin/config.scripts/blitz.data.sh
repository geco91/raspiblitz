#!/bin/bash
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 >&2 echo "# managing the data drive(s) with new bootable setups for RaspberryPi, VMs and Laptops"
 >&2 echo "# blitz.data.sh status   # check if system is setup and what drives are used"
 >&2 echo "# blitz.data.sh layout   # auto detect the old/best drives to use for storage, system and data"
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

###################
# STATUS
###################

if [ "$1" = "status" ]; then
  echo "systemSetup='${systemSetup}'"
  if [ ${combinedDataStorage} -gt -1 ]; then
    echo "combinedDataStorage='${combinedDataStorage}'"
  fi
  exit 0
fi

###################
# LAYOUT
# auto detect the old/best drives to use for storage, system and data
###################

if [ "$1" = "layout" ]; then

    # initial values for drives to determine
    storageDevice=""
    systemDevice="sda"
    dataDevice=""

    # get a list of all connected drives >63GB ordered by size (biggest first)
    listOfDevices=$(lsblk -dno NAME,SIZE | grep -E "^(sd|nvme)" | \
    awk '{ 
    size=$2
    if(size ~ /T/) { 
      sub("T","",size); size=size*1024 
    } else if(size ~ /G/) { 
      sub("G","",size); size=size*1 
    } else if(size ~ /M/) { 
      sub("M","",size); size=size/1024 
    }
    if (size >= 63) printf "%s %.0f\n", $1, size
    }' | sort -k2,2nr -k1,1 )
    echo "listOfDevices='${listOfDevices}'"

    # remove lines with already used drives
    if [ -n "${storageDevice}" ]; then
        listOfDevices=$(echo "${listOfDevices}" | grep -v "${storageDevice}")
    fi
    if [ -n "${systemDevice}" ]; then
        listOfDevices=$(echo "${listOfDevices}" | grep -v "${systemDevice}")
    fi
    if [ -n "${dataDevice}" ]; then
        listOfDevices=$(echo "${listOfDevices}" | grep -v "${dataDevice}")
    fi
    echo "listOfDevices='${listOfDevices}'"

    # Set STORAGE
    if [ ${#storageDevice} -eq 0 ]; then
        # when no storage device yet: take the biggest drive as the storage drive
        storageDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
        storageSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
        # remove the storage device from the list
        listOfDevices=$(echo "${listOfDevices}" | grep -v "${storageDevice}")
    fi

    # Set SYSTEM
    bootFromStorage=0 # signales if there is no extra system drive add boot partition to storage drive
    bootFromSD=0      # signales if there is no extra system drive keep booting from SD card (only RaspberryPi)
    if [ ${#systemDevice} -eq 0 ]; then
        # when no system device yet: take the next biggest drive as the system drive
        systemDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
        systemSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
        # remove the system device from the list
        listOfDevices=$(echo "${listOfDevices}" | grep -v "${systemDevice}")
    fi
    # if there is was no spereated system drive left
    if [ ${#systemDevice} -eq 0 ]; then
        if [ "${computerType}" = "raspberrypi" ] && [ ${gotNVMe} = "0" ]; then
            # if its a RaspberryPi with a USB drive - keep system drive empty and keep booting from SD
            bootFromSD=1
        else
            # all other like VM, RaspberryPi with a NVMe or a laptop - use the storage drive as system drive
            bootFromStorage=1
        fi
    fi

    # Set DATA
    if [ ${#dataDevice} -eq 0 ]; then
        # when no data device yet: take the second biggest drive as the data drive
        dataDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
        dataSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
        # remove the data device from the list
        listOfDevices=$(echo "${listOfDevices}" | grep -v "${dataDevice}")
    fi

    # count remaining devices
    remainingDevices=$(echo "${listOfDevices}" | wc -l)

    # if there is no spereated data drive - run combine data & storage partiton
    if [ ${#dataDevice} -eq 0 ]; then
        combinedDataStorage=1
    fi

    # output the result
    echo "storageDevice='${storageDevice}'"
    echo "storageSizeGB='${storageSizeGB}'"
    echo "storageRecoverPartition='${storageRecoverPartition}'"
    echo "systemDevice='${systemDevice}'"
    echo "systemSizeGB='${systemSizeGB}'"
    echo "dataDevice='${dataDevice}'"
    echo "dataSizeGB='${dataSizeGB}'"
    echo "combinedDataStorage='${combinedDataStorage}'"
    echo "bootFromStorage='${bootFromStorage}'"
    echo "bootFromSD='${bootFromSD}'"
    echo "remainingDevices='${remainingDevices}'"

  exit 0
fi



