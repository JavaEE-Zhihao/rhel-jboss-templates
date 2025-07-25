#!/bin/sh
log() {
    while IFS= read -r line; do
        printf '%s %s\n' "$(date "+%Y-%m-%d %H:%M:%S")" "$line" >> /var/log/jbosseap.install.log
    done
}

openport() {
    port=$1

    echo "firewall-cmd --zone=public --add-port=$port/tcp  --permanent" | log; flag=${PIPESTATUS[0]}
    sudo firewall-cmd  --zone=public --add-port=$port/tcp  --permanent  | log; flag=${PIPESTATUS[0]}
}

JBOSS_EAP_USER=$1
JBOSS_EAP_PASSWORD_BASE64=$2
JBOSS_EAP_PASSWORD=$(echo $JBOSS_EAP_PASSWORD_BASE64 | base64 -d)
RHSM_USER=$3
RHSM_PASSWORD_BASE64=$4
RHSM_PASSWORD=$(echo $RHSM_PASSWORD_BASE64 | base64 -d)
RHSM_EAPPOOL=$5
RHSM_RHELPOOL=$6
CONNECT_SATELLITE=${7}
SATELLITE_ACTIVATION_KEY_BASE64=${8}
SATELLITE_ACTIVATION_KEY=$(echo $SATELLITE_ACTIVATION_KEY_BASE64 | base64 -d)
SATELLITE_ORG_NAME_BASE64=${9}
SATELLITE_ORG_NAME=$(echo $SATELLITE_ORG_NAME_BASE64 | base64 -d)
SATELLITE_VM_FQDN=${10}
JDK_VERSION=${11}
enableDB=${12}
dbType=${13}
jdbcDSJNDIName=${14}
dsConnectionString=${15}
databaseUser=${16}
databasePassword=${17}
gracefulShutdownTimeout=${18}
enablePswlessConnection=${19}
uamiClientId=${20}
NODE_ID=$(uuidgen | sed 's/-//g' | cut -c 1-23)

if [[ "${JDK_VERSION,,}" == "eap8-openjdk17" || "${JDK_VERSION,,}" == "eap8-openjdk11" ]]; then

    export EAP_HOME="/opt/rh/eap8/root/usr/share/wildfly"
    export EAP_RPM_CONF_STANDALONE="/etc/opt/rh/eap8/wildfly/eap8-standalone.conf"
    export EAP_LAUNCH_CONFIG="/opt/rh/eap8/root/usr/share/wildfly/bin/standalone.conf"

    echo 'export EAP_HOME="/opt/rh/eap8/root/usr/share/wildfly"' >> ~/.bash_profile
    echo 'export EAP_RPM_CONF_STANDALONE="/etc/opt/rh/eap8/wildfly/eap8-standalone.conf"' >> ~/.bash_profile
    source ~/.bash_profile
    touch /etc/profile.d/eap_env.sh
    echo 'export EAP_HOME="/opt/rh/eap8/root/usr/share/wildfly"' >> /etc/profile.d/eap_env.sh
    echo 'export EAP_RPM_CONF_STANDALONE="/etc/opt/rh/eap7/wildfly/eap8-standalone.conf"' >> /etc/profile.d/eap_env.sh

else

    export EAP_HOME="/opt/rh/eap7/root/usr/share/wildfly"
    export EAP_RPM_CONF_STANDALONE="/etc/opt/rh/eap7/wildfly/eap7-standalone.conf"
    export EAP_LAUNCH_CONFIG="/opt/rh/eap7/root/usr/share/wildfly/bin/standalone.conf"

    echo 'export EAP_HOME="/opt/rh/eap7/root/usr/share/wildfly"' >> ~/.bash_profile
    echo 'export EAP_RPM_CONF_STANDALONE="/etc/opt/rh/eap7/wildfly/eap7-standalone.conf"' >> ~/.bash_profile
    source ~/.bash_profile
    touch /etc/profile.d/eap_env.sh
    echo 'export EAP_HOME="/opt/rh/eap7/root/usr/share/wildfly"' >> /etc/profile.d/eap_env.sh
    echo 'export EAP_RPM_CONF_STANDALONE="/etc/opt/rh/eap7/wildfly/eap7-standalone.conf"' >> /etc/profile.d/eap_env.sh

