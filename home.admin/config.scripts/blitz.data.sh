#!/bin/bash
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
    >&2 echo "# managing the data drive(s) with new bootable setups for RaspberryPi, VMs and Laptops"
    >&2 echo "# blitz.data.sh status [-inspect] # auto detect the old/best drives to use for storage, system and data"
    >&2 echo "# blitz.data.sh setup STOARGE [device] combinedData=[0|1] bootFromStorage=[0|1]"
    >&2 echo "# blitz.data.sh setup SEPERATE-DATA [device]"
    >&2 echo "# blitz.data.sh setup SEPERATE-SYSTEM [device]"
    >&2 echo "# blitz.data.sh recover STOARGE [device] combinedData=[0|1] bootFromStorage=[0|1]"
    >&2 echo "# blitz.data.sh recover SEPERATE-DATA [device]"
    >&2 echo "# blitz.data.sh recover SEPERATE-SYSTEM [device]"
    >&2 echo "# blitz.data.sh migration [umbrel|citadel|mynode] [partition] [-test] # will migrate partition to raspiblitz"
    >&2 echo "# blitz.data.sh uasp-fix [-info] # deactivates UASP for non supported USB HDD Adapters"
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

# minimal storage sizes (recommended sizes can get checked by UI)
storagePrunedMinGB=128
storageFullMinGB=890
dataMinGB=32
systemMinGB=32

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

###################
# STATUS
###################

