#!/bin/bash
# (C) Copyright 2012,2013 Continuent, Inc - Released under the New BSD License
# Version 1.0.14 - 2014-05-27

cookbook_dir=$(dirname $0)
cd "$cookbook_dir/.."
STAGING_DIRECTORY=$PWD

SSH='ssh -o StrictHostKeyChecking=no'
SCP='scp -o StrictHostKeyChecking=no'
DASHLINE="## -------------------------------------------------------------------------------------"
NODES=$1
if [ -z "$NODES" ]
then
    echo "We need a NODES file to work with"
    exit 1
fi

CURDIR=`dirname $0`

if [ -x "$CURDIR/simple_services" ]
then
    SIMPLE_SERVICES=$CURDIR/simple_services
else
    for P in `echo $PATH |tr ':' ' '` 
    do
        if [ -x $P/simple_services ]
        then
            SIMPLE_SERVICES=$P/simple_services
            continue
        fi
    done
fi

if [ -z "$SIMPLE_SERVICES" ]
then
    echo "simple_services is not installed. "
    echo "While not strictly necessary for the recipes installation, it is needed to run the auxuliary scripts."
    echo "Please get it from http://code.google.com/p/tungsten-toolbox/ and put it in the \$PATH"
    exit 1
fi

if [ ! -f $cookbook_dir/$NODES ]
then
    echo "$cookbook_dir/$NODES not found"
    exit 1
fi

. $cookbook_dir/$NODES

if [ -z "${ALL_NODES[0]}" ]
then
    echo "Nodes variables not set"
    echo "Please edit cookbook/COMMON_NODES.sh or cookbook/NODES*.sh"
    echo "Make sure that NODE1, NODE2, etc are filled"
    exit 1
fi

HOSTS_LIST=""
MASTERS_LIST=""
SLAVES_LIST=""
MASTER_SERVICES_LIST=""
export LONG_LINE="--------------------------------------------------------------------------------------"

for NODE in ${ALL_NODES[*]}
do
   [ -n "$HOSTS_LIST" ] && HOSTS_LIST="$HOSTS_LIST,"
   HOSTS_LIST="$HOSTS_LIST$NODE"
done

service_count=0
for NODE in ${SLAVES[*]}
do
   [ -n "$SLAVES_LIST" ] && SLAVES_LIST="$SLAVES_LIST,"
   SLAVES_LIST="$SLAVES_LIST$NODE"
done

service_count=0
for NODE in ${MASTERS[*]}
do
    unset SKIP
    if [ -n "$HUB" ]
    then
        if [ "$HUB" == "$NODE" ]
        then
            SKIP=1
            service_count=$(($service_count+1))
        fi
    fi
    if [ -z "$SKIP" ]
    then
        [ -n "$MASTERS_LIST" ] && MASTERS_LIST="$MASTERS_LIST,"
        [ -n "$MASTER_SERVICES_LIST" ] && MASTER_SERVICES_LIST="$MASTER_SERVICES_LIST,"
        MASTERS_LIST="$MASTERS_LIST$NODE"
        MASTER_SERVICES_LIST="$MASTER_SERVICES_LIST${MM_SERVICES[$service_count]}"
        service_count=$(($service_count+1))
    fi
done

export MASTERS_LIST
export SLAVES_LIST
export HOSTS_LIST
export MASTER_SERVICES_LIST

CURRENT_HOST=$(hostname)
INSTALLER_IN_CLUSTER=0
# CURRENT_HOST_IP=$(hostname --ip)
CURRENT_HOST_IPs=$(/sbin/ifconfig |perl -lne 'if ( /inet/) {print $1 if /\s*(\d+\.\d+\.\d+\.\d+)/}')

[ -z "$VERBOSE" ] && export VERBOSE=1
if [ -n "$NOVERBOSE" -o -n "$QUIET" ]
then
    unset VERBOSE
fi

export USE_TPM=1

function check_if_nodes_are_reachable
{
    for NODE in ${ALL_NODES[*]}
    do
        NODE_ANSWER=/tmp/node_answer$$
        [ -f $NODE_ANSWER ] && rm -f $NODE_ANSWER
        ping -c 1 $NODE > $NODE_ANSWER 2>&1
        if [ $? != "0" ]
        then
            echo $DASHLINE
            echo "# node $NODE is unreachable"
            echo "# check the entries in $cookbook_dir/COMMON_NODES.sh"
            echo $DASHLINE
            cat $NODE_ANSWER
            rm -f $NODE_ANSWER
            exit 1
        fi 
        [ -f $NODE_ANSWER ] && rm -f $NODE_ANSWER
    done
}

