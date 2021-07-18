#!/bin/bash

DIR="$( which $BASH_SOURCE)"
DIR="$(dirname $DIR)"

echo "# Initial File" > $DIR/my-log.txt

function mylog_write {
    echo "---> ${0##*/} => $@" >> $DIR/my-log.txt
}

source $DIR/to_absolute_path.sh
to-absolute-path $DIR
DIR=$ABS_PATH
mylog_write "# Absoulute path: $ABS_PATH"

# 2.0 source the CC vars so we can cleanup the packages
set-chain-env.sh -z
source   $DIR/cc.env.sh
rm -rf $CC2_PACKAGE_FOLDER &> /dev/null
mylog_write "# CC2_PACKAGE_FOLDER: $CC2_PACKAGE_FOLDER"

# Time to sleep for containers to launch
COUCHDB_SLEEP_TIME=5s

function usage {
    echo    "dev-init.sh -opt -opt ...    Initializes the dev setup"
    echo    "Options:   -h Help  -d Dev mode -s CouchDB  -e  Setup explorer -c CLI container"
    echo    "To start the dev environment:  dev-start.sh"
    echo    "To stop the dev environment:   dev-stop.sh"
}

# Give time to containers for starting up
SLEEP_TIME=5s
# DB containers need more time
# Adjust this if the validation is failing when launched with Couch DB
SLEEP_TIME_DB=10s

###### Generate the Launch & Shytdown scripts based on options ###########
# Pending t=TLS enable     k=Kafka enable   c=cli
    PEER_MODE=net
    LAUNCH_SCRIPT="docker-compose  -f ./compose/docker-compose.base.yaml "
    LAUNCH_DEV_MODE=""
    LAUNCH_SCRIPT_DB=""
    LAUNCH_SCRIPT_EXPLORER=""
    LAUNCH_SCRIPT_CLI=""
    while getopts "dcehs" OPTION; do
        case $OPTION in
        h)  usage
            exit
            ;;
        d) 
            LAUNCH_DEV_MODE=" -f ./compose/docker-compose.dev.yaml "
            PEER_MODE=dev
            ;;
        s)
            LAUNCH_SCRIPT_DB=" -f ./compose/docker-compose.couchdb.yaml "
            SLEEP_TIME=$SLEEP_TIME_DB
            ;;
        e)
            LAUNCH_SCRIPT_EXPLORER=" -f ./compose/docker-compose.explorer.yaml "
            ;;
        c)
            LAUNCH_SCRIPT_CLI=" -f ./compose/docker-compose.cli.yaml "
            ;;
        *)
            usage
            exit
        esac
    done
    LAUNCH_SCRIPT="$LAUNCH_SCRIPT  $LAUNCH_DEV_MODE $LAUNCH_SCRIPT_DB $LAUNCH_SCRIPT_EXPLORER $LAUNCH_SCRIPT_CLI "
    SHUTDOWN_SCRIPT="$LAUNCH_SCRIPT down "
    LAUNCH_SCRIPT="$LAUNCH_SCRIPT up -d"

    # Before overwriting shutdown - we need to shutdown the environment
    echo    "==============Stopping the Dev Environment ======"
    dev-stop.sh &> /dev/null

    echo "#PEER_MODE=$PEER_MODE" > $DIR/_launch.sh
    echo "#Command=dev-init.sh ${BASH_ARGV[*]} " >> $DIR/_launch.sh
    echo "#Generated: $(date) " >> $DIR/_launch.sh
    echo "$LAUNCH_SCRIPT --remove-orphans" >> $DIR/_launch.sh
    echo "#PEER_MODE=$PEER_MODE" > $DIR/_shutdown.sh
    echo "#Command=dev-init.sh ${BASH_ARGV[*]} " >> $DIR/_shutdown.sh
    echo "#Generated: $(date) " >> $DIR/_shutdown.sh
    echo "$SHUTDOWN_SCRIPT" >> $DIR/_shutdown.sh

    echo "Created the scripts...{ _launch.sh   _shutdown.sh }"
##################################################################################



# Remove all chaincode image containers
echo    "==============Cleaning up the Dev containers & images ======"

# REMOVE the dev- container images also - TBD
docker rm $(docker ps -a -q)            &> /dev/null
docker rmi $(docker images dev-* -q)    &> /dev/null

