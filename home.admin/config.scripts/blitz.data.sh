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

    echo "# blitz.data.sh layout"

    # scenario could be: unknown, recover, fresh
    scenario="unknown"
    storageBlockchainGB=0

    # initial values for drives & state to determine
    storageDevice=""
    systemDevice=""
    dataDevice=""
    
    # get a list of all existing ext4 partitions of connected storage drives
    ext4Partitions=$(lsblk -no NAME,SIZE,FSTYPE | sed 's/[└├]─//g' | grep -E "^(sd|nvme)" | grep "ext4" | \
    awk '{ 
        size=$2
        if(size ~ /T/) { 
          sub("T","",size); size=size*1024 
        } else if(size ~ /G/) { 
          sub("G","",size); size=size*1 
        } else if(size ~ /M/) { 
          sub("M","",size); size=size/1024 
        }
        printf "%s %.0f\n", $1, size
    }' | sort -k2,2n -k1,1)
    #echo "ext4Partitions='${ext4Partitions}'"

    # check if some drive is already mounted on /mnt/temp
    mountPath=$(findmnt -n -o TARGET "/mnt/temp" 2>/dev/null)
    if [ -n "${mountPath}" ]; then
        echo "error='a drive already mounted on /mnt/temp'"
        exit 1
    fi

    # check every partition if it has data to recover
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            name=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{print $2}')
            
            # mount partition if not already mounted
            needsUnmount=0
            mountPath=$(findmnt -n -o TARGET "/dev/${name}" 2>/dev/null)   
            if [ -z "${mountPath}" ]; then
                # create temp mount point if not exists
                mkdir -p /mnt/temp 2>/dev/null
                # try to mount
                if ! mount "/dev/${name}" /mnt/temp; then
                    echo "error='cannot mount /dev/${name}'"
                    continue
                fi
                mountPath="/mnt/temp"
                needsUnmount=1
            fi
            
            deviceName=$(echo "${name}" | sed -E 's/p?[0-9]+$//')
            echo "# Checking partition ${name} (${size}GB) on ${deviceName} mounted at ${mountPath}"

            # Check STORAGE DRIVE
            if [ -d "${mountPath}/app-storage" ]; then

                # set data
                echo "# L> STORAGE partition"
                storageDevice="${deviceName}"
                storageSizeGB="${size}"
                storagePartition="${name}"
                if [ "${needsUnmount}" = "0" ]; then
                    storageMountedPath="${mountPath}"
                fi
                
                # check if its a combined data & storage partition
                if [ -d "${mountPath}/app-data" ]; then
                    combinedDataStorage=1
                else
                    combinedDataStorage=0
                fi

                # check blochain data
                if [ -d "${mountPath}/blocks" ]; then
                    storageBlockchainGB=$(du -s ${mountPath}/app-storage/bitcoin/blocks 2>/dev/null| awk '{printf "%.0f", $1/(1024*1024)}')
                    if [ "${storageBlockchainGB}" = "" ]; then
                        # check old location
                        storageBlockchainGB=$(du -s ${mountPath}/bitcoin/blocks 2>/dev/null| awk '{printf "%.0f", $1/(1024*1024)}')
                    fi
                    if [ "${storageBlockchainGB}" = "" ]; then
                        # if nothing found - set to numeric 0
                        storageBlockchainGB=0
                    fi
                fi

            # Check DATA DRIVE
            elif [ -d "${mountPath}/app-data" ] && [ ${size} -gt 63 ]; then

                # check for unclean setups
                if [ -d "${mountPath}/app-storage" ]; then
                    echo "# there might be two old storage drives connected"
                    echo "error='app-storage found on app-data partition'"
                    exit 1
                fi

                # set data
                echo "# L> DATA partition"
                dataDevice="${deviceName}"
                dataSizeGB="${size}"
                dataPartition="${name}"
                if [ "${needsUnmount}" = "0" ]; then
                    dataMountedPath="${mountPath}"
                fi

            # Check SYSTEM DRIVE
            elif [ -d "${mountPath}/boot" ] && [ -d "${mountPath}/sys" ] && [ ${size} -gt 63 ]; then

                # check for unclean setups
                if [ -d "${mountPath}/app-storage" ]; then
                    echo "error='system partition mixed with storage'"
                    exit 1
                fi
                if [ -d "${mountPath}/app-data" ]; then
                    echo "error='system partition mixed with data'"
                    exit 1
                fi

                # set data - just so that same device is used again to overwrite on fresh install
                echo "# L> SYSTEM partition"
                systemDevice="${deviceName}"
                systemSizeGB="${size}"
                systemPartition="${name}"
            else
                echo "# L> no data found on partition"
            fi

            # cleanup if we mounted
            if [ "${needsUnmount}" = "1" ]; then
                umount /mnt/temp
                rm -r /mnt/temp
            fi
        fi
    done <<< "${ext4Partitions}"

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
    #echo "listOfDevices='${listOfDevices}'"

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
    #echo "listOfDevices='${listOfDevices}'"

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

        # if there is was no spereated data drive - run combine data & storage partiton
        if [ ${#dataDevice} -eq 0 ]; then
            combinedDataStorage=1
        fi
    fi

    # count remaining devices
    remainingDevices=$(echo "${listOfDevices}" | wc -l)

    # output the result
    echo "storageDevice='${storageDevice}'"
    echo "storageSizeGB='${storageSizeGB}'"
    echo "storagePartition='${storagePartition}'"
    echo "storageMountedPath='${storageMountedPath}'"
    echo "storageBlockchainGB='${storageBlockchainGB}'"
    echo "systemDevice='${systemDevice}'"
    echo "systemSizeGB='${systemSizeGB}'"
    echo "systemPartition='${systemPartition}'"
    echo "dataDevice='${dataDevice}'"
    echo "dataSizeGB='${dataSizeGB}'"
    echo "dataPartition='${dataPartition}'"
    echo "dataMountedPath='${dataMountedPath}'"
    echo "combinedDataStorage='${combinedDataStorage}'"
    echo "bootFromStorage='${bootFromStorage}'"
    echo "bootFromSD='${bootFromSD}'"
    echo "remainingDevices='${remainingDevices}'"

  exit 0
fi



