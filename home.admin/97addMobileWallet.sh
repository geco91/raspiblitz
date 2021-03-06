#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

justLocal=1

# if dynDomain is set connect from outside is possible (no notice)
if [ ${#dynDomain} -gt 0 ]; then
  justLocal=0
fi

# if sshtunnel to 10009/8080 then outside reach is possible (no notice)
isForwarded=$(echo ${sshtunnel} | grep -c "10009<")
if [ ${isForwarded} -gt 0 ]; then
  justLocal=0
fi
isForwarded=$(echo ${sshtunnel} | grep -c "8080<")
if [ ${isForwarded} -gt 0 ]; then
  justLocal=0
fi

# if TOR is activated then outside reach is possible (no notice)
if [ "${runBehindTor}" = "on" ]; then
  justLocal=0
fi

# check if dynamic domain is set
if [ ${justLocal} -eq 1 ]; then
  whiptail --title " Just Local Network? " --yesno "If you want to connect with your RaspiBlitz
also from outside your local network you need to 
activate 'Services' -> 'DynamicDNS' FIRST.
OR use SSH tunnel forwarding for port 10009
OR have TOR activated.

Do you JUST want to connect with your mobile
when your are on the same LOCAL NETWORK?
" 15 54
  response=$?
  case $response in
    1) exit ;;
  esac
fi

if [ "${chain}" == "test" ]; then
  whiptail --title " Testnet Notice " --msgbox "You are running your node in testnet.
Not all mobile Apps may support running in testnet.
For full support switch to mainnet.
" 9 55
fi

# fuction to call for wallets that support TOR
connect="ip"
choose_IP_or_TOR()
{
  whiptail --title " How to Connect? " \
	--yes-button "TOR" \
	--no-button "IP/Domain" \
	--yesno "The mobile wallet you selected supports TOR.\nDo you want to connect over TOR to your RaspiBlitz or fallback to Domain/IP?" 9 60
	if [ $? -eq 0 ]; then
	  echo "# yes-button -> TOR"
	  connect="tor" 
	else
	  echo "# no-button -> IP"
	  connect="ip"
	fi
}

# Options
OPTIONS=(ZAP_IOS "Zap Wallet (iOS)" \
        ZAP_ANDROID "Zap Wallet (Android)" \
        SHANGO_IOS "Shango Wallet (iOS)" \
        SHANGO_ANDROID "Shango Wallet (Android)" \
        ZEUS_IOS "Zeus Wallet (iOS)" \
        ZEUS_ANDROID "Zeus Wallet (Android)"
	)

# Additinal Options with TOR
if [ "${runBehindTor}" = "on" ]; then
  OPTIONS+=(FULLY_NODED "Fully Noded (IOS+TOR)") 
fi

# Additinal Options with no TOR
#if [ "${runBehindTor}" != "on" ]; then
  OPTIONS+=(SENDMANY_ANDROID "SendMany (Android)") 
#fi

CHOICE=$(whiptail --clear --title "Choose Mobile Wallet" --menu "" 14 50 8 "${OPTIONS[@]}" 2>&1 >/dev/tty)

/home/admin/config.scripts/blitz.lcd.sh hide

clear
echo "creating install info ..."
case $CHOICE in
  CLOSE)
  	exit 1;
    ;;
	SHANGO_IOS)
	  appstoreLink="https://testflight.apple.com/join/WwCjFnS8"
	  /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Testflight and Shango on your iOS device" \
	    --yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "At the moment this app is in public beta testing:\n\n${appstoreLink}\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 10 60
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
      /home/admin/config.scripts/bonus.lndconnect.sh shango-ios ${connect}
	  exit 1;
	  ;;
	SHANGO_ANDROID)
	  appstoreLink="https://play.google.com/store/apps/details?id=com.shango"
	  /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Shango on your Android Phone" \
		--yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "At the moment this app is in public beta testing:\n\n${appstoreLink}\n\nEasiest way to install scan QR code on LCD with phone.\n\nWhen installed and started -> continue" 10 60
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
	  /home/admin/config.scripts/bonus.lndconnect.sh shango-android ${connect}
      exit 1;
      ;;
  ZAP_IOS)
      choose_IP_or_TOR
      appstoreLink="https://apps.apple.com/us/app/zap-bitcoin-lightning-wallet/id1406311960"
      /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Testflight and Zap on your iOS device" \
		--yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "Search for 'Zap Bitcoin' in Apple Appstore for basic version\nOr join public beta test for latest features:\n${appstoreLink}\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 11 65
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
  	  /home/admin/config.scripts/bonus.lndconnect.sh zap-ios ${connect}
      exit 1;
    ;;
  ZAP_ANDROID)
      # choose IP or TOR --> function call
      choose_IP_or_TOR
      appstoreLink="https://play.google.com/store/apps/details?id=zapsolutions.zap"
      /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Zap from PlayStore on your Android device" \
	    --yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "Find & install the Zap Wallet on the Android Play Store:\n\n${appstoreLink}\n\nEasiest way to install scan QR code on LCD with phone.\n\nWhen installed and started -> continue." 10 65
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
  	  /home/admin/config.scripts/bonus.lndconnect.sh zap-android ${connect}
      exit 1;
    ;;
  SENDMANY_ANDROID)

      # check if keysend is activated first
	  source <(/home/admin/config.scripts/lnd.keysend.sh status)
	  if [ "${keysendOn}" == "0" ]; then
	    whiptail --title " KEYSEND NEEDED " --msgbox "
To use the chat feature of the SendMany app, you need to activate the Keysend feature first.

Please go to MAINMENU > SERVICES and activate KEYSEND first.
" 12 65
	    exit 1
	  fi

      appstoreLink="https://github.com/fusion44/sendmany/releases"
      /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install SendMany APK from GithubReleases (open assets) on your device" \
	    --yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "Download & install the SendMany APK (armeabi-v7) from GitHub:\n\n${appstoreLink}\n\nEasiest way to scan QR code on LCD and download/install.\n\nWhen installed and started -> continue." 13 65
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
  	  /home/admin/config.scripts/bonus.lndconnect.sh sendmany-android ${connect}
      exit 1;
    ;;
  ZEUS_IOS)
      appstoreLink="https://testflight.apple.com/join/gpVFzEHN"
      /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Testflight and Zeus on your iOS device" \
	    --yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "At the moment this app is in public beta testing:\n\n${appstoreLink}\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 10 60
	  if [ $? -eq 1 ]; then
		/home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
  	  /home/admin/config.scripts/bonus.lndconnect.sh zeus-ios ${connect}
  	  exit 1;
  	;;
  ZEUS_ANDROID)
      # choose IP or TOR --> function call
      choose_IP_or_TOR
      appstoreLink="https://play.google.com/store/apps/details?id=com.zeusln.zeus"
      /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Zeus on your Android Phone" \
		--yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "Find and install the Zeus Wallet on the Android Play Store:\n\n${appstoreLink}\n\nEasiest way to install scan QR code on LCD with phone.\n\nWhen installed and started -> continue." 10 65
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
  	  /home/admin/config.scripts/bonus.lndconnect.sh zeus-android ${connect}
  	  exit 1;
  	;;
  FULLY_NODED)
      appstoreLink="https://testflight.apple.com/join/PuFnSqgi"
      /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Fully Noded on your iOS device" \
		--yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "At the moment this app is in public beta testing:\n\n${appstoreLink}\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 10 60
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
  	  /home/admin/config.scripts/bonus.fullynoded.sh
  	  exit 1;
  	;;
esac