function timer
{
    timeout=$1
    step=$2
    [ -z "$step" ] && step=5
        for N in $(seq 1 $timeout)
        do
            MOD_STEP=$(($N%$step))
            if [ "$MOD_STEP" == "0" ]
            then
                echo -n "$N"
            else
                echo -n '.'
            fi
            sleep 1
        done
        echo ''
}

function check_if_installer_is_in_cluster
{
    for HOST in ${ALL_NODES[*]}
    do
        if [ "$HOST" == "$CURRENT_HOST" ]
        then
            INSTALLER_IN_CLUSTER=1
            return
        else
            for CURRENT_HOST_IP in $CURRENT_HOST_IPs
            do
                if [ "$CURRENT_HOST_IP" != '127.0.0.1' ]
                then
                    # Check if the IP for the hostname is associated with
                    # one of the hosts defined for this cluster
                    for LINE in $(grep $CURRENT_HOST_IP /etc/hosts | grep -v '^#')
                    do
                        for ITEM in $LINE
                        do
                            if [ "$ITEM" == "$CURRENT_HOST" ]
                            then
                            INSTALLER_IN_CLUSTER=1
                            return
                            fi
                        done 
                    done
                fi
            done
        fi
    done
}

check_if_installer_is_in_cluster

if [ "$INSTALLER_IN_CLUSTER" != "1" ]
then
    if [ -z "$IGNORE_INSTALLER_NOT_IN_CLUSTER" ]
    then
        echo "This framework is designed to act within the cluster that is installing"
        echo "The current host ($CURRENT_HOST) is not among the designated servers (${ALL_NODES[*]})"
        echo ""
        echo "You can override this check by setting the variable IGNORE_INSTALLER_NOT_IN_CLUSTER."
        echo "But if you do, be warned that, even though the installation **may** succeed,"
        echo "some tools in the cookbook toolkit will not work at all"
        exit 1
    fi
fi

. $cookbook_dir/USER_VALUES.sh

[ -z "$MY_CNF" ] && export MY_CNF=/etc/my.cnf
if [ ! -f $MY_CNF ]
then
    UBUNTU_MY_CNF=/etc/mysql/my.cnf
    if [ -f $UBUNTU_MY_CNF ]
    then
        MY_CNF=$UBUNTU_MY_CNF
    else
        echo "could not find a configuration file (either $MY_CNF or $UBUNTU_MY_CNF)"
        exit 1
    fi
fi

export REPLICATOR=$TUNGSTEN_BASE/tungsten/tungsten-replicator/bin/replicator
export TREPCTL="$TUNGSTEN_BASE/tungsten/tungsten-replicator/bin/trepctl -port $RMI_PORT"
export MULTI_TREPCTL="$TUNGSTEN_BASE/tungsten/tungsten-replicator/scripts/multi_trepctl"
export TUNGSTEN_SET_POSITION="$TUNGSTEN_BASE/tungsten/tungsten-replicator/scripts/tungsten_set_position"
export TUNGSTEN_PROVISION_SLAVE="$TUNGSTEN_BASE/tungsten/tungsten-replicator/scripts/tungsten_provision_slave"
export TUNGSTEN_READ_MASTER_EVENTS="$TUNGSTEN_BASE/tungsten/tungsten-replicator/scripts/tungsten_read_master_events"
export THL=$TUNGSTEN_BASE/tungsten/tungsten-replicator/bin/thl
export INSTALL_LOG=$cookbook_dir/current_install.log
export INSTALL_SUMMARY=$cookbook_dir/current_install.summary
export DEPLOY_VARS=$cookbook_dir/deploy_vars.sh
export STAGING_INFO=$HOME/tungsten_replicator_staging.info

if [ -n "$WRITE_STAGING_INFO" ]
then
    if [ -d $WRITE_STAGING_INFO ]
    then
        for NODE in ${ALL_NODES[*]}
        do
            DIR_EXISTS=$($SSH $NODE "if [ -d $WRITE_STAGING_INFO ] ; then echo yes ; fi")
            if [ "$DIR_EXISTS" != "yes" ]
            then
                echo "###  Directory '$WRITE_STAGING_INFO' does not exist in node $NODE"
                CONFLICT=1
            fi
        done
        if [ -n "$CONFLICT" ]
        then
            exit 1
        fi
        STAGING_INFO=$(basename $STAGING_INFO)
        export STAGING_INFO="$WRITE_STAGING_INFO/$STAGING_INFO"
    fi 
fi

