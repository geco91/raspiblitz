#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info
# get values from cache

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"

# init SETUPFILE & temp dir on mem drive
sudo mkdir /var/cache/raspiblitz/temp
sudo chown admin:admin /var/cache/raspiblitz/temp
sudo rm $SETUPFILE 2>/dev/null
echo "# RASPIBLITZ SETUP STATE" > $SETUPFILE
sudo chown admin:admin $SETUPFILE
sudo chmod 777 $SETUPFILE

source <(/home/admin/_cache.sh get dnsworking)

# remember original setupphase
orgSetupPhase="${setupPhase}"

############################################
# PRESETUP: SET DNS (just if needed)
if [ "${dnsworking}" == "0" ]; then
  sudo /home/admin/config.scripts/internet.dns.sh test
fi

############################################
# QuickOption: Update
if [ "${setupPhase}" == "update" ]; then
  # show update dialog
  /home/admin/setup.scripts/dialogUpdate.sh
  if [ "$?" == "0" ]; then
    # proceed with provision (mark Password A to be set)
    echo "# OK update process starting .."
    echo "setPasswordA=1" >> $SETUPFILE
  else
    # default to normal setup options
    /home/admin/_cache.sh set setupPhase "setup"
    echo "# you refused recovery option - defaulting to normal setup menu"
  fi
fi

############################################
# QuickOption: Recovery
if [ "${setupPhase}" == "recovery" ]; then
  # show recovery dialog
  /home/admin/setup.scripts/dialogRecovery.sh
  if [ "$?" == "0" ]; then
    # proceed with provision (mark Password A to be set)
    echo "# OK recover process starting .."
    echo "setPasswordA=1" >> $SETUPFILE
  else
    # default to normal setup options
    /home/admin/_cache.sh set setupPhase "setup"
    echo "# you refused recovery option - defaulting to normal setup menu"
  fi
fi

############################################
# QuickOption: Migration from other node
if [ "${setupPhase}" == "migration" ]; then

  source <(/home/admin/_cache.sh get system_setup_storageMigration)
  
  # show recovery dialog
  echo "# Starting migration dialog (${system_setup_storageMigration}) ..."

  /home/admin/setup.scripts/dialogMigration.sh ${system_setup_storageMigration} "normal"
  if [ "$?" == "0" ]; then
    # mark migration to happen on provision
    echo "migrationOS='${system_setup_storageMigration}'" >> $SETUPFILE
    # user needs to reset password A, B & C
    echo "setPasswordA=1" >> $SETUPFILE
    echo "setPasswordB=1" >> $SETUPFILE
    echo "setPasswordC=1" >> $SETUPFILE
  else
    # on cancel - default to normal setup
    /home/admin/_cache.sh set setupPhase "setup"
    echo "# you refused node migration option - defaulting to normal setup"
    /home/admin/00raspiblitz.sh
    exit 1
  fi

fi

# fresh import setup values
source /home/admin/raspiblitz.info