# Initializes the dev setup
rm -rf $DIR/../crypto/crypto-config  &> /dev/null
mylog_write "# Remove crpto config: $DIR/../crypto/crypto-config"
rm $DIR/../config/*.block &> /dev/null
mylog_write "# Remove block: $DIR/../config/*.block"
rm $DIR/../config/*.tx &> /dev/null
mylog_write "# Remove files tx: $DIR/../config/*.tx"
sudo rm -rf $HOME/ledgers &> /dev/null
mylog_write "# Remove ledger: $HOME/ledgers"


# Copy the aprorpriate compose file

if [ "$1" == "dev" ]; then
    PEER_MODE=dev
else
    PEER_MODE=net
fi
# cp "$DIR/../devenv/compose/docker-compose.$PEER_MODE.yaml"  "$DIR/../devenv/docker-compose.yaml"
# echo "Initializing & Starting environment in mode = $PEER_MODE"

# Generates the crypto material for the dev enviornment
echo    '================ Generating crypto ================'
mylog_write "================ Generating crypto ================"
CRYPTO_CONFIG_YAML=$DIR/../config/crypto-config.yaml
mylog_write "# CRYPTO_CONFIG_YAML: $DIR/../config/crypto-config.yaml"
mylog_write "# Output directory: $DIR/../crypto/crypto-config"
cryptogen generate --config=$CRYPTO_CONFIG_YAML --output=$DIR/../crypto/crypto-config


# Generates the orderer | generate genesis block for ordererchannel
# export ORDERER_GENERAL_LOGLEVEL=debug
export FABRIC_LOGGING_SPEC=INFO
export FABRIC_CFG_PATH=$DIR/../config
mylog_write "# FABRIC_CFG_PATH: $DIR/../config"

# Create the Genesis Block
echo    '================ Writing Genesis Block ================'
mylog_write "================ Writing Genesis Block ================"
GENESIS_BLOCK=$DIR/../config/airline-genesis.block
mylog_write "# GENESIS_BLOCK: $GENESIS_BLOCK"
ORDERER_CHANNEL_ID=ordererchannel
mylog_write "# ORDERER_CHANNEL_ID: $ORDERER_CHANNEL_ID"
configtxgen -profile AirlineOrdererGenesis -outputBlock $GENESIS_BLOCK -channelID $ORDERER_CHANNEL_ID

echo    '================ Writing airlinechannel ================'
mylog_write "================ Writing airlinechannel ================"
CHANNEL_ID=airlinechannel
CHANNEL_CREATE_TX=$DIR/../config/airline-channel.tx
mylog_write "# CHANNEL_ID: $CHANNEL_ID"
mylog_write "# CHANNEL_CREATE_TX: $CHANNEL_CREATE_TX"
configtxgen -profile AirlineChannel -outputCreateChannelTx $CHANNEL_CREATE_TX -channelID $CHANNEL_ID

echo    '================ Generate the anchor Peer updates ======'
mylog_write "================ Generate the anchor Peer updates ======"
ANCHOR_UPDATE_TX=$DIR/../config/airline-anchor-update-acme.tx
mylog_write "# ANCHOR_UPDATE_TX: $ANCHOR_UPDATE_TX"
configtxgen -profile AirlineChannel -outputAnchorPeersUpdate $ANCHOR_UPDATE_TX -channelID $CHANNEL_ID -asOrg AcmeMSP

ANCHOR_UPDATE_TX=$DIR/../config/airline-anchor-update-budget.tx
mylog_write "# ANCHOR_UPDATE_TX: $ANCHOR_UPDATE_TX"
configtxgen -profile AirlineChannel -outputAnchorPeersUpdate $ANCHOR_UPDATE_TX -channelID $CHANNEL_ID -asOrg BudgetMSP

echo    '================ Launch the network ================'
$DIR/dev-start.sh

# Couch DB takes time to start
if [ "$LAUNCH_SCRIPT_DB" != "" ]; then 
    echo "Giving time to CouchDB to Launch ... "
    sleep $COUCHDB_SLEEP_TIME
fi

export CORE_PEER_ID=init.sh
mylog_write "# CORE_PEER_ID: $CORE_PEER_ID"
echo    '========= Submitting txn for channel creation as AcmeAdmin ============'
mylog_write "========= Submitting txn for channel creation as AcmeAdmin ============"
CRYPTO_CONFIG_ROOT_FOLDER=$DIR/../crypto/crypto-config/peerOrganizations
mylog_write "# CRYPTO_CONFIG_ROOT_FOLDER: $DIR/../crypto/crypto-config/peerOrganizations"
ORG_NAME=acme.com
mylog_write "# ORG_NAME: $ORG_NAME"
CHANNEL_TX_FILE=$DIR/../config/airline-channel.tx
mylog_write "# CHANNEL_TX_FILE: $CHANNEL_TX_FILE"
ORDERER_ADDRESS=localhost:7050
mylog_write "# ORDERER_ADDRESS: $ORDERER_ADDRESS"
export CORE_PEER_LOCALMSPID=AcmeMSP
mylog_write "# CORE_PEER_LOCALMSPID: $CORE_PEER_LOCALMSPID"
export CORE_PEER_MSPCONFIGPATH=$CRYPTO_CONFIG_ROOT_FOLDER/$ORG_NAME/users/Admin@acme.com/msp
mylog_write "# CORE_PEER_MSPCONFIGPATH: $CORE_PEER_MSPCONFIGPATH"
peer channel create -o $ORDERER_ADDRESS -c airlinechannel -f $CHANNEL_TX_FILE


sleep $SLEEP_TIME

echo    '========= Joining the acme-peer1 to Airline channel ============'
mylog_write "========= Joining the acme-peer1 to Airline channel ============"
AIRLINE_CHANNEL_BLOCK=./airlinechannel.block
mylog_write "# AIRLINE_CHANNEL_BLOCK: $AIRLINE_CHANNEL_BLOCK"
export CORE_PEER_ADDRESS=acme-peer1.acme.com:7051
mylog_write "# CORE_PEER_ADDRESS: $CORE_PEER_ADDRESS"
peer channel join -o $ORDERER_ADDRESS -b $AIRLINE_CHANNEL_BLOCK
# Update anchor peer on channel for acme
# sleep  3s
sleep $SLEEP_TIME
ANCHOR_UPDATE_TX=$DIR/../config/airline-anchor-update-acme.tx
mylog_write "# ANCHOR_UPDATE_TX: $ANCHOR_UPDATE_TX"
peer channel update -o $ORDERER_ADDRESS -c airlinechannel -f $ANCHOR_UPDATE_TX

echo    '========= Joining the budget-peer1 to Airline channel ============'
mylog_write "========= Joining the budget-peer1 to Airline channel ============"
# peer channel fetch config $AIRLINE_CHANNEL_BLOCK -o $ORDERER_ADDRESS -c airlinechannel
export CORE_PEER_LOCALMSPID=BudgetMSP
mylog_write "# CORE_PEER_LOCALMSPID: $CORE_PEER_LOCALMSPID"
ORG_NAME=budget.com
mylog_write "# ORG_NAME: $ORG_NAME"
export CORE_PEER_ADDRESS=budget-peer1.budget.com:8051
mylog_write "# CORE_PEER_ADDRESS: $CORE_PEER_ADDRESS"
export CORE_PEER_MSPCONFIGPATH=$CRYPTO_CONFIG_ROOT_FOLDER/$ORG_NAME/users/Admin@budget.com/msp
mylog_write "# CORE_PEER_MSPCONFIGPATH: $CORE_PEER_MSPCONFIGPATH"
peer channel join -o $ORDERER_ADDRESS -b $AIRLINE_CHANNEL_BLOCK
# Update anchor peer on channel for budget
sleep  $SLEEP_TIME
ANCHOR_UPDATE_TX=$DIR/../config/airline-anchor-update-budget.tx
mylog_write "# ANCHOR_UPDATE_TX: $ANCHOR_UPDATE_TX"
peer channel update -o $ORDERER_ADDRESS -c airlinechannel -f $ANCHOR_UPDATE_TX

# Initialize the explorer only if -e option was used
mylog_write "# LAUNCH_SCRIPT_EXPLORER: $LAUNCH_SCRIPT_EXPLORER"
if [ "$LAUNCH_SCRIPT_EXPLORER" != "" ]; then
    echo "=========  Initializing the Explorer ============"
    exp-init.sh
    echo  ""
    echo  "Done. To validate execute validate.sh & hit browser to http://localhost:8080"
fi

echo    '========= Anchor peer update tx for BudgetMSP ====='



echo    '========= Anchor peer update tx for AcmeMSP ====='
# export ORG_NAME=acme.com
# export CORE_PEER_LOCALMSPID=AcmeMSP
# export CORE_PEER_MSPCONFIGPATH=$CRYPTO_CONFIG_ROOT_FOLDER/$ORG_NAME/users/Admin@acme.com/msp

mylog_write "# AIRLINE_CHANNEL_BLOCK: $AIRLINE_CHANNEL_BLOCK"

rm  $AIRLINE_CHANNEL_BLOCK

echo "=== Initialization completed * Environment launched ==="
echo "=== dev-stop.sh    to stop"
echo "=== dev-start.sh   to start"
echo "Done."