fi

# Satellite server configuration
if [[ "${CONNECT_SATELLITE,,}" == "true" ]]; then
    ####################### Register to satellite server
    echo "Configuring Satellite server registration" | log; flag=${PIPESTATUS[0]}

    echo "sudo rpm -Uvh http://${SATELLITE_VM_FQDN}/pub/katello-ca-consumer-latest.noarch.rpm" | log; flag=${PIPESTATUS[0]}
    sudo rpm -Uvh http://${SATELLITE_VM_FQDN}/pub/katello-ca-consumer-latest.noarch.rpm | log; flag=${PIPESTATUS[0]}

    echo "sudo subscription-manager clean" | log; flag=${PIPESTATUS[0]}
    sudo subscription-manager clean | log; flag=${PIPESTATUS[0]}

    echo "sudo subscription-manager register --org=${SATELLITE_ORG_NAME} --activationkey=${SATELLITE_ACTIVATION_KEY}" | log; flag=${PIPESTATUS[0]}
    sudo subscription-manager register --org="${SATELLITE_ORG_NAME}" --activationkey="${SATELLITE_ACTIVATION_KEY}" --force | log; flag=${PIPESTATUS[0]}
else
    echo "Initial JBoss EAP setup" | log; flag=${PIPESTATUS[0]}
    echo "subscription-manager register --username RHSM_USER --password RHSM_PASSWORD" | log; flag=${PIPESTATUS[0]}
    subscription-manager register --username $RHSM_USER --password $RHSM_PASSWORD --force  | log; flag=${PIPESTATUS[0]}
    if [ $flag != 0 ] ; then echo "ERROR! Red Hat Subscription Manager Registration Failed" >&2 log; exit $flag;  fi

    echo "Subscribing the system to get access to JBoss EAP repos ($RHSM_EAPPOOL)" | log; flag=${PIPESTATUS[0]}
    echo "subscription-manager attach --pool=EAP_POOL" | log; flag=${PIPESTATUS[0]}
    subscription-manager attach --pool=${RHSM_EAPPOOL} | log; flag=${PIPESTATUS[0]}
    if [ $flag != 0 ] ; then echo  "ERROR! Pool Attach for JBoss EAP Failed" >&2 log; exit $flag;  fi

    if [ "$RHSM_EAPPOOL" != "$RHSM_RHELPOOL" ]; then
        echo "Subscribing the system to get access to RHEL repos ($RHSM_RHELPOOL)" | log; flag=${PIPESTATUS[0]}
        subscription-manager attach --pool=${RHSM_RHELPOOL}  | log; flag=${PIPESTATUS[0]}
        if [ $flag != 0 ] ; then echo  "ERROR! Pool Attach for RHEL Failed" >&2 log; exit $flag;  fi
    else
        echo "Using the same pool to get access to RHEL repos" | log; flag=${PIPESTATUS[0]}
    fi
fi

####################### Install required dependencies
echo "Install curl, wget, git, unzip, vim" | log; flag=${PIPESTATUS[0]}
echo "sudo yum install curl wget unzip vim git -y" | log; flag=${PIPESTATUS[0]}
sudo yum install curl wget unzip vim git -y | log; flag=${PIPESTATUS[0]}

# workaround to this issue:https://github.com/azure-javaee/rhel-jboss-templates/issues/2
sudo update-crypto-policies --set DEFAULT:SHA1 | log; flag=${PIPESTATUS[0]}

####################### 

