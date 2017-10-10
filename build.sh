#!/bin/sh
#mapr client dynamic build script
#Log everything in /tmp/build.log
logfile=/tmp/build.log
exec > $logfile 2>&1
set -x

#Map or set defaults pulled from  for client packages
INSTALL_HBASE_CLIENT=${INSTALL_HBASE_CLIENT}
INSTALL_HIVE_CLIENT=${INSTALL_HIVE_CLIENT}
INSTALL_PIG_CLIENT=${INSTALL_PIG_CLIENT}
INSTALL_POSIX_CLIENT=${INSTALL_POSIX_CLIENT}
INSTALL_SPARK_CLIENT=${INSTALL_SPARK_CLIENT}
INSTALL_STREAMS_CLIENT=${INSTALL_STREAMS_CLIENT}
INSTALL_YARN_CLIENT=${INSTALL_YARN_CLIENT}

echo "HBASE=$INSTALL_HBASE_CLIENT"
echo "HIVE=$INSTALL_HIVE_CLIENT"
echo "PIG=$INSTALL_PIG_CLIENT"
echo "POSIX=$INSTALL_POSIX_CLIENT"
echo "SPARK=$INSTALL_SPARK_CLIENT"
echo "STREAMS=$INSTALL_STREAMS_CLIENT"
echo "YARN=$INSTALL_YARN_CLIENT"

#set environment
MAPR_PKG_GROUPS=()
PACKAGES="mapr-client"
CONTAINER_PORTS=${MAPR_PORTS:-22}
MAPR_LIB_DIR=$MAPR_HOME/lib
MAPR_VERSION_CORE=${MAPR_VERSION_CORE:-5.2.2}
MAPR_VERSION_MEP=${MAPR_VERSION_MEP:-3.0.1}
MAPR_PKG_URL=${MAPR_PKG_URL:-http://package.mapr.com/releases}
MAPR_CORE_URL=$MAPR_PKG_URL
MAPR_ECO_URL=$MAPR_PKG_URL
SPRVD_CONF=/etc/supervisor/conf.d/supervisord.conf


PKG_posix="mapr-posix-client-container"
PKG_hbase="mapr-hbase"
PKG_yarn="mapr-asynchbase"
PKG_hive="mapr-hive"
PKG_pig="mapr-pig"
PKG_drill="mapr-drill"
PKG_spark="mapr-spark"
PKG_streams="mapr-kafka mapr-librdkafka"

[ "$INSTALL_HBASE_CLIENT" = "true" ] && MAPR_PKG_GROUPS+=("hbase")
[ "$INSTALL_HIVE_CLIENT" = "true" ] && MAPR_PKG_GROUPS+=("hive")
[ "$INSTALL_PIG_CLIENT" = "true" ] && MAPR_PKG_GROUPS+=("pig")
[ "$INSTALL_POSIX_CLIENT" = "true" ] && MAPR_PKG_GROUPS+=("posix")
[ "$INSTALL_SPARK_CLIENT" = "true" ] && MAPR_PKG_GROUPS+=("spark")
[ "$INSTALL_STREAMS_CLIENT" = "true" ] && MAPR_PKG_GROUPS+=("streams")
[ "$INSTALL_YARN_CLIENT" = "true" ] && MAPR_PKG_GROUPS+=("yarn")

for p in "${MAPR_PKG_GROUPS[@]}"; do
	PACKAGES="$PACKAGES $(eval "echo \"\$PKG_$p\"")"
done

echo "Installing the following pakcages in image: $PACKAGES"

/opt/mapr/installer/docker/mapr-setup.sh -r http://package.mapr.com/releases container client $MAPR_VERSION_CORE $MAPR_VERSION_MEP $PACKAGES


exit 0



