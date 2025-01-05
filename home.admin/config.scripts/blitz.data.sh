#!/bin/bash
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 >&2 echo "# managing the data drive(s) with new bootable setups for RaspberryPi, VMs and Laptops"
 >&2 echo "# blitz.data.sh status   # check if system is setup and what drives are used"
 >&2 echo "# blitz.data.sh explore  # find the best drives to use for storage, system and data"
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
# EXPLORE
# find the best drives to use for storage, system and data
###################

if [ "$1" = "explore" ]; then

    # array of device names to exclude
    alreadyUsedDevices=("sda")

    # get a list of all connected drives >63GB ordered by size (biggest first)
    listOfDevices=$(lsblk -dno NAME,SIZE | grep -E "^(sd|nvme)" | \
    awk -v exclude="${alreadyUsedDevices[*]}" '{
    split(exclude, excludeArray, " ")
    size=$2
    if(size ~ /T/) { 
      sub("T","",size); size=size*1024 
    } else if(size ~ /G/) { 
      sub("G","",size); size=size*1 
    } else if(size ~ /M/) { 
      sub("M","",size); size=size/1024 
    }
    excludeDevice=0
    for(i in excludeArray) {
      if($1 == excludeArray[i]) {
        excludeDevice=1
        break
      }
    }
    if (size >= 63 && excludeDevice == 0) printf "%s %.0f\n", $1, size
    }' | sort -k2,2nr -k1,1 )

    # take the biggest drive as the storage drive
    _storageDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
    _storageSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
  
    # take the second biggest drive as the system drive (only in VM setups)
    _systemDevice=$(echo "${listOfDevices}" | sed -n '2p' | awk '{print $1}')
    _systemSizeGB=$(echo "${listOfDevices}" | sed -n '2p' | awk '{print $2}')

    # if there is no spereated system drive
    _bootFromStorage=0
    _bootFromSD=0
    if [ ${#systemDevice} -eq 0 ]; then
        if [ "${computerType}" = "raspberrypi" ] && [ ${gotNVMe} = "0" ]; then
            # if its a RaspberryPi with a USB drive - keep system drive empty and keep booting from SD
            _bootFromSD=1
        else
            # all other like VM, RaspberryPi with a NVMe or a laptop - use the storage drive as system drive
            _bootFromStorage=1
        fi
    fi

    # take the third biggest drive as the data drive (only in VM setups)
    _dataDevice=$(echo "${listOfDevices}" | sed -n '3p' | awk '{print $1}')
    _dataSizeGB=$(echo "${listOfDevices}" | sed -n '3p' | awk '{print $2}')  

    # if there is no spereated data drive - run combine data & storage partiton
    _combinedDataStorage=0
    if [ ${#dataDevice} -eq 0 ]; then
        _combinedDataStorage=1
    fi

    # output the result
    echo "_storageDevice='${storageDevice}'"
    echo "_storageSizeGB='${storageSizeGB}'"
    echo "_systemDevice='${systemDevice}'"
    echo "_systemSizeGB='${systemSizeGB}'"
    echo "_dataDevice='${dataDevice}'"
    echo "_dataSizeGB='${dataSizeGB}'"
    echo "_combinedDataStorage='${combinedDataStorage}'"
    echo "_bootFromStorage='${bootFromStorage}'"
    echo "_bootFromSD='${bootFromSD}'"

  exit 0
fi