############################################
# DEFAULT: Basic Setup menu
# user might default to from quick options
if [ "${setupPhase}" = "setup" ]; then

  echo "# Starting basic setup dialog ..."
  /home/admin/setup.scripts/dialogBasicSetup.sh ${orgSetupPhase}
  menuresult=$?

  # menu RECOVER menu option
  if [ "${menuresult}" = "4" ]; then
    setupPhase="${orgSetupPhase}"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
    # proceed with provision (mark Password A to be set)
    echo "# OK update process starting .."
    echo "setPasswordA=1" >> $SETUPFILE
  fi
  
  # menu MIGRATE menu option
  if [ "${menuresult}" == "5" ]; then
    setupPhase="${orgSetupPhase}"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
    # mark migration to happen on provision
    echo "migrationOS='${hddGotMigrationData}'" >> $SETUPFILE
    # user needs to reset password A, B & C
    echo "setPasswordA=1" >> $SETUPFILE
    echo "setPasswordB=1" >> $SETUPFILE
    echo "setPasswordC=1" >> $SETUPFILE
  fi

  # exit to terminal
  if [ "${menuresult}" == "3" ]; then
    /home/admin/_cache.sh set setupPhase "${orgSetupPhase}"
    exit 1
  fi

  # shutdown without changes
  if [ "${menuresult}" == "2" ]; then
    sudo shutdown now
    exit 0
  fi

  ###############################################
  # FORMAT DRIVE on NEW SETUP or MIGRATION UPLOAD 
  if [ "${menuresult}" == "0" ] || [ "${menuresult}" == "1" ]; then

    source <(/home/admin/_cache.sh get system_setup_askSystemCopy system_setup_bootFromStorage system_setup_combinedDataStorage)

    if [ "${system_setup_askSystemCopy}" == "1" ]; then
      # ask user about system copy
      /home/admin/setup.scripts/dialogSystemCopy.sh
      userChoice=$?
      if [ "${userChoice}" == "1" ]; then
        echo "systemCopy=1" >> $SETUPFILE
      else
        echo "systemCopy=0" >> $SETUPFILE
      fi
    fi

    source <(/home/admin/_cache.sh get system_setup_storageMigration system_setup_storageBlockchainGB)

    # check if there is a blockchain to use (so HDD is already formatted)
    # thats also true if the node is coming from another nodeOS
    existingBlockchain=""
    if [ "${system_setup_storageBlockchainGB}" == "1" ] || [ "${system_setup_storageMigration}" != "" ]; then
      existingBlockchain="BITCOIN"
    fi

    # ask user about possible existing blockchain and formatting HDD
    /home/admin/setup.scripts/dialogDeleteData.sh "${existingBlockchain}"
    userChoice=$?
    if [ "${userChoice}" == "1" ]; then

      echo "deleteData='all'" >> $SETUPFILE

    elif [ "${userChoice}" == "2" ]; then

      echo "deleteData='keepBlockchain'" >> $SETUPFILE

    else

      # STOP SETUP  - loop back to setup menu start
      exit 0

    fi

  fi

  ############################################
  # UPLOAD MIGRATION
  if [ "${menuresult}" == "1" ]; then

    #/home/admin/setup.scripts/dialogMigration.sh raspiblitz
    #if [ "$?" == "1" ]; then
    #  # upload did not worked .. exit with 0 to restart process from outside loop
    #  echo "Upload failed ... return to menu"
    #  sleep 2
    #  exit 0
    #fi

    echo "uploadMigration=1" >> $SETUPFILE
    echo "setPasswordA=1" >> $SETUPFILE
  fi

  ############################################
  # FRESH SETUP
  if [ "${menuresult}" == "0" ]; then

    # user needs to set all passwords (defaults)
    echo "setPasswordA=1" >> $SETUPFILE
    echo "setPasswordB=1" >> $SETUPFILE
    echo "setPasswordC=1" >> $SETUPFILE

    ############################################
    # Setting Name for Node

    echo "# Starting name dialog ..."
    /home/admin/setup.scripts/dialogName.sh

    ############################################
    # Choosing Blockchain & Lightning

    echo "# Starting Blockchain & Lightning selection ..."
    /home/admin/setup.scripts/dialogBlockchainLightning.sh
    if [ "$?" == "1" ]; then
      # exit with 0 to restart process from outside loop
      exit 0
    fi

    ############################################
    # Lightning Wallet (new or restore) do this before passwords
    # because password C not needed if LND rescue file is uploaded

    lightningWalletDone=0
    source ${SETUPFILE}
    if [ "${lightning}" == "none" ]; then
      lightningWalletDone=1
      # also disable asking for password c if no lightning implementation was chosen
      sed -i "s/^setPasswordC=.*/setPasswordC=0/g" ${SETUPFILE}
    fi 
    while [ "${lightningWalletDone}" == "0" ]
    do

      if [ "${lightning}" == "lnd" ]; then

        echo "# Starting lightning wallet dialog for LND ..."
        /home/admin/setup.scripts/dialogLightningWallet-lnd.sh
        dialogResult=$?

      elif [ "${lightning}" == "cl" ]; then

        echo "# Starting lightning wallet dialog for CORE LIGHTNING ..."
        /home/admin/setup.scripts/dialogLightningWallet-cl.sh
        dialogResult=$?

      else
        echo "FAIL: unknown lightning implementation (${lightning})"
        lightningWalletDone=1
        sleep 8
      fi

      # break loop only if a clean exit
      if [ "${dialogResult}" == "0" ]; then
        lightningWalletDone=1
      fi

      # allow user to cancel to terminal on dialog main menu
      # all other cancels have other exit codes
      if [ "${dialogResult}" == "1" ]; then
        echo "# you selected cancel - sending exit code 1"
        exit 1
      fi

    done

  fi

fi

############################################
# Enter Passwords
# for fresh setup & migration

echo "# Starting passwords dialog ..."
sudo /home/admin/setup.scripts/dialogPasswords.sh || exit 1

# check if password A is set
source ${SETUPFILE}
if [ "${passwordA}" == "" ]; then
  /home/admin/config.scripts/blitz.error.sh $(basename "$0") "missing-passworda-1" "missing passwordA(1) in (${SETUPFILE}) after dialogPasswords.sh" ""
  exit 1
fi

# set flag for bootstrap process to kick-off provision process
/home/admin/_cache.sh set state "waitprovision"

clear