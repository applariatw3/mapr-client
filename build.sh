#!/bin/sh
#mapr server entrypoint script

export JAVA_HOME=/usr/lib/jvm/java-openjdk
export MAPR_HOME=/opt/mapr
export MAPR_ENVIRONMENT=docker

#set environment
MAPR_PKG_GROUPS=( $MAPR_BUILD )
PACKAGES=
CONTAINER_PORTS=${MAPR_PORTS:-22}
MAPR_MONITORING=${MAPR_MONITORING:-true}
MAPR_LOGGING=${MAPR_LOGGING:-true}
MAPR_INSTALLER_DIR=${MAPR_INSTALLER_DIR:-$MAPR_HOME/installer}
MAPR_CONTAINER_DIR=$MAPR_HOME/installer/docker
MAPR_LIB_DIR=${MAPR_LIB_DIR:-$MAPR_HOME/lib}
MAPR_VERSION_CORE=${MAPR_VERSION_CORE:-5.2.2}
MAPR_VERSION_MEP=${MAPR_VERSION_MEP:-3.0.1}
MAPR_PKG_URL=${MAPR_PKG_URL:-http://package.mapr.com/releases}
MAPR_CORE_URL=$MAPR_PKG_URL
MAPR_ECO_URL=$MAPR_PKG_URL
SPRVD_CONF=/etc/supervisor/conf.d/supervisord.conf

PKG_fs="mapr-fileserver"
PORTS_fs="5660 1111"
PKG_nfs="mapr-nfs"
PORTS_nfs="2049 111"
PKG_yarn="mapr-nodemanager"
PORTS_yarn="5660 8041 8042 31010 8047 8080 1111"
PKG_rm="mapr-resourcemanager"
PORTS_rm="8088 8032 19888 1111"
PKG_mrv1="mapr-tasktracker"
PORTS_mrv1="5660 50060 1111"
PKG_jt="mapr-jobtracker"
PORTS_jt="50030"
PKG_zk="mapr-zookeeper"
PORTS_zk="5181 3888 2888"
PKG_mcs="mapr-webserver"
PORTS_mcs="8443"
PKG_cldb="mapr-cldb mapr-fileserver"
PORTS_cldb="5660 7221 7222 1111"
PKG_mon="mapr-collectd"
PKG_log="mapr-fluentd"
PKG_hs="mapr-historyserver"
PORTS_hs="19888"
PKG_shs="mapr-sparkhistoryserver"
PORTS_shs="18080"
PKG_client="mapr-hbase mapr-asynchbase mapr-spark mapr-hive mapr-kafka mapr-librdkafka"
PORTS_client=""
PKG_es="mapr-elasticsearch"
PORTS_es="9200 9300"
PKG_ot="mapr-opentsdb"
PORTS_ot="4242"
PKG_kibana="mapr-kibana"
PORTS_kibana="5601"
PKG_graphana="mapr-graphana"
PORTS_graphana="3000"
PKG_hive="mapr-hivemetastore mapr-hiveserver2 mapr-hivewebhcat"
PORTS_hive="9083 10000 50111"
PKG_drill="mapr-drill"
PORTS_drill="8047 31010"
PKG_hbrest="mapr-hbase-rest"
PORTS_hbrest="8080"

START_ZK=0
START_WARDEN=1

[ "$MAPR_MONITORING" = true ] && MAPR_PKG_GROUPS+=(mon)
[ "$MAPR_LOGGING" = true ] && MAPR_PKG_GROUPS+=(log)

add_package() {
    PACKAGES="$PACKAGES $(eval "echo \"\$PKG_$1\"")"
        
    CONTAINER_PORTS="$CONTAINER_PORTS $(eval "echo \"\$PORTS_$1\"")"
}

for p in "${MAPR_PKG_GROUPS[@]}"; do
	add_package $p
	
	[ "$p" = zk ] && START_ZK=1
done

echo "Installing the following pakcages in image: $PACKAGES"

/opt/mapr/installer/docker/mapr-setup.sh -r http://package.mapr.com/releases container core $PACKAGES

MAPR_PORTS=$CONTAINER_PORTS

#Add entries to supervisord.conf
if [ $START_ZK -eq 1 ]; then
	cat >> $SPRVD_CONF << EOC

[program:mapr-zookeeper]
command=/etc/init.d/mapr-zookeeper start
autorestart=false
EOC

echo "Added zookeeper to start list"
fi

if [ $START_WARDEN -eq 1 ]; then
	cat >> $SPRVD_CONF << EOC

[program:mapr-warden]
command=/etc/init.d/mapr-warden start
autorestart=false
EOC

echo "Added warden to start list"
fi


exit 0