if [[ "${JDK_VERSION,,}" == "eap8-openjdk17" || "${JDK_VERSION,,}" == "eap8-openjdk11" ]]; then
# Install JBoss EAP 8
    echo "subscription-manager repos --enable=jb-eap-8.0-for-rhel-9-x86_64-rpms"         | log; flag=${PIPESTATUS[0]}
    subscription-manager repos --enable=jb-eap-8.0-for-rhel-9-x86_64-rpms                | log; flag=${PIPESTATUS[0]}
    if [ $flag != 0 ] ; then echo  "ERROR! Enabling repos for JBoss EAP Failed" >&2 log; exit $flag;  fi

    if [[ "${JDK_VERSION,,}" == "eap8-openjdk17" ]]; then

        echo "Installing JBoss EAP 8 JDK 17" | log; flag=${PIPESTATUS[0]}
        echo "yum groupinstall -y jboss-eap8" | log; flag=${PIPESTATUS[0]}
        yum groupinstall -y jboss-eap8       | log; flag=${PIPESTATUS[0]}
        if [ $flag != 0 ] ; then echo  "ERROR! JBoss EAP installation Failed" >&2 log; exit $flag;  fi
    
    elif [[ "${JDK_VERSION,,}" == "eap8-openjdk11" ]]; then
        echo "Installing JBoss EAP 8 JDK 11" | log; flag=${PIPESTATUS[0]}
        echo "yum groupinstall -y jboss-eap8-jdk11" | log; flag=${PIPESTATUS[0]}
        yum groupinstall -y jboss-eap8-jdk11       | log; flag=${PIPESTATUS[0]}
        if [ $flag != 0 ] ; then echo  "ERROR! JBoss EAP installation Failed" >&2 log; exit $flag;  fi
    fi

else
# Install JBoss EAP 7.4
    echo "subscription-manager repos --enable=jb-eap-7.4-for-rhel-8-x86_64-rpms"         | log; flag=${PIPESTATUS[0]}
    subscription-manager repos --enable=jb-eap-7.4-for-rhel-8-x86_64-rpms                | log; flag=${PIPESTATUS[0]}
    if [ $flag != 0 ] ; then echo  "ERROR! Enabling repos for JBoss EAP Failed" >&2 log; exit $flag;  fi

    if [[ "${JDK_VERSION,,}" == "eap74-openjdk17" ]]; then
        echo "Installing JBoss EAP 7.4 JDK 17" | log; flag=${PIPESTATUS[0]}
        echo "yum groupinstall -y jboss-eap7-jdk17" | log; flag=${PIPESTATUS[0]}
        yum groupinstall -y jboss-eap7-jdk17       | log; flag=${PIPESTATUS[0]}
        if [ $flag != 0 ] ; then echo  "ERROR! JBoss EAP installation Failed" >&2 log; exit $flag;  fi
    
    elif [[ "${JDK_VERSION,,}" == "eap74-openjdk11" ]]; then
        echo "Installing JBoss EAP 7.4 JDK 11" | log; flag=${PIPESTATUS[0]}
        echo "yum groupinstall -y jboss-eap7-jdk11" | log; flag=${PIPESTATUS[0]}
        yum groupinstall -y jboss-eap7-jdk11       | log; flag=${PIPESTATUS[0]}
        if [ $flag != 0 ] ; then echo  "ERROR! JBoss EAP installation Failed" >&2 log; exit $flag;  fi
    
     elif [[ "${JDK_VERSION,,}" == "eap74-openjdk8" ]]; then
        echo "Installing JBoss EAP 7.4 JDK 8" | log; flag=${PIPESTATUS[0]}
        echo "yum groupinstall -y jboss-eap7" | log; flag=${PIPESTATUS[0]}
        yum groupinstall -y jboss-eap7       | log; flag=${PIPESTATUS[0]}
        if [ $flag != 0 ] ; then echo  "ERROR! JBoss EAP installation Failed" >&2 log; exit $flag;  fi
    fi

fi

echo "Updating standalone-full-ha.xml" | log; flag=${PIPESTATUS[0]}
echo -e "\t stack UDP to TCP"       | log; flag=${PIPESTATUS[0]}
echo -e "\t set transaction id"     | log; flag=${PIPESTATUS[0]}