if [ "$1" = "status" ]; then

    echo "# blitz.data.sh status"

    # optional: parameter
    userWantsInspect=0
    if [ "$2" = "-inspect" ]; then
        userWantsInspect=1
    fi

    # initial values for drives & state to determine
    storageDevice=""
    systemDevice=""
    dataDevice=""
    storageBlockchainGB=0
    dataInspectSuccess=0
    dataConfigFound=0
    combinedDataStorage=0
    
    # get a list of all existing ext4 partitions of connected storage drives
    # cdrom and sd card will get ignored - but it might include install thumb drive on laptops
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
            
            dataInspectPartition=0
            deviceName=$(echo "${name}" | sed -E 's/p?[0-9]+$//')
            echo "# Checking partition ${name} (${size}GB) on ${deviceName} mounted at ${mountPath}"

            # Check STORAGE DRIVE
            if [ -d "${mountPath}/app-storage" ]; then

                # set data
                echo "#  - STORAGE partition"
                storageDevice="${deviceName}"
                storageSizeGB="${size}"
                storagePartition="${name}"
                if [ "${needsUnmount}" = "0" ]; then
                    storageMountedPath="${mountPath}"
                fi
                
                # check if its a combined data & storage partition
                if [ -d "${mountPath}/app-data" ]; then
                    if [ ${#dataDevice} -eq 0 ]; then
                        combinedDataStorage=1
                    fi
                    dataInspectPartition=1
                else
                    combinedDataStorage=0
                fi

                # check blochain data
                storageBlockchainGB=$(du -s ${mountPath}/app-storage/bitcoin/blocks 2>/dev/null| awk '{printf "%.0f", $1/(1024*1024)}')
                if [ "${storageBlockchainGB}" = "" ]; then
                        # check old location
                        storageBlockchainGB=$(du -s ${mountPath}/bitcoin/blocks 2>/dev/null| awk '{printf "%.0f", $1/(1024*1024)}')
                fi
                if [ "${storageBlockchainGB}" = "" ]; then
                    # if nothing found - set to numeric 0
                    storageBlockchainGB=0
                fi

            # Check DATA DRIVE
            elif [ -d "${mountPath}/app-data" ] && [ ${size} -gt 7 ]; then

                # check for unclean setups
                if [ -d "${mountPath}/app-storage" ]; then
                    echo "# there might be two old storage drives connected"
                    echo "error='app-storage found on app-data partition'"
                    exit 1
                fi

                # set data
                echo "#  - DATA partition"
                combinedDataStorage=0
                dataInspectPartition=1
                dataDevice="${deviceName}"
                dataSizeGB="${size}"
                dataPartition="${name}"
                if [ "${needsUnmount}" = "0" ]; then
                    dataMountedPath="${mountPath}"
                fi

            # Check SYSTEM DRIVE
            elif [ -d "${mountPath}/boot" ] && [ -d "${mountPath}/home/admin/raspiblitz" ] && [ ${size} -gt 7 ]; then

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
                echo "#  - SYSTEM partition"
                systemDevice="${deviceName}"
                systemSizeGB="${size}"
                systemPartition="${name}"
                systemMountedPath="${mountPath}"

            # Check MIGRATION: UMBREL
            elif [ -f "${mountPath}/umbrel/info.json" ]; then
                echo "#  - UMBREL data detected - use 'blitz.data.sh migration'"
                storageMigration="umbrel"

            # Check MIGRATION: CITADEL
            elif [ -f "${mountPath}/citadel/info.json" ]; then
                echo "#  - CITADEL data detected - use 'blitz.data.sh migration'"
                storageMigration="citadel"

            # Check MIGRATION: MYNODE
            elif [ -f "${mountPath}/mynode/bitcoin/bitcoin.conf" ]; then
                echo "#  - MYNODE data detected - use 'blitz.data.sh migration'"
                storageMigration="mynode"

            else
                echo "#  - no data found on partition"
            fi

            # Check: CONFIG FILE
            if [ -f "${mountPath}/raspiblitz.conf" ] || [ -f "${mountPath}/app-data/raspiblitz.conf" ]; then
                dataConfigFound=1
                echo "#    * found raspiblitz.conf"
            fi

            # Datainspect: copy setup relevant data from partition to temp location
            if [ "$dataInspectPartition" = "1" ]; then
                if [ "$userWantsInspect" = "0" ]; then
                    echo "#  - skipping data inspect - use '-inspect' to copy data to RAMDISK for inspection"
                elif [ ! -d "/var/cache/raspiblitz" ]; then
                    echo "#  - skipping data inspect - RAMDISK not found"
                else

                    echo "#  - RUN INSPECT -> RAMDISK: /var/cache/raspiblitz/hdd-inspect"
                    mkdir /var/cache/raspiblitz/hdd-inspect 2>/dev/null
                    dataInspectSuccess=1

                    # make copy of raspiblitz.conf to RAMDISK (try old and new path)
                    cp -a ${mountPath}/raspiblitz.conf /var/cache/raspiblitz/hdd-inspect/raspiblitz.conf 2>/dev/null
                    cp -a ${mountPath}/app-data/raspiblitz.conf /var/cache/raspiblitz/hdd-inspect/raspiblitz.conf 2>/dev/null
                    if [ -f "/var/cache/raspiblitz/hdd-inspect/raspiblitz.conf" ]; then
                        echo "#    * raspiblitz.conf copied to RAMDISK"
                    fi

                    # make copy of WIFI config to RAMDISK (if available)
                    cp -a ${mountPath}/app-data/wifi /var/cache/raspiblitz/hdd-inspect/ 2>/dev/null
                    if [ -d "/var/cache/raspiblitz/hdd-inspect/wifi" ]; then
                        echo "#    * WIFI config copied to RAMDISK"
                    fi

                    # make copy of SSH keys to RAMDISK (if available)
                    cp -a ${mountPath}/app-data/sshd /var/cache/raspiblitz/hdd-inspect 2>/dev/null
                    cp -a ${mountPath}/app-data/ssh-root /var/cache/raspiblitz/hdd-inspect 2>/dev/null
                    if [ -d "/var/cache/raspiblitz/hdd-inspect/sshd" ] || [ -d "/var/cache/raspiblitz/hdd-inspect/ssh-root" ]; then
                        echo "#    * SSH keys copied to RAMDISK"
                    fi
                fi
            fi

            # cleanup if we mounted
            if [ "${needsUnmount}" = "1" ]; then
                umount /mnt/temp
                rm -r /mnt/temp
            fi
        fi
    done <<< "${ext4Partitions}"

    # check boot situation
    if [ -n "${storageDevice}" ] && [ "${storageDevice}" = "${systemDevice}" ]; then
        # system runs from storage device
        bootFromStorage=1
        bootFromSD=0
    else
        # system might run from SD card
        bootFromStorage=0
        # check if boot partition is on SD card (mmcblk)
        bootFromSD=$(lsblk | grep mmcblk | grep -c /boot)
    fi
    
    ########################
    # PROPOSE LAYOUT
    # before setup - when there is no storage device yet
    if [ ${#storageDevice} -eq 0 ]; then

        # get a list of all connected drives >7GB ordered by size (biggest first)
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
        if (size >= 7) printf "%s %.0f\n", $1, size
        }' | sort -k2,2nr -k1,1 )
        #echo "listOfDevices='${listOfDevices}'"

        # on laptop ignore identified system drive which is the INSTALL thumb drive on setup
        # on RaspberryPi ignore all systems from thumb drives
        if [ "${computerType}" = "laptop" ] || [ "${computerType}" = "raspberrypi" ]; then
            echo "# on laptop or RaspberryPi ignore existing system drives for new setup"
            systemDevice=""
            systemSizeGB=""
            systemPartition=""
            systemMountedPath=""
        fi

        # Set STORAGE (the biggest drive)
        storageDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
        storageSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
        # remove the storage device from the list
        listOfDevices=$(echo "${listOfDevices}" | grep -v "${storageDevice}")

        if [ ${#storageDevice} -gt 0 ] && [ "${computerType}" = "pc" ]; then
            echo "# on bare metal PC - storage device is the system boot device"
            bootFromStorage=1
            bootFromSD=0
        fi

        # no storage device found (system seems only device)
        if [ "${systemDevice}" = "${storageDevice}" ]; then
            scenario="error:no-storage"
            storageDevice=""
            storageSizeGB=""

        # Set SYSTEM
        elif [ ${#systemDevice} -eq 0 ]; then

            # when no system device yet: take the next biggest drive as the system drive
            systemDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
            systemSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')

            # if there is was no spereated system drive left
            if [ ${#systemDevice} -eq 0 ]; then

                # force RaspberryPi with no NVMe to boot from SD
                if [ "${computerType}" == "raspberrypi" ] && [ ${gotNVMe} -lt 1 ] ; then
                    bootFromStorage=0
                    bootFromSD=1

                # force RaspberryPi with small NVMe to boot from SD (old NVMe 1TB setups)
                elif [ "${computerType}" == "raspberrypi" ] && [ ${#storageSizeGB} -gt 0 ]  && [ ${storageSizeGB} -lt $((storageFullMinGB + dataMinGB + systemMinGB)) ]; then
                    echo "# NVMe too small to also host system - keep booting from SD card"
                    storageWarning='too-small-for-boot'
                    bootFromStorage=0
                    bootFromSD=1

                # all other systems boot from storage
                else
                    echo "# all other systems boot from storage"
                    bootFromStorage=1
                    bootFromSD=0
                fi

            # when seperate system drive is found - check size
            else

                # if there is a system drive but its smaller than systemMinGB - boot from storage
                if [ ${systemSizeGB} -lt ${systemMinGB} ] && [ ${storageSizeGB} -gt ${storagePrunedMinGB} ]; then
                    echo "# seprate system too small - boot from storage"
                    bootFromSD=0
                    bootFromStorage=1
                    systemDevice=""
                    systemSizeGB=""

                # otherwise remove the system device from the list
                else
                    listOfDevices=$(echo "${listOfDevices}" | grep -v "${systemDevice}")
                fi

            fi
        fi

        # Set DATA (check last, because it more common to have STORAGE & DATA combined)
        if [ ${#dataDevice} -eq 0 ]; then

            # when no data device yet: take the second biggest drive as the data drive
            dataDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
            dataSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')

            # ignore system device if choosen as data device
            if [ "${systemDevice}" = "${dataDevice}" ]; then
                dataDevice=""
                dataSizeGB=""
            fi

            # if there is was no spereated data drive - run combine data & storage partiton
            if [ ${#dataDevice} -eq 0 ]; then
                combinedDataStorage=1

            # when data drive but no storage
            elif [ ${#storageDevice} -eq 0 ]; then
                echo "# ERROR: data drive but no storage"
                scenario="error:system-bigger-than-storage"

            # if there is a data drive but its smaller than dataMinGB & storage drive is big enough - combine data & storage partiton
            elif [ ${dataSizeGB} -lt ${dataMinGB} ] && [ ${storageSizeGB} -gt ${storagePrunedMinGB} ]; then
                combinedDataStorage=1

            # remove the data device from the list
            else
                listOfDevices=$(echo "${listOfDevices}" | grep -v "${dataDevice}")
            fi

        fi

    fi

    #################
    # Check Mininimal Sizes

    # in case of combined data & storage partition
    if [ ${combinedDataStorage} -eq 1 ]; then
        # add dataMinGB to storagePrunedMinGB
        storagePrunedMinGB=$((${storagePrunedMinGB} + ${dataMinGB}))
        # add dataMinGB to storageFullMinGB
        storageFullMinGB=$((${storageFullMinGB} + ${dataMinGB}))
    fi

    # in case of booting from storage
    if [ ${bootFromStorage} -eq 1 ]; then
        # add systemMinGB to storagePrunedMinGB
        storagePrunedMinGB=$((${storagePrunedMinGB} + ${systemMinGB}))
        # add systemMinGB to storageFullMinGB
        storageFullMinGB=$((${storageFullMinGB} + ${systemMinGB}))
    fi

    # STORAGE
    if [ ${#storageDevice} -gt 0 ]; then
        if [ ${storageSizeGB} -lt $((storageFullMinGB - 1)) ]; then
            storageWarning='only-pruned'
        fi
        if [ ${storageSizeGB} -lt $((storagePrunedMinGB - 1)) ]; then
            storageWarning='too-small'
        fi
    fi

    # SYSTEM
    if [ ${#systemDevice} -gt 0 ] && [ ${bootFromStorage} -eq 0 ]; then
        if [ ${systemSizeGB} -lt $((systemMinGB - 1)) ]; then
            systemWarning='too-small'
        fi
    fi

    # DATA
    if [ ${#dataDevice} -gt 0 ]; then
        if [ ${dataSizeGB} -lt $((dataMinGB - 1)) ]; then
            dataWarning='too-small'
        fi
    fi

    #################
    # Device Names

    # use: find_by_id_filename [DEVICENAME]
    find_by_id_filename() {
        local device="$1"
        for dev in /dev/disk/by-id/*; do
            if [ "$(readlink -f "$dev")" = "/dev/$device" ]; then
                basename "$dev"
            fi
        done | sort | head -n1
    }

    # STORAGE
    if [ ${#storageDevice} -gt 0 ]; then
        storageDeviceName=$(find_by_id_filename "${storageDevice}")
    fi

    # SYSTEM
    if [ ${#systemDevice} -gt 0 ]; then
        systemDeviceName=$(find_by_id_filename "${systemDevice}")
    fi

    # DATA
    if [ ${#dataDevice} -gt 0 ]; then
        dataDeviceName=$(find_by_id_filename "${dataDevice}")
    fi

    #################
    # Define Scenario

    # migration: detected data from another node implementation
    if [ ${#scenario} -gt 0 ]; then
        echo "# scenario already set by analysis above to: ${scenario}"
       
    elif [ ${#storageMigration} -gt 0 ]; then
        scenario="migration"

    # nodata: no drives >64GB connected
    elif [ ${#storageDevice} -eq 0 ]; then
        scenario="error:no-storage"

    # ready: Proxmox VM with all seperated drives mounted
    elif [ ${#storageMountedPath} -gt 0 ]  && [ ${#dataMountedPath} -gt 0 ] && [ ${#systemMountedPath} -gt 0 ]; then
        scenario="ready"

    # ready: RaspberryPi+BootNVMe, Laptop or VM with patched thru USB drive
    elif [ ${#storageMountedPath} -gt 0 ] && [ ${combinedDataStorage} -eq 1 ]; then
        scenario="ready"

    # ready: Old RaspberryPi 
    elif [ ${#storageMountedPath} -gt 0 ] && [ ${combinedDataStorage} -eq 1 ] && [ ${bootFromSD} -eq 1 ]; then
        scenario="ready"

    # recover: drives there but unmounted & blitz config exists (check raspiblitz.conf with -inspect if its update)
    elif [ ${#storageDevice} -gt 0 ] && [ ${#storageMountedPath} -eq 0 ] && [ ${dataConfigFound} -eq 1 ]; then
        scenario="recover"

    # setup: drives there but unmounted & no blitz config exists 
    elif [ ${#storageDevice} -gt 0 ] && [ ${#storageMountedPath} -eq 0 ] && [ ${dataConfigFound} -eq 0 ]; then
        scenario="setup"

    # UNKNOWN SCENARIO
    else
        scenario="error:unknown-state"
    fi

    # output the result
    echo "scenario='${scenario}'"
    echo "storageDevice='${storageDevice}'"
    echo "storageDeviceName='${storageDeviceName}'"
    echo "storageSizeGB='${storageSizeGB}'"
    echo "storagePrunedMinGB='${storagePrunedMinGB}'"
    echo "storageFullMinGB='${storageFullMinGB}'"
    echo "storageWarning='${storageWarning}'"
    echo "storagePartition='${storagePartition}'"
    echo "storageMountedPath='${storageMountedPath}'"
    echo "storageBlockchainGB='${storageBlockchainGB}'"
    echo "storageMigration='${storageMigration}'"
    echo "systemDevice='${systemDevice}'"
    echo "systemDeviceName='${systemDeviceName}'"
    echo "systemSizeGB='${systemSizeGB}'"
    echo "systemMinGB='${systemMinGB}'"
    echo "systemWarning='${systemWarning}'"
    echo "systemPartition='${systemPartition}'"
    echo "systemMountedPath='${systemMountedPath}'"
    echo "dataDevice='${dataDevice}'"
    echo "dataDeviceName='${dataDeviceName}'"
    echo "dataSizeGB='${dataSizeGB}'"
    echo "dataMinGB='${dataMinGB}'"
    echo "dataWarning='${dataWarning}'"
    echo "dataPartition='${dataPartition}'"
    echo "dataMountedPath='${dataMountedPath}'"
    echo "dataConfigFound='${dataConfigFound}'"
    echo "dataInspectSuccess='${dataInspectSuccess}'"
    echo "combinedDataStorage='${combinedDataStorage}'"
    echo "bootFromStorage='${bootFromStorage}'"
    echo "bootFromSD='${bootFromSD}'"

    exit 0
fi

###################
# SETUP
# format, partition and setup drives
###################

if [ "$1" = "setup" ]; then
    echo "# blitz.data.sh setup"

    # check that it is a valid setup type: STORAGE, SEPERATE-DATA, SEPERATE-SYSTEM
    setupType=$2
    if [ "${setupType}" != "STORAGE" ] && [ "${setupType}" != "SEPERATE-DATA" ] && [ "${setupType}" != "SEPERATE-SYSTEM" ]; then
        echo "# setupType(${setupType})"
        echo "error='setup type not supported'"
        exit 1
    fi

    # check that device is set & exists & not mounted
    setupDevice=$3
    if [ ${#setupDevice} -eq 0 ]; then
        echo "error='missing device'"
        exit 1
    fi
    if ! lsblk -no NAME | grep -q "${setupDevice}$"; then
        echo "error='device not found'"
        exit 1
    fi
    if findmnt -n -o TARGET "/dev/${setupDevice}" 2>/dev/null; then
        echo "error='device is mounted'"
        exit 1
    fi

    # check if data should also be combined with storage
    setupCombinedData=$4
    if [ "${setupCombinedData}" != "combinedData=0" ] && [ "${setupCombinedData}" != "combinedData=1" ] && [ "${setupCombinedData}" != "0" ] && [ "${setupCombinedData}" != "1" ]; then
        echo "error='combinedData(${setupCombinedData})'"
        echo "error='combinedData not supported'"
        exit 1
    fi
    setupCombinedData=0
    if [ "${setupCombinedData}" = "combinedData=1" ] || [ "${setupCombinedData}" = "1" ]; then
        setupCombinedData=1
    fi

    # check if boot should be from storage
    setupBootFromStorage=$5
    if [ "${setupBootFromStorage}" != "bootFromStorage=0" ] && [ "${setupBootFromStorage}" != "bootFromStorage=1" ] && [ "${setupBootFromStorage}" != "0" ] && [ "${setupBootFromStorage}" != "1" ]; then
        echo "error='bootFromStorage(${setupBootFromStorage})'"
        echo "error='bootFromStorage not supported'"
        exit 1
    fi
    setupBootFromStorage=0
    if [ "${setupBootFromStorage}" = "bootFromStorage=1" ] || [ "${setupBootFromStorage}" = "1" ]; then
        setupBootFromStorage=1
    fi

    # determine the partition base name
    setupDevicePartitionBase=${setupDevice}
    if [[ "${setupDevice}" =~ ^nvme ]]; then
        setupDevicePartitionBase="${setupDevice}p"
    fi

    # debug info
    echo "# setupType(${setupType})"
    echo "# setupDevice(${setupDevice})"
    echo "# setupDevicePartitionBase(${setupDevicePartitionBase})"
    echo "# setupBootFromStorage(${setupBootFromStorage})"
    echo "# setupCombinedData(${setupCombinedData})"

    ##########################
    # PARTITION & FORMAT

    # SYSTEM (single drive)
    if [ setupType="SEPERATE-SYSTEM" ]; then
        echo "# SYSTEM"
        echo "# .. partitioning"
        wipefs -a /dev/${setupDevice}
        parted /dev/${setupDevice} --script mklabel msdos
        parted /dev/${setupDevice} --script mkpart primary fat32 1MiB 100%
        wipefs -a /dev/${setupDevicePartitionBase}1
        mkfs -t vfat -F 32  /dev/${setupDevicePartitionBase}1
        wipefs -a /dev/${setupDevicePartitionBase}2
        mkfs -t ext4  /dev/${setupDevicePartitionBase}2

    # STOARGE with System
    elif [ setupType="STORAGE" ] && [ ${setupBootFromStorage} -eq 1 ]; then
        echo "# STORAGE (with system)"
        echo "# .. partitioning"
        wipefs -a /dev/${setupDevice}
        parted /dev/${setupDevice} --script mklabel msdos
        parted /dev/${setupDevice} --script mkpart primary fat32 1MiB 513MiB
        parted /dev/${setupDevice} --script mkpart primary ext4 541MB 100%
        echo "# .. formating"
        wipefs -a /dev/${setupDevicePartitionBase}1
        mkfs -t vfat -F 32  /dev/${setupDevicePartitionBase}1
        wipefs -a /dev/${setupDevicePartitionBase}2
        mkfs -t ext4  /dev/${setupDevicePartitionBase}2
        wipefs -a /dev/${setupDevicePartitionBase}3
        mkfs -t ext4  /dev/${setupDevicePartitionBase}3

    # STOARGE (single drive OR host for seperate data & system)
    elif [ setupType="STORAGE" ] && [ ${setupBootFromStorage} -eq 0 ]; then
        echo "# STORAGE"
        echo "# .. partitioning"
        wipefs -a /dev/${setupDevice}
        parted /dev/${setupDevice} --script mklabel msdos
        parted /dev/${setupDevice} --script mkpart primary ext4 1MB 100%
        echo "# .. formating"
        wipefs -a /dev/${setupDevicePartitionBase}1
        mkfs -t ext4  /dev/${setupDevicePartitionBase}1

    # DATA (single drive)
    elif [ setupType="SEPERATE-DATA" ]; then
        echo "# DATA"
        echo "# .. partitioning"
        wipefs -a /dev/${setupDevice}
        parted /dev/${setupDevice} --script mklabel msdos
        parted /dev/${setupDevice} --script mkpart primary ext4 1MB 100%
        echo "# .. formating"
        wipefs -a /dev/${setupDevicePartitionBase}1
        mkfs -t ext4  /dev/${setupDevicePartitionBase}1

    else
        echo "error='setup type not supported'"
        exit 1
    fi

    ##########################
    # MAKE BOOTABLE

    if [ setupType="SEPERATE-SYSTEM" ] || [ ${setupBootFromStorage} -eq 1 ]; then
        echo "# MAKE BOOTABLE"
        if [ "${computerType}" = "raspberrypi" ]; then
            echo "# RaspberryPi - set LBA flag"
            parted /dev/${setupDevice} --script set 1 lba on
            isFlagSetLBA=$(parted /dev/${setupDevice} --script print | grep -c 'fat32.*lba')
            if [ ${isFlagSetLBA} -eq 0 ]; then
                echo "error='failed to set LBA flag'"
                exit 1
            fi
            echo "# RaspberryPi - Bootorder"
            isBootOrderSet=$(sudo rpi-eeprom-config | grep -cx "BOOT_ORDER=0xf461")
            if [ ${isBootOrderSet} -eq 0 ]; then
                echo "# .. changeing Bootorder"
                rpi-eeprom-config --out bootconf.txt
                sed -i '/^BOOT_ORDER=/d' ./bootconf.txt && sudo sh -c 'echo "BOOT_ORDER=0xf461" >> ./bootconf.txt'
                rpi-eeprom-config --apply bootconf.txt
                rm bootconf.txt
            else
                echo "# .. Bootorder already set"
            fi
        else
            echo "# VM & PC - set BOOT/ESP flag"
            parted /dev/${setupDevice} --script set 1 boot on
            parted /dev/${setupDevice} --script set 1 esp on
            isFlagSetBOOT=$(parted /dev/${setupDevice} --script print | grep -c 'fat32.*boot')
            isFlagSetESP=$(parted /dev/${setupDevice} --script print | grep -c 'fat32.*esp')
        fi
    else
        echo "# skipping: Bootable"
    fi

    exit 1

    ##########################
    # COPY SYSTEM

    if [ setupType="SEPERATE-SYSTEM" ] || [ ${setupBootFromStorage} -eq 1 ]; then
        echo "# SYSTEM COPY"

        # copy the boot drive
        bootPath="/boot/"
        if [ "${computerType}" = "raspberrypi" ]; then
            bootPath="/boot/firmware/"
        fi
        mkdir -p /mnt/disk_boot 2>/dev/null
        mount /dev/${setupDevicePartitionBase}1 /mnt/disk_boot
        if ! findmnt -n -o TARGET "/mnt/disk_boot" 2>/dev/null; then
            echo "error='boot partition not mounted'"
            exit 1
        fi
        echo "# .. copy boot"
        rsync -avh --delete --info=progress2 ${bootPath} /mnt/disk_boot/

        # copy the system drive
        echo "# .. copy system"
        mkdir -p /mnt/disk_system 2>/dev/null
        mount /dev/${setupDevicePartitionBase}2 /mnt/disk_system
        if ! findmnt -n -o TARGET "/mnt/disk_system" 2>/dev/null; then
            echo "error='system partition not mounted'"
            exit 1
        fi
        rsync -axHAX --delete --info=progress2\
            --exclude=/dev/* \
            --exclude=/proc/* \
            --exclude=/sys/* \
            --exclude=/tmp/* \
            --exclude=/run/* \
            --exclude=/mnt/* \
            --exclude=/media/* \
            --exclude=/boot/* \
            --exclude=/lost+found \
            --exclude=/var/cache/* \
            --exclude=/var/tmp/* \
            --exclude=/var/log/* \
            / /mnt/disk_root/
            echo "# OK - System copied"
    else
        echo "# skipping: SystemCopy"
    fi

    exit 0

fi

###################
# RECOVER
# re-integrate drives into the system
###################

if [ "$1" = "recover" ]; then
    echo "# blitz.data.sh recover"

    # replace fstab & link (maybe there is some same linking as in setup)

    echo "error='TODO'"
    exit 0
fi

###################
# MIGRATION
###################

if [ "$1" = "migration" ]; then

    echo "# blitz.data.sh migration"

    # check if all needed parameters are set
    if [ $# -lt 3 ]; then
        echo "error='missing parameters'"
        exit 1
    fi

    # check that partition exists
    if ! lsblk -no NAME | grep -q "${dataPartition}$"; then
        echo "# dataPartition(${dataPartition})"
        echo "error='partition not found'"
        exit 1
    fi

    # check that partition is not mounted
    if findmnt -n -o TARGET "/dev/${dataPartition}" 2>/dev/null; then
        echo "# dataPartition(${dataPartition})"
        echo "# make sure the partition is not mounted"
        echo "error='partition is mounted'"
        exit 1
    fi

    onlyTestIfMigratioinPossible=0
    if [ "$4" = "-test" ]; then
        echo "# ... only testing if migration is possible"
        onlyTestIfMigratioinPossible=1
    fi

    mountPath="/mnt/temp"
    mkdir -p "${mountPath}" 2>/dev/null
    if ! mount "/dev/${name}" "${mountPath}"; then
        echo "error='cannot mount partition'"
        exit 1
    fi

    #####################
    # MIGRATION: UMBREL
    if [ "$2" = "umbrel" ]; then

        # TODO: Detect and output Umbrel Version

        if [ ${onlyTestIfMigratioinPossible} -eq 1 ]; then
            # provide information about the versions
            btcVersion=$(grep "lncm/bitcoind" ${mountPath}/umbrel/app-data/bitcoin/docker-compose.yml 2>/dev/null | sed 's/.*bitcoind://' | sed 's/@.*//')
            clnVersion=$(grep "lncm/clightning" ${mountPath}/umbrel/app-data/core-lightning/docker-compose.yml 2>/dev/null | sed 's/.*clightning://' | sed 's/@.*//')
            lndVersion=$(grep "lightninglabs/lnd" ${mountPath}/umbrel/app-data/lightning/docker-compose.yml 2>/dev/null | sed 's/.*lnd://' | sed 's/@.*//')
            echo "btcVersion='${btcVersion}'"
            echo "clnVersion='${clnVersion}'"
            echo "lndVersion='${lndVersion}'"
        else

            echo "error='TODO migration'"

        fi

    #####################
    # MIGRATION: CITADEL
    elif [ "$2" = "citadel" ]; then

        # TODO: Detect and output Citadel Version

        if [ ${onlyTestIfMigratioinPossible} -eq 1 ]; then
            # provide information about the versions
            lndVersion=$(grep "lightninglabs/lnd" ${mountPath}/citadel/docker-compose.yml 2>/dev/null | sed 's/.*lnd://' | sed 's/@.*//')
            echo "lndVersion='${lndVersion}'"
        else

            echo "error='TODO migration'"

        fi

    #####################
    # MIGRATION: MYNODE
    elif [ "$2" = "mynode" ]; then

        echo "error='TODO'"

    else
        echo "error='migration type not supported'"
    fi

    # unmount partition
    umount ${mountPath}
    rm -r ${mountPath}

    exit 0
fi

#############
# UASP-fix
#############

if [ "$1" = "uasp-fix" ]; then

    echo "# blitz.data.sh uasp-fix"

    # optional: parameter
    onlyInfo=0
    if [ "$2" = "-info" ]; then
        echo
        onlyInfo=1
    fi

    # check is running on RaspiOS
    if [ "${computerType}" != "raspberrypi" ]; then
        echo "error='only on RaspberryPi'"
        exit 1
    fi

    # HDD Adapter UASP support --> https://www.pragmaticlinux.com/2021/03/fix-for-getting-your-ssd-working-via-usb-3-on-your-raspberry-pi/
    hddAdapter=$(lsusb | grep "SATA" | head -1 | cut -d " " -f6)
    if [ "${hddAdapter}" == "" ]; then
      hddAdapter=$(lsusb | grep "GC Protronics" | head -1 | cut -d " " -f6)
    fi
    if [ "${hddAdapter}" == "" ]; then
      hddAdapter=$(lsusb | grep "ASMedia Technology" | head -1 | cut -d " " -f6)
    fi

    # check if HDD ADAPTER is on UASP WHITELIST (tested devices)
    hddAdapterUASP=0
    if [ "${hddAdapter}" == "174c:55aa" ]; then
      # UGREEN 2.5" External USB 3.0 Hard Disk Case with UASP support
      hddAdapterUASP=1
    fi
    if [ "${hddAdapter}" == "174c:1153" ]; then
      # UGREEN 2.5" External USB 3.0 Hard Disk Case with UASP support, 2021+ version
      hddAdapterUASP=1
    fi
    if [ "${hddAdapter}" == "0825:0001" ] || [ "${hddAdapter}" == "174c:0825" ]; then
      # SupTronics 2.5" SATA HDD Shield X825 v1.5
      hddAdapterUASP=1
    fi
    if [ "${hddAdapter}" == "2109:0715" ]; then
      # ICY BOX IB-247-C31 Type-C Enclosure for 2.5inch SATA Drives
      hddAdapterUASP=1
    fi
    if [ "${hddAdapter}" == "174c:235c" ]; then
      # Cable Matters USB 3.1 Type-C Gen2 External SATA SSD Enclosure
      hddAdapterUASP=1
    fi
    if [ -f "/boot/firmware/uasp.force" ]; then
      # or when user forces UASP by flag file on sd card
      hddAdapterUASP=1
    fi

    if [ ${onlyInfo} -eq 1 ]; then
        echo "# the ID of the HDD Adapter:"
        echo "hddAdapter='${hddAdapter}'"
        echo "# if HDD Adapter supports UASP:"
        echo "hddAdapterUASP='${hddAdapterUASP}'"
        exit 0
    fi

    # https://www.pragmaticlinux.com/2021/03/fix-for-getting-your-ssd-working-via-usb-3-on-your-raspberry-pi/
    cmdlineFileExists=$(ls /boot/firmware/cmdline.txt 2>/dev/null | grep -c "cmdline.txt")
    if [ ${cmdlineFileExists} -eq 0 ]; then
        echo "error='no /boot/firmware/cmdline.txt'"
        exit 1
    elif [ ${#hddAdapter} -eq 0 ]; then
        echo "# Skipping UASP deactivation - no USB HDD Adapter found"
        echo "neededReboot=0"
    elif [ ${hddAdapterUASP} -eq 1 ]; then
        echo "# Skipping UASP deactivation - USB HDD Adapter is on UASP WHITELIST"
        echo "neededReboot=0"
    else
        echo "# UASP deactivation - because USB HDD Adapter is not on UASP WHITELIST ..."
        usbQuirkDone=$(cat /boot/firmware/cmdline.txt | grep -c "usb-storage.quirks=${hddAdapter}:u")
        if [ ${usbQuirkDone} -eq 0 ]; then
            # remove any old usb-storage.quirks
            sed -i "s/usb-storage.quirks=[^ ]* //g" /boot/firmware/cmdline.txt 2>/dev/null
            # add new usb-storage.quirks
            sed -i "s/^/usb-storage.quirks=${hddAdapter}:u /" /boot/firmware/cmdline.txt
            # go into reboot to activate new setting
            echo "# DONE deactivating UASP for ${hddAdapter}"
            echo "neededReboot=1"
        else
            echo "# Already UASP deactivated for ${hddAdapter}"
            echo "neededReboot=0"
        fi
    fi
    exit 0
fi