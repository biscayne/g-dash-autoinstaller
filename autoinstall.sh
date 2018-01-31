#!/bin/bash
tempdir="/home/pi/gulden/"
guldendir="/opt/gulden"
guldenddir="/opt/gulden/gulden"
guldendatadir="/opt/gulden/datadir"
guldenconf="/opt/gulden/datadir/Gulden.conf"
gdashdir="/var/www/html"
gdashdownload="http://g-dash.nl/download/G-DASH-0.22.tar.gz"
gdashtar="G-DASH-0.22.tar.gz"
gdashversion="0.22"
gdashostname=$(ip route get 8.8.8.8 | awk '{print $NF; exit}')
gdashostname=${gdashostname//[[:blank:]]/}

echo "Adding Gulden repository to the Raspbian sources"
sudo sh -c 'echo "deb http://raspbian.gulden.com/repo/ stretch main" > /etc/apt/sources.list.d/gulden.list'

echo "Updating the system"
sudo apt-get update && sudo apt-get -y upgrade

echo "Create a directory to download the files and store scripts"
mkdir $tempdir
cd $tempdir

echo "Downloading the latest version of G-DASH"
wget $gdashdownload

echo "Installing Curl, Apache and PHP"
sudo apt-get -y install curl apache2 php libapache2-mod-php php-curl php-json php-cli
sudo systemctl daemon-reload

echo "Instaling Gulden from the repo"
sudo apt-get -y --allow-unauthenticated install gulden

echo "Making pi the owner of this folder"
sudo chown -R pi:pi $guldendir

#Generate password for RPC
rpcpasswordgen=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)

echo "Create a Gulden.conf with default values"
cat > $guldenconf << EOF
maxconnections=50
rpcuser=pi
rpcpassword=$rpcpasswordgen
EOF

echo "Make the Gulden files executable"
sudo chmod -R a+rwx $guldenddir

echo "Creating G-DASH web directory"
sudo rm -Rf $gdashdir
sudo mkdir $gdashdir
sudo chown -R www-data:www-data $gdashdir

echo "Extracting G-DASH to the web directory"
sudo -u www-data tar -xvf $gdashtar --directory $gdashdir

sudo service apache2 restart

echo "Create startup script and give it execution rights"
cat > $guldendir/guldenstart.sh << EOF
#!/bin/bash
echo "Stopping GuldenD service"
$guldenddir/Gulden-cli -datadir=$guldendatadir stop
sleep 5

echo "Killing GuldenD"
killall -9 GuldenD
sleep 5

echo "Removing peers.dat"
rm $guldendatadir/peers.dat
sleep 5

echo "Checking for Gulden update"
sudo apt-get update
sudo apt-get -y --allow-unauthenticated install gulden
sleep 5

echo "Starting GuldenD"
$guldenddir/GuldenD -datadir=$guldendatadir &
EOF

sudo chmod a+rwx $guldendir/guldenstart.sh

echo "Creating crontab entry to start Gulden at boot"
crontab -l | { cat; echo "@reboot sleep 30 ; $guldendir/guldenstart.sh 2>&1"; } | crontab -

echo "Creating crontab entry to automatically find the Pi after installing via G-DASH.nl"
crontab -l | { cat; echo "@reboot sleep 120 ; php /var/www/html/lib/push/cronnotifications.php >/dev/null 2>&1"; } | crontab -

echo "Writing G-DASH congiguration file"
sudo mv $gdashdir/config/config_sample.php $gdashdir/config/config.php
sudo chown pi:pi $gdashdir/config/config.php
cat > $gdashdir/config/config.php << EOF
<?php \$CONFIG = array(
'weblocation' => 'http://$gdashostname',
'guldenlocation' => '$guldenddir/',
'datadir' => '$guldendatadir/',
'rpcuser' => 'pi',
'rpcpass' => '$rpcpasswordgen',
'dashversion' => '$gdashversion',
'configured' => '0',
'rpchost' => '127.0.0.1',
'rpcport' => '9232',
); ?>
EOF
sudo chown www-data:www-data $gdashdir/config/config.php

cd ~
sudo rm -Rf $tempdir

echo "Starting Gulden for the first time"
source $guldendir/guldenstart.sh

echo "Waiting for Gulden to load"
sleep 15

echo "Waiting for Gulden to accept commands"
sleep 15

echo "Encrypting wallet"
$guldenddir/Gulden-cli -datadir=$guldendatadir encryptwallet "changeme"
sleep 5

echo "Restarting Gulden"
source $guldendir/guldenstart.sh

echo ""
echo "-------------------------------------------------------------"
echo "Finished!"
echo "You can now login to the G-DASH by going to http://$gdashostname"
echo "Make sure you set a username and password in the settings menu!"
echo "Wallet password: changeme"