## OpenJDK 17 specific logic
if [[ "${JDK_VERSION,,}" == "eap74-openjdk17" ]]; then
    sudo -u jboss $EAP_HOME/bin/jboss-cli.sh --file=$EAP_HOME/docs/examples/enable-elytron-se17.cli -Dconfig=standalone-full-ha.xml
fi

sudo -u jboss $EAP_HOME/bin/jboss-cli.sh --echo-command \
"embed-server --std-out=echo  --server-config=standalone-full-ha.xml",\
'/subsystem=transactions:write-attribute(name=node-identifier,value="'${NODE_ID}'")',\
'/subsystem=jgroups/channel=ee:write-attribute(name="stack", value="tcp")' | log; flag=${PIPESTATUS[0]} 

####################### Configure the JBoss server and setup eap service
echo "Setting configurations in $EAP_RPM_CONF_STANDALONE"
echo -e "\t-> WILDFLY_SERVER_CONFIG=standalone-full-ha.xml" | log; flag=${PIPESTATUS[0]}
echo 'WILDFLY_SERVER_CONFIG=standalone-full-ha.xml' >> $EAP_RPM_CONF_STANDALONE | log; flag=${PIPESTATUS[0]}
echo 'WILDFLY_OPTS=-Dorg.wildfly.sigterm.suspend.timeout=${gracefulShutdownTimeout}' >> $EAP_RPM_CONF_STANDALONE | log; flag=${PIPESTATUS[0]}

echo "Setting configurations in $EAP_LAUNCH_CONFIG"
echo -e '\t-> JAVA_OPTS="$JAVA_OPTS -Djboss.bind.address=0.0.0.0"' | log; flag=${PIPESTATUS[0]}
echo -e '\t-> JAVA_OPTS="$JAVA_OPTS -Djboss.bind.address.management=0.0.0.0"' | log; flag=${PIPESTATUS[0]}
echo -e '\t-> JAVA_OPTS="$JAVA_OPTS -Djboss.bind.address.private=$(hostname -I)"' | log; flag=${PIPESTATUS[0]}

echo -e 'JAVA_OPTS="$JAVA_OPTS -Djboss.bind.address=0.0.0.0"' >> $EAP_LAUNCH_CONFIG | log; flag=${PIPESTATUS[0]}
echo -e 'JAVA_OPTS="$JAVA_OPTS -Djboss.bind.address.management=0.0.0.0"' >> $EAP_LAUNCH_CONFIG | log; flag=${PIPESTATUS[0]}
echo -e 'JAVA_OPTS="$JAVA_OPTS -Djboss.bind.address.private=$(hostname -I)"' >> $EAP_LAUNCH_CONFIG | log; flag=${PIPESTATUS[0]}
echo -e 'JAVA_OPTS="$JAVA_OPTS -Djava.net.preferIPv4Stack=true"' >> $EAP_LAUNCH_CONFIG | log; flag=${PIPESTATUS[0]}

echo -e "JAVA_OPTS=\"\$JAVA_OPTS -Djboss.jgroups.azure_ping.storage_account_name=$STORAGE_ACCOUNT_NAME\"" >> $EAP_LAUNCH_CONFIG | log; flag=${PIPESTATUS[0]}
echo -e "JAVA_OPTS=\"\$JAVA_OPTS -Djboss.jgroups.azure_ping.storage_access_key=$STORAGE_ACCESS_KEY\"" >> $EAP_LAUNCH_CONFIG | log; flag=${PIPESTATUS[0]}
echo -e "JAVA_OPTS=\"\$JAVA_OPTS -Djboss.jgroups.azure_ping.container=$CONTAINER_NAME\"" >> $EAP_LAUNCH_CONFIG | log; flag=${PIPESTATUS[0]}

####################### Start the JBoss server and setup eap service