CURRENT_TOPOLOGY=$cookbook_dir/../CURRENT_TOPOLOGY
MY_COOKBOOK_CNF=$STAGING_DIRECTORY/cookbook/my.cookbook.cnf
MYSQL="mysql --defaults-file=$MY_COOKBOOK_CNF"
MYSQLDUMP="mysqldump --defaults-file=$MY_COOKBOOK_CNF"
MYSQLADMIN="mysqladmin --defaults-file=$MY_COOKBOOK_CNF"
[ -z "$DEPLOYMENT_BANNER" ] && DEPLOYMENT_BANNER=''

if [ -n "$DEPLOYMENT_BANNER" ]
then
    if [ -z "$(echo $DEPLOYMENT_BANNER | grep 'tpm\|t-i')" ]
    then
        if [ -n "$USE_TPM" ]
        then
            DEPLOYMENT_BANNER="$DEPLOYMENT_BANNER - tpm"
        else
            DEPLOYMENT_BANNER="$DEPLOYMENT_BANNER - t-i"
        fi
    fi
    if [ -z "$(echo $DEPLOYMENT_BANNER | grep 'ssl\|unencrypted')" ]
    then
        if [ -n "$WITH_SECURITY" ]
        then
            DEPLOYMENT_BANNER="$DEPLOYMENT_BANNER - ssl"
        else
            DEPLOYMENT_BANNER="$DEPLOYMENT_BANNER - unencrypted"
        fi
    fi
    export DEPLOYMENT_BANNER
fi

function check_installed
{
    if [ -f $CURRENT_TOPOLOGY ]
    then
        echo "There is a previous installation recorded in $CURRENT_TOPOLOGY"
        cat $CURRENT_TOPOLOGY
        TOPOLOGY=$(cat $CURRENT_TOPOLOGY)
        echo "Run cookbook/clear_cluster to remove this installation"
        exit 1
    fi 
    if [ -n "$WRITE_STAGING_INFO" ]
    then
        if [ -f $STAGING_INFO ]
        then
            if [ -n "$I_WANT_TO_UNINSTALL" ]
            then
                staging_host=$(perl -ne 'print $1 if /Staging server\s+: (\S+)/' $STAGING_INFO)
                staging_dir=$(perl -ne 'print $1 if /Staging directory\s+: (\S+)/' $STAGING_INFO)
                uninstall_exist=$($SSH $staging_host "if [ -x $staging_dir/cookbook/clear_cluster ] ; then echo yes ; fi")
                if [ -n "$uninstall_exist" ]
                then
                    $SSH $staging_host "I_WANT_TO_UNINSTALL=1 $staging_dir/cookbook/clear_cluster"
                fi
            else
                echo "Found file $STAGING_INFO"
                echo "It indicates a previous installation"
                exit 1
            fi
        fi
    fi
}

keystore=$cookbook_dir/keystore.jks
truststore=$cookbook_dir/truststore.ts
certificate=$cookbook_dir/client.cer
password_store=$cookbook_dir/passwords.store
jmxremote=$cookbook_dir/jmxremote.access
security_options=$cookbook_dir/security.options

security_files=( $keystore $truststore $certificate $password_store $jmxremote $security_options )

function check_security_files
{
    all_files_exist=1
    for SF in ${security_files[*]}
    do
        if [ ! -f $SF ]
        then
            echo "Missing file $SF"
            all_files_exist=0
        fi
    done
    if [ "$all_files_exist" == "0" ]
    then
        exit 1
    fi
}


function check_security
{
    if [ -n "$WITH_SECURITY" ]
    then
       if [ -f $security_options ]
       then
            export SECURITY_OPTIONS=$(cat $security_options)
        else
            if [ -x "$cookbook_dir/create-security-keys" ]
            then
                $cookbook_dir/create-security-keys cookbookpass
                check_security_files
                export SECURITY_OPTIONS=$(cat $security_options)
            else
                echo "$cookbook_dir/create-security-keys not found"
                exit 1
            fi 
       fi 
    fi
}

function check_current_topology
{
    if [ -f $CURRENT_TOPOLOGY ]
    then
        WANTED=$1
        TOPOLOGY=$(cat $CURRENT_TOPOLOGY)
        if [ "$TOPOLOGY" != "$WANTED" ]
        then
            echo "this script requires a $WANTED topology."
            echo "Found a different topology ($TOPOLOGY) in $CURRENT_TOPOLOGY"
            exit 1
        fi
    else
        echo "$CURRENT_TOPOLOGY not found"
        echo "Cannot determine if $WANTED topology is deployed"
        exit 1
    fi
}

