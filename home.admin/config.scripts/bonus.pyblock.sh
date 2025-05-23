#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall PyBlock"
 echo "bonus.pyblock.sh [on|off|menu|update]"
 exit 1
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info PyBlock " --msgbox "
pyblock is a command line tool.
Exit to Terminal and use command 'pyblock'.
Usage: https://github.com/curly60e/pyblock/blob/master/README.md
" 10 75
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ $(sudo ls /home/pyblock/PyBLOCK 2>/dev/null | grep -c "bclock.conf") -gt 0 ]; then
    echo "# FAIL - pyblock already installed"
    sleep 3
    exit 1
  fi
  
  echo "*** INSTALL pyblocks***"
  
  # create pyblock user
  USERNAME=pyblock
  echo "# add the user: ${USERNAME}"
  sudo adduser --system --group --shell /bin/bash --home /home/${USERNAME} ${USERNAME}
  echo "Copy the skeleton files for login"
  sudo -u ${USERNAME} cp -r /etc/skel/. /home/${USERNAME}/

  cd /home/pyblock
  sudo -u pyblock mkdir /home/pyblock/config

  # install hexyl
  sudo apt-get install -y hexyl html2text


  ## WORKAROUND: see https://github.com/raspiblitz/raspiblitz/issues/4383
  # install via pip
  # sudo -u pyblock pip3 install pybitblock 
  # install from github
  sudo -u pyblock git clone https://github.com/curly60e/pyblock.git
  cd pyblock
  sudo -u pyblock git checkout v2.7.2
  sudo -u pyblock sed -i 's/^python =.*$/python = ">=3.11,<4.0"/' pyproject.toml
  sudo -u pyblock poetry lock
  sudo -u pyblock poetry install
  envPath=$(sudo -u pyblock poetry env info --path)
  # sudo -u pyblock ${envPath}/bin/pip uninstall -y typer click
  # sudo -u pyblock ${envPath}/bin/pip install typer==0.4.0 click==8.0.0

  # set PATH for the user
  sudo bash -c "echo 'PATH=\$PATH:${envPath}/bin' >> /home/pyblock/.profile"
  
  # add user to group with admin access to lnd
  sudo /usr/sbin/usermod --append --groups lndadmin pyblock
  
  sudo rm -rf /home/pyblock/.bitcoin  # not a symlink.. delete it silently
  sudo -u pyblock mkdir /home/pyblock/.bitcoin
  sudo cp /mnt/hdd/app-data/bitcoin/bitcoin.conf /home/pyblock/.bitcoin/
  sudo chown pyblock:pyblock /home/pyblock/.bitcoin/bitcoin.conf

  # make sure symlink to central app-data directory exists ***"
  sudo rm -rf /home/pyblock/.lnd  # not a symlink.. delete it silently
  # create symlink
  sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/pyblock/.lnd"
  
  ## Create conf
  # from xxd -p bclock.conf | tr -d '\n'
  echo 80037d710028580700000069705f706f727471015807000000687474703a2f2f710258070000007270637573657271035800000000710458070000007270637061737371056804580a000000626974636f696e636c697106581a0000002f7573722f6c6f63616c2f62696e2f626974636f696e2d636c697107752e0a | xxd -r -p -  ~/bclock.conf
  sudo mv ~/bclock.conf /home/pyblock/config/bclock.conf
  sudo chown pyblock:pyblock /home/pyblock/config/bclock.conf

  # from xxd -p blndconnect.conf | tr -d '\n'
  echo 80037d710028580700000069705f706f72747101580000000071025803000000746c737103680258080000006d616361726f6f6e7104680258020000006c6e710558140000002f7573722f6c6f63616c2f62696e2f6c6e636c697106752e0a | xxd -r -p -  ~/blndconnect.conf
  sudo mv ~/blndconnect.conf /home/pyblock/config/blndconnect.conf
  sudo chown pyblock:pyblock /home/pyblock/config/blndconnect.conf

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set pyblock "on"
  echo "# Usage: https://github.com/curly60e/pyblock"
  echo "# To start use raspiblitz shortcut-command: pyblock"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set pyblock "off"
  
  echo "*** REMOVING PyBLOCK ***"
  sudo userdel -rf pyblock
  echo "# OK, pyblock is removed."
  exit 0

fi

echo "FAIL - Unknown Parameter $1"
exit 1
