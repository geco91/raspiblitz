#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Hardware Tool Script"
 echo "blitz.hardware.sh [status]"
 exit 1
fi

########################
# GATHER HARDWARE INFO
#######################

# detect info about the computer
computerType="pc"
computerVersion=1

# detect generic RaspberryPi
isRaspberryPi=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi")
if [ ${isRaspberryPi} -gt 0 ]; then
    computerType="raspberrypi"
    computerVersion=0 #unknown
fi

# detect RaspberryPi 3
isRaspberryPi3=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 3")
if [ "${isRaspberryPi3}" == "1" ]; then
    computerType="raspberrypi"
    computerVersion=3
fi

# detect RaspberryPi 4
isRaspberryPi4=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 4")
if [ ${isRaspberryPi4} -gt 0 ]; then
    computerType="raspberrypi"
    computerVersion=4
fi

# detect RaspberryPi 5
isRaspberryPi5=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 5")
if [ "${isRaspberryPi5}" == "1" ]; then
    computerType="raspberrypi"
    computerVersion=5
fi

# detect VM
isVM=$(grep -c 'hypervisor' /proc/cpuinfo)
if [ ${isVM} -gt 0 ]; then
    computerType="vm"
fi

# detect NVMe drive
gotNVMe=$(lsblk -o TRAN | grep -c nvme)
if [ ${gotNVMe} -gt 0 ]; then
    gotNVMe=1
fi

# detect USB drive
gotUSB=$(lsblk -o TRAN | grep -c usb)
if [ ${gotUSB} -gt 0 ]; then
    gotUSB=1
fi

# get how many RAM (in MB)
ramMB=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)

# get how many RAM (in GB - approx)
ramGB=$(awk '/MemTotal/ {printf( "%d\n", $2 / 950000 )}' /proc/meminfo)

########################
# OUTPUT HARDWARE INFO
#######################

if [ "$1" = "status" ]; then
    echo "computerType='${computerType}'"
    echo "computerVersion=${computerVersion}"
    echo "ramMB=${ramMB}"
    echo "ramGB=${ramGB}"
    echo "gotNVMe=${gotNVMe}"
    echo "gotUSB=${gotUSB}"
fi