function are_you_sure_you_want_to_clear
{
    echo $LONG_LINE
    echo "!!! WARNING !!!"
    echo $LONG_LINE
    echo "'clear-cluster' is a potentially damaging operation."
    echo "This command will do all the following:"
    if [ "$STOP_REPLICATORS" == 1 ]
    then
        echo "* Stop the replication software in all servers. [\$STOP_REPLICATORS]"
    fi
    if [ "$REMOVE_TUNGSTEN_BASE" == "1" ]
    then
        echo "* REMOVE ALL THE CONTENTS from $TUNGSTEN_BASE/.[\$REMOVE_TUNGSTEN_BASE]"
    fi
    if [ "$REMOVE_SERVICE_SCHEMA" == "1" ]
    then
        echo "* REMOVE the tungsten_<service_name> schemas in all nodes (${ALL_NODES[*]}) [\$REMOVE_SERVICE_SCHEMA] "
    fi
    if [ "$REMOVE_TEST_SCHEMAS" == "1" ]
    then
        echo "* REMOVE the schemas created for testing (test, evaluator) in all nodes (${ALL_NODES[*]})  [\$REMOVE_TEST_SCHEMAS]"
    fi
    if [ "$REMOVE_DATABASE_CONTENTS" == "1" ]
    then
        echo "* REMOVE *** ALL THE DATABASE CONTENTS *** in all nodes (${ALL_NODES[*]}) [\$REMOVE_DATABASE_CONTENTS] "
    fi
    if [ "$CLEAN_NODE_DATABASE_SERVER" == "1" ]
    then
        echo "* Create the test server anew;                [\$CLEAN_NODE_DATABASE_SERVER]"
        echo "* Unset the read_only variable;               [\$CLEAN_NODE_DATABASE_SERVER]"
        echo "* Set the binlog format to MIXED;             [\$CLEAN_NODE_DATABASE_SERVER]"
        echo "* Reset the master (removes all binary logs); [\$CLEAN_NODE_DATABASE_SERVER]"
    fi
    if [ -z "$I_WANT_TO_UNINSTALL" ]
    then
        echo "If this is what you want, either set the variable I_WANT_TO_UNINSTALL "
        echo "or answer 'y' to the question below"
        echo "You may also set the variables in brackets to fine tune the execution."
        echo "Alternatively, have a look at $0 and customize it to your needs."
    else
        echo "***"
        echo "The variable \$I_WANT_TO_UNINSTALL was set. No confirmation is required."
        echo "***"
    fi
    echo "--------------------------------------------------------------------------------------"

    while [ -z "$I_WANT_TO_UNINSTALL" ] ; do
        read -p 'Do you wish to uninstall this cluster? [y/n] ' yn 
        case $yn in 
            [Yy]* ) I_WANT_TO_UNINSTALL=YES;; 
            [Nn]* ) exit;;
            * ) echo 'Please answer (y) or (n).';;
        esac
    done
}

function write_my_cookbook_cnf
{
    echo '[client]'                           > $MY_COOKBOOK_CNF
    echo "user=$DATABASE_USER"               >> $MY_COOKBOOK_CNF
    echo "password=$DATABASE_PASSWORD"       >> $MY_COOKBOOK_CNF
    echo "port=$DATABASE_PORT"               >> $MY_COOKBOOK_CNF
    echo "host=__HOST__"                     >> $MY_COOKBOOK_CNF
    echo ''                                  >> $MY_COOKBOOK_CNF
    echo '[mysql]'                           >> $MY_COOKBOOK_CNF
    echo "prompt='*mysql [\h] {\u} (\d) > '" >> $MY_COOKBOOK_CNF
}