if [[ "${JDK_VERSION,,}" == "eap8-openjdk17" || "${JDK_VERSION,,}" == "eap8-openjdk11" ]]; then
    echo "Start JBoss-EAP service"                  | log; flag=${PIPESTATUS[0]}
    echo "systemctl enable eap8-standalone.service" | log; flag=${PIPESTATUS[0]}
    systemctl enable eap8-standalone.service        | log; flag=${PIPESTATUS[0]}

    ###################### Editing eap8-standalone.services
    echo "Adding - After=syslog.target network.target NetworkManager-wait-online.service" | log; flag=${PIPESTATUS[0]}
    sed -i 's/After=syslog.target network.target/After=syslog.target network.target NetworkManager-wait-online.service/' /usr/lib/systemd/system/eap8-standalone.service | log; flag=${PIPESTATUS[0]}
    echo "Adding - Wants=NetworkManager-wait-online.service \nBefore=httpd.service" | log; flag=${PIPESTATUS[0]}
    sed -i 's/Before=httpd.service/Wants=NetworkManager-wait-online.service \nBefore=httpd.service/' /usr/lib/systemd/system/eap8-standalone.service | log; flag=${PIPESTATUS[0]}
    # Calculating EAP gracefulShutdownTimeout and passing it the service.
    if  [[ "${gracefulShutdownTimeout,,}" == "-1" ]]; then
        sed -i 's/Environment="WILDFLY_OPTS="/Environment="WILDFLY_OPTS="\nTimeoutStopSec=infinity/' /usr/lib/systemd/system/eap8-standalone.service | log; flag=${PIPESTATUS[0]}
    else
        timeoutStopSec=$gracefulShutdownTimeout+20
        if  "${timeoutStopSec}">90; then
        sed -i 's/Environment="WILDFLY_OPTS="/Environment="WILDFLY_OPTS="\nTimeoutStopSec='${timeoutStopSec}'/' /usr/lib/systemd/system/eap8-standalone.service | log; flag=${PIPESTATUS[0]}
        fi
    fi
    systemd-analyze verify --recursive-errors=no /usr/lib/systemd/system/eap8-standalone.service
    echo "systemctl daemon-reload" | log; flag=${PIPESTATUS[0]}
    systemctl daemon-reload | log; flag=${PIPESTATUS[0]}

    echo "systemctl restart eap8-standalone.service"| log; flag=${PIPESTATUS[0]}
    systemctl restart eap8-standalone.service       | log; flag=${PIPESTATUS[0]}
    echo "systemctl status eap8-standalone.service" | log; flag=${PIPESTATUS[0]}
    systemctl status eap8-standalone.service        | log; flag=${PIPESTATUS[0]}

else
    echo "Start JBoss-EAP service"                  | log; flag=${PIPESTATUS[0]}
    echo "systemctl enable eap7-standalone.service" | log; flag=${PIPESTATUS[0]}
    systemctl enable eap7-standalone.service        | log; flag=${PIPESTATUS[0]}

    ###################### Editing eap7-standalone.services
    echo "Adding - After=syslog.target network.target NetworkManager-wait-online.service" | log; flag=${PIPESTATUS[0]}
    sed -i 's/After=syslog.target network.target/After=syslog.target network.target NetworkManager-wait-online.service/' /usr/lib/systemd/system/eap7-standalone.service | log; flag=${PIPESTATUS[0]}
    echo "Adding - Wants=NetworkManager-wait-online.service \nBefore=httpd.service" | log; flag=${PIPESTATUS[0]}
    sed -i 's/Before=httpd.service/Wants=NetworkManager-wait-online.service \nBefore=httpd.service/' /usr/lib/systemd/system/eap7-standalone.service | log; flag=${PIPESTATUS[0]}
    # Calculating EAP gracefulShutdownTimeout and passing it the service.
    if [[  "${gracefulShutdownTimeout,,}" == "infinity" ]]; then
        sed -i 's/Environment="WILDFLY_OPTS="/Environment="WILDFLY_OPTS="\nTimeoutStopSec=infinity/' /usr/lib/systemd/system/eap7-standalone.service | log; flag=${PIPESTATUS[0]}
    else
        timeoutStopSec=$gracefulShutdownTimeout+20
        if  "${timeoutStopSec}">90; then
        sed -i 's/Environment="WILDFLY_OPTS="/Environment="WILDFLY_OPTS="\nTimeoutStopSec='${timeoutStopSec}'/' /usr/lib/systemd/system/eap7-standalone.service | log; flag=${PIPESTATUS[0]}
        fi
    fi
    systemd-analyze verify --recursive-errors=no /usr/lib/systemd/system/eap7-standalone.service
    echo "systemctl daemon-reload" | log; flag=${PIPESTATUS[0]}
    systemctl daemon-reload | log; flag=${PIPESTATUS[0]}

    echo "systemctl restart eap7-standalone.service"| log; flag=${PIPESTATUS[0]}
    systemctl restart eap7-standalone.service       | log; flag=${PIPESTATUS[0]}
    echo "systemctl status eap7-standalone.service" | log; flag=${PIPESTATUS[0]}
    systemctl status eap7-standalone.service        | log; flag=${PIPESTATUS[0]}
