#!/bin/bash

# get raspiblitz config
echo "# get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/app-data/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $1)

# make sure the CL wallet is unlocked
/home/admin/config.scripts/cl.hsmtool.sh unlock ${CHAIN}

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE=" Core Lightning Options (${CHAIN})"
MENU=""
OPTIONS=()
  OPTIONS+=(FUNDING "Fund the Core Lightning wallet onchain")
  OPTIONS+=(PEERING "Connect to a peer")
  OPTIONS+=(CHANNEL "Open a channel with peer")
  OPTIONS+=(SEND "Pay an invoice / payment request")
  OPTIONS+=(RECEIVE "Create an invoice / payment request")
  OPTIONS+=(SUMMARY "Information about this node")
  OPTIONS+=(NAME "Change the name / alias of the node")
ln_getInfo=$($lightningcli_alias getinfo 2>/dev/null)
ln_channels_online="$(echo "${ln_getInfo}" | jq -r '.num_active_channels')" 2>/dev/null
cl_num_inactive_channels="$(echo "${ln_getInfo}" | jq -r '.num_inactive_channels')" 2>/dev/null
openChannels=$((ln_channels_online+cl_num_inactive_channels))
if [ ${#openChannels} -gt 0 ] && [ ${openChannels} -gt 0 ]; then
  OPTIONS+=(SUEZ "Visualize channels")
  OPTIONS+=(CLOSEALL "Close all open channels on $CHAIN")
fi
  OPTIONS+=(CASHOUT "Withdraw all funds onchain ($CHAIN)")
  OPTIONS+=(SEED "Show Wallet Seed Words")
if [ "${clWatchtowerClient}" == "on" ] && [ "${CHAIN}" == "mainnet" ]; then
  OPTIONS+=(WATCHTOWER  "Watchtower Client Options")
fi
  OPTIONS+=(REPAIR-CL "Repair options for Core Lightning")
if [ "${lightning}" != "cl" ] && [ "${CHAIN}" == "mainnet" ]; then
  OPTIONS+=(SWITCHLN  "Use Core Lightning as default")
fi

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Main menu" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in
  SUMMARY)
      clear
      /home/admin/config.scripts/cl-plugin.summars.sh $CHAIN
      echo "Press ENTER to return to main menu."
      read key
      ;;
  PEERING)
      /home/admin/BBconnectPeer.sh cl $CHAIN
      ;;
  FUNDING)
      /home/admin/BBfundWallet.sh cl $CHAIN
      ;;
  CASHOUT)
      /home/admin/BBcashoutWallet.sh cl $CHAIN
      ;;
  CHANNEL)
      /home/admin/BBopenChannel.sh cl $CHAIN
      ;;
  SEND)
      /home/admin/BBpayInvoice.sh cl $CHAIN
      ;;
  RECEIVE)
      /home/admin/BBcreateInvoice.sh cl $CHAIN
      ;;
  SEED)
      sudo /home/admin/config.scripts/cl.install.sh display-seed $CHAIN
      ;;
  NAME)
      sudo /home/admin/config.scripts/cl.setname.sh $CHAIN
      ;;
  WATCHTOWER)
      /home/admin/config.scripts/cl-plugin.watchtower-client.sh info
      ;;
  SUEZ)
      clear
      if [ ! -f /home/bitcoin/suez/suez ];then
        /home/admin/config.scripts/bonus.suez.sh on
      fi
      cd /home/bitcoin/suez || exit 1
      echo
      sudo -u bitcoin poetry run /home/bitcoin/suez/suez --client=c-lightning --client-args=--conf=${CLCONF}
      echo
      echo "Press ENTER to return to main menu."
      read key
      ;;
  CLOSEALL)
      /home/admin/BBcloseAllChannels.sh cl $CHAIN
      echo "Press ENTER to return to main menu."
      read key
      ;;
  REPAIR-CL)
      /home/admin/99clRepairMenu.sh $CHAIN
      ;;
  SWITCHLN)
      clear
      echo
      # setting value in the raspiblitz.conf
      /home/admin/config.scripts/blitz.conf.sh set lightning "cl"
      # when raspiblitz api is active - trigger a restart
      if systemctl list-unit-files --type=service | grep -Fq 'blitzapi.service'; then
        echo "# Restarting the blitzapi ..."
        sudo systemctl restart blitzapi
      fi
      echo "# OK - lightning=cl is set in /mnt/hdd/app-data/raspiblitz.conf"
      echo
      echo "Press ENTER to return to main menu."
      read key
      ;;
esac

exit 0