function post_installation
{
    write_my_cookbook_cnf
    TOPOLOGY=$(cat $CURRENT_TOPOLOGY)
    DB_USE=$cookbook_dir/db_use
    TUNGSTEN_RELEASE=$(grep RELEASE $cookbook_dir/../.manifest| awk '{print $2}')  
    DB_USE=$STAGING_DIRECTORY/cookbook/db_use
    INSTALLATION_TOOL='tpm'
    SECURITY_STATUS="no (unencrypted)"
    if [ -n "$WITH_SECURITY" ]
    then
        SECURITY_STATUS="yes (encrypted with ssl)"
    fi
    echo "Deployment completed "
    echo "Topology           :'$TOPOLOGY'"                                            > $INSTALL_SUMMARY
    echo "Tungsten path      : $TUNGSTEN_BASE "                                      >> $INSTALL_SUMMARY
    echo "Staging server     : $(hostname)"                                          >> $INSTALL_SUMMARY
    echo "Staging directory  : $PWD"                                                 >> $INSTALL_SUMMARY
    echo "Installation tool  : $INSTALLATION_TOOL"                                   >> $INSTALL_SUMMARY
    echo "Security enabled   : $SECURITY_STATUS"                                     >> $INSTALL_SUMMARY
    echo "Nodes              : (${ALL_NODES[*]})"                                    >> $INSTALL_SUMMARY
    echo "Master services    : (${MASTERS[*]})"                                      >> $INSTALL_SUMMARY
    echo "Slave services     : (${SLAVES[*]})"                                       >> $INSTALL_SUMMARY
    echo "MySQL version      : $($MYSQL -h ${MASTERS[0]} -BN -e 'select @@version')" >> $INSTALL_SUMMARY
    echo "MySQL port         : $DATABASE_PORT"                                       >> $INSTALL_SUMMARY
    echo "MySQL shortcut     : $MYSQL"                                               >> $INSTALL_SUMMARY
    echo "                   : (or $DB_USE)"                                         >> $INSTALL_SUMMARY
    echo "Tungsten release   : $TUNGSTEN_RELEASE"                                    >> $INSTALL_SUMMARY
    echo "Installation log   : $INSTALL_LOG"                                         >> $INSTALL_SUMMARY

    echo "topology=$TOPOLOGY"                                             > $DEPLOY_VARS
    echo "tungsten_path=$TUNGSTEN_BASE "                                      >> $DEPLOY_VARS
    echo "staging_server=$(hostname)"                                          >> $DEPLOY_VARS
    echo "staging_directory=$PWD"                                                 >> $DEPLOY_VARS
    echo "installation_tool=$INSTALLATION_TOOL"                                   >> $DEPLOY_VARS
    echo "security_enabled='$SECURITY_STATUS'"                                     >> $DEPLOY_VARS
    echo "nodes=(${ALL_NODES[*]})"                                    >> $DEPLOY_VARS
    echo "master_services=(${MASTERS[*]})"                                      >> $DEPLOY_VARS
    echo "slave_services=(${SLAVES[*]})"                                       >> $DEPLOY_VARS
    echo "mysql_version=$($MYSQL -h ${MASTERS[0]} -BN -e 'select @@version')" >> $DEPLOY_VARS
    echo "mysql_port=$DATABASE_PORT"                                       >> $DEPLOY_VARS
    echo "tungsten_release=$TUNGSTEN_RELEASE"                                    >> $DEPLOY_VARS
    echo "installation_log=$INSTALL_LOG"                                         >> $DEPLOY_VARS



    MY_BARE_CNF=$(basename $MY_COOKBOOK_CNF)
    echo "#!/bin/bash" > $DB_USE
    echo 'cookbook_dir=$(dirname $0)' >> $DB_USE
    echo "mysql --defaults-file=\$cookbook_dir/$MY_BARE_CNF \"\$@\"" >> $DB_USE
    chmod +x $DB_USE

    for NODE in ${ALL_NODES[*]}
    do  
        MY_REMOTE_CNF=/tmp/my_template$$.cnf
        cp $MY_COOKBOOK_CNF $MY_REMOTE_CNF
        perl -i -pe "s/__HOST__/$NODE/" $MY_REMOTE_CNF
        DEPLOYED=$($SSH $NODE "if [ -d $TUNGSTEN_BASE ] ; then echo 'yes' ; fi")
        if [ "$DEPLOYED" == "yes" ]
        then
            $SCP -q $CURRENT_TOPOLOGY $NODE:$TUNGSTEN_BASE/tungsten/  
            $SCP -q $MY_REMOTE_CNF $NODE:$TUNGSTEN_BASE/tungsten/cookbook/$MY_BARE_CNF
            $SCP -q $INSTALL_LOG $NODE:$TUNGSTEN_BASE/tungsten/cookbook/
            $SCP -q $INSTALL_SUMMARY $NODE:$TUNGSTEN_BASE/tungsten/cookbook/
            if [ -n "$WRITE_STAGING_INFO" ]
            then
                $SCP -q $INSTALL_SUMMARY $NODE:$STAGING_INFO
            fi
            $SCP -q $DB_USE $NODE:$TUNGSTEN_BASE/tungsten/cookbook/
        fi
        rm $MY_REMOTE_CNF
    done
    cp $TUNGSTEN_BASE/tungsten/cookbook/$MY_BARE_CNF $MY_COOKBOOK_CNF
    cat $INSTALL_SUMMARY

}