fi
####################### 

####################### Open Red Hat software firewall for port 8080 and 9990:
openport 8080
openport 9990
openport 9999   # native management
openport 8443   # HTTPS
openport 8009   # AJP
openport 22     # SSH
echo "firewall-cmd --reload" | log; flag=${PIPESTATUS[0]}
firewall-cmd --reload | log; flag=${PIPESTATUS[0]}

echo "iptables-save" | log; flag=${PIPESTATUS[0]}
sudo iptables-save   | log; flag=${PIPESTATUS[0]}

/bin/date +%H:%M:%S 
echo "Configuring JBoss EAP management user" | log; flag=${PIPESTATUS[0]}
echo "$EAP_HOME/bin/add-user.sh -u JBOSS_EAP_USER -p JBOSS_EAP_PASSWORD -g 'guest,mgmtgroup'" | log; flag=${PIPESTATUS[0]}
$EAP_HOME/bin/add-user.sh -u $JBOSS_EAP_USER -p $JBOSS_EAP_PASSWORD -g 'guest,mgmtgroup'  | log; flag=${PIPESTATUS[0]}
if [ $flag != 0 ] ; then echo  "ERROR! JBoss EAP management user configuration Failed" >&2 log; exit $flag;  fi 

# Seeing a race condition timing error so sleep to delay
sleep 20

# Configure JDBC driver and data source
if [ "$enableDB" == "True" ]; then
    echo "pwd=$PWD" | log; flag=${PIPESTATUS[0]}
    echo "jdbcDataSourceName=dataSource-$dbType" | log; flag=${PIPESTATUS[0]}
    jdbcDataSourceName=dataSource-$dbType
    echo "./create-ds-${dbType}.sh $EAP_HOME $jdbcDataSourceName $jdbcDSJNDIName $dsConnectionString $databaseUser $databasePassword $enablePswlessConnection $uamiClientId" | log; flag=${PIPESTATUS[0]}
    ./create-ds-${dbType}.sh $EAP_HOME "$jdbcDataSourceName" "$jdbcDSJNDIName" "$dsConnectionString" "$databaseUser" "$databasePassword" $enablePswlessConnection "$uamiClientId"

    # Test connection for the created data source
    sudo -u jboss $EAP_HOME/bin/jboss-cli.sh --connect "/subsystem=datasources/data-source=$jdbcDataSourceName:test-connection-in-pool" | log; flag=${PIPESTATUS[0]}
    if [ $flag != 0 ]; then 
        echo "ERROR! Test data source connection failed." >&2 log
        exit $flag
    fi
fi

echo "ALL DONE!" | log; flag=${PIPESTATUS[0]}
/bin/date +%H:%M:%S | log