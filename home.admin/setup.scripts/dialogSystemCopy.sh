#!/bin/bash

source <(/home/admin/_cache.sh get system_setup_storageDevice system_setup_storageDeviceName system_setup_storageSizeGB system_setup_storageWarning)
source <(/home/admin/_cache.sh get system_setup_systemDevice system_setup_systemDeviceName system_setup_systemSizeGB system_setup_systemWarning)
source <(/home/admin/_cache.sh get system_setup_dataDevice system_setup_dataDeviceName system_setup_dataSizeGB system_setup_dataWarning)

driveInfo=""
if [ "${system_setup_systemDevice}" != "" ]; then
    driveInfo+="SYSTEM:  ${system_setup_systemDevice} ${system_setup_systemSizeGB}GB\n"
fi
if [ "${system_setup_storageDevice}" != "" ]; then
    driveInfo+="STORAGE: ${system_setup_storageDevice} ${system_setup_storageSizeGB}GB\n"
fi
if [ "${system_setup_dataDevice}" != "" ]; then
    driveInfo+="DATA:    ${system_setup_dataDevice} ${system_setup_systemSizeGB}GB\n"
fi

whiptail --title " BOOT FROM SSD/NVME " --yes-button "YES - BOOT SSD/NVME" --no-button "NO" --yesno "Your system allows to BOOT FROM SSD/NVME - which provides better stability & performance and is recommended.

${driveInfo}

Do you want to copy RaspiBlitz system to SSD/NVME and boot from it?" 16 65

if [ "$?" == "0" ]; then
    echo "# 0 --> Yes"
    exit 0
else
    echo "# 1 --> No"
    exit 1
fi
