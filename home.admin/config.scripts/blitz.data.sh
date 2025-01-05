#!/bin/bash
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
    >&2 echo "# managing the data drive(s) with new bootable setups for RaspberryPi, VMs and Laptops"
    >&2 echo "# blitz.data.sh status [-inspect] # auto detect the old/best drives to use for storage, system and data"
    >&2 echo "# blitz.data.sh setup STOARGE [device] combinedData=[0|1] bootFromStorage=[0|1]"
    >&2 echo "# blitz.data.sh setup SINGLE-DATA"
    >&2 echo "# blitz.data.sh setup SINGLE-SYSTEM"
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

    # scenario could be: unknown, migration, recover, setup, ready
    scenario="unknown"
    storageBlockchainGB=0
    dataInspectDone=0

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
                    combinedDataStorage=1
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
            elif [ -d "${mountPath}/app-data" ] && [ ${size} -gt 63 ]; then

                # check for unclean setups
                if [ -d "${mountPath}/app-storage" ]; then
                    echo "# there might be two old storage drives connected"
                    echo "error='app-storage found on app-data partition'"
                    exit 1
                fi

                # set data
                echo "#  - DATA partition"
                dataInspectPartition=1
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
                echo "#  - SYSTEM partition"
                systemDevice="${deviceName}"
                systemSizeGB="${size}"
                systemPartition="${name}"

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
                echo "#  - no data found on partition or too small"
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
                    dataInspectDone=1

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
    remainingDevices=0
    if [ ${#listOfDevices} -gt 0 ]; then
        remainingDevices=$(echo "${listOfDevices}" | wc -l)
    fi

    # output the result
    echo "storageDevice='${storageDevice}'"
    echo "storageSizeGB='${storageSizeGB}'"
    echo "storagePartition='${storagePartition}'"
    echo "storageMountedPath='${storageMountedPath}'"
    echo "storageBlockchainGB='${storageBlockchainGB}'"
    echo "storageMigration='${storageMigration}'"
    echo "systemDevice='${systemDevice}'"
    echo "systemSizeGB='${systemSizeGB}'"
    echo "systemPartition='${systemPartition}'"
    echo "dataDevice='${dataDevice}'"
    echo "dataSizeGB='${dataSizeGB}'"
    echo "dataPartition='${dataPartition}'"
    echo "dataMountedPath='${dataMountedPath}'"
    echo "dataInspectDone='${dataInspectDone}'"
    echo "combinedDataStorage='${combinedDataStorage}'"
    echo "bootFromStorage='${bootFromStorage}'"
    echo "bootFromSD='${bootFromSD}'"
    echo "remainingDevices='${remainingDevices}'"

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