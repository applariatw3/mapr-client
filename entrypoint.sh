#!/bin/sh
#mapr client entrypoint script

echo "Starting MAPR Client PACC as ${POD_NAME} from entrypoint.sh"

set -e
#set environment from inputs
MAPR_CLUSTER=${MAPR_CLUSTER:?Missing required MAPR cluster name}
MAPR_CLDB_HOSTS=${MAPR_CLDB_HOSTS:?Missing required MAPR CLDB hosts}

set +e

MAPR_MCS=${MAPR_MCS:-mapr-cldb}
MAPR_MCS_PORT=${MAPR_MCS_PORT:-8443}
MAPR_SECURITY=${MAPR_SECURITY:-disabled}
MAPR_MEMORY=${NODE_MEMORY:-0}
MAPR_ADMIN_UID=${MAPR_ADMIN_UID:-5000}
MAPR_ADMIN_GID=${MAPR_ADMIN_GID:-5000}
MAPR_ADMIN=${MAPR_ADMIN:-mapr}
MAPR_ADMIN_PASSWORD=${MAPR_ADMIN_PASSWORD:-mapr522301}
MAPR_ADMIN_GROUP=${MAPR_ADMIN_GROUP:-mapr}
MAPR_CLIENT_UID=${MAPR_CLIENT_UID:-1000}
MAPR_CLIENT_GID=${MAPR_CLIENT_GID:-100}
MAPR_CLIENT_USER=${MAPR_CLIENT_USER:-demo}
MAPR_CLIENT_PASSWORD=${MAPR_CLIENT_PASSWORD:-demo123}
MAPR_CLIENT_GROUP=${MAPR_CLIENT_GROUP:-users}


#export path
export PATH=$JAVA_HOME/bin:$MAPR_HOME/bin:$PATH
export CLASSPATH=$CLASSPATH
#export MAPR_CLASSPATH=$MAPR_CLASSPATH

#internal environment
MAPR_CLUSTER_CONF="$MAPR_HOME/conf/mapr-clusters.conf"
MAPR_CONFIGURE_SCRIPT="$MAPR_HOME/server/configure.sh"


#Interrupt entrypoint if command overridden

#Reset the MAPR hostid to be unique for each container, set hostname to running container hostname
#hostname -f | grep $POD_NAME | grep -q -v grep && echo $(hostname -f) > $MAPR_HOME/hostname

#Configure default environment script
echo "#!/bin/bash" > $MAPR_ENV_FILE
echo "JAVA_HOME=\"$JAVA_HOME\"" >> $MAPR_ENV_FILE
echo "MAPR_CLUSTER=\"$MAPR_CLUSTER\"" >> $MAPR_ENV_FILE
echo "MAPR_HOME=\"$MAPR_HOME\"" >> $MAPR_ENV_FILE
[ -f "$MAPR_HOME/bin/mapr" ] && echo "MAPR_CLASSPATH=\"\$($MAPR_HOME/bin/mapr classpath)\"" >> $MAPR_ENV_FILE
[ -n "$MAPR_MOUNT_PATH" ] && echo "MAPR_MOUNT_PATH=\"$MAPR_MOUNT_PATH\"" >> $MAPR_ENV_FILE
if [ -n "$MAPR_TICKETFILE_LOCATION" ]; then
	local ticket="MAPR_TICKETFILE_LOCATION=$MAPR_TICKETFILE_LOCATION"

	echo "$ticket" >> /etc/environment
	echo "$ticket" >> $MAPR_ENV_FILE
	sed -i -e "s|MAPR_TICKETFILE_LOCATION=.*|MAPR_TICKETFILE_LOCATION=$MAPR_TICKETFILE_LOCATION|" \
		"$MAPR_HOME/initscripts/$MAPR_PACKAGE_POSIX"
fi
echo "PATH=\"\$JAVA_HOME:\$PATH:\$MAPR_HOME/bin\"" >> $MAPR_ENV_FILE

#Create the mapr admin user
#if id $MAPR_ADMIN >/dev/null 2>&1; then
#	echo "Mapr admin user already exists"
#else
#	$MAPR_CONTAINER_DIR/mapr-create-user.sh $MAPR_ADMIN $MAPR_ADMIN_UID $MAPR_ADMIN_GROUP $MAPR_ADMIN_GID $MAPR_ADMIN_PASSWORD
#fi

#Create the mapr client user
if id $MAPR_CLIENT_USER >/dev/null 2>&1; then
	echo "Mapr client user already exists"
else
	$MAPR_CONTAINER_DIR/mapr-create-user.sh $MAPR_CLIENT_USER $MAPR_CLIENT_UID $MAPR_CLIENT_GROUP $MAPR_CLIENT_GID $MAPR_CLIENT_PASSWORD
fi

#configure sshd
if [ ! -d /var/run/sshd ]; then
	mkdir /var/run/sshd
	echo "root:$MAPR_ADMIN_PASSWORD" | chpasswd

	rm -f /run/nologin
	if [ -f /etc/ssh/sshd_config ]; then
		sed -ri 's/^PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
		sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config
		sed -ri 's/#UsePAM no/UsePAM no/g' /etc/ssh/sshd_config
		sed -i 's/^ChallengeResponseAuthentication no$/ChallengeResponseAuthentication yes/g' \
			/etc/ssh/sshd_config || echo "Could not enable ChallengeResponseAuthentication"
		echo "ChallengeResponseAuthentication enabled"
	fi

	# SSH login fix. Otherwise user is kicked off after login
	sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
fi

#set memory for container
if [ "$MAPR_ORCHESTRATOR" = "k8s" -a $MAPR_MEMORY -ne 0 ]; then
	mem_file="$MAPR_HOME/conf/container_meminfo"
	mem_char=$(echo "$MAPR_MEMORY" | grep -o -E '[kmgKMG]')
	mem_number=$(echo "$MAPR_MEMORY" | grep -o -E '[0-9]+')

	echo "Seting MapR container memory limits..."
	[ ${#mem_number} -eq 0 ] && echo "Empty memory allocation, using default 2G" && mem_number=2
	[ ${#mem_char} -gt 1 ] && echo "Invalid memory allocation: using default 2G" && mem_char=G
	[ $mem_number == "0" ] && echo "Can't use zero, using default 2gG && mem_number=2" && mem_number=2

	case "$mem_char" in
		g|G) mem_total=$(($mem_number * 1024 * 1024)) ;;
		m|M) mem_total=$(($mem_number * 1024)) ;;
		k|K) mem_total=$(($mem_number)) ;;
	esac
	cp -f -v /proc/meminfo $mem_file
	chown $MAPR_CLIENT_USER:$MAPR_GROUP $mem_file
	chmod 644 $mem_file
	sed -i "s!/proc/meminfo!${mem_file}!" "$MAPR_HOME/server/initscripts-common.sh" || \
		echo "Could not edit initscripts-common.sh"
	sed -i "/^MemTotal/ s/^.*$/MemTotal:     $mem_total kB/" "$mem_file" || \
		echo "Could not edit meminfo MemTotal"
	sed -i "/^MemFree/ s/^.*$/MemFree:     $mem_total kB/" "$mem_file" || \
		echo "Could not edit meminfo MemFree"
	sed -i "/^MemAvailable/ s/^.*$/MemAvailable:     $mem_total kB/" "$mem_file" || \
		echo "Could not edit meminfo MemAvailable"
fi
	

#Set variables MAPR_HOME, JAVA_HOME, [ MAPR_SUBNETS (if set)] in conf/env.sh
env_file="$MAPR_HOME/conf/env.sh"
sed -i "s:^#export JAVA_HOME.*:export JAVA_HOME=${JAVA_HOME}:" "$env_file" || \
	echo "Could not edit JAVA_HOME in $env_file"
sed -i "s:^#export MAPR_HOME.*:export MAPR_HOME=${MAPR_HOME}:" "$env_file" || \
	echo "Could not edit MAPR_HOME in $env_file"
if [ -n "$MAPR_SUBNETS" ]; then
	sed -i "s:^#export MAPR_SUBNETS.*:export MAPR_SUBNETS=${MAPR_SUBNETS}:" "$env_file" || \
		echo "Could not edit MAPR_SUBNETS in $env_file"
fi

#Update /etc/hosts file
find_host_ip(){
	cnt=0
	until getent hosts $1; do
		 let cnt++
		 echo "Waiting for MAPR host to resolve, attempt $cnt"
		 [ $cnt -gt 4 ] && check_failed=1 && return
		 sleep 3
	done
}

check_hosts(){
	IFS=',' read -ra RMH <<< "$1"
	node=0
	FQLIST=()
	for i in "${RMH[@]}"; do
        host=$(echo $i | cut -d ':' -f 1)
        
        #fqhost="$host.$NAMESPACE.svc.cluster.local"
        fqhost=$host
        if cat /etc/hosts |grep $fqhost; then
                echo "Found /etc/hosts entry for $fqhost"
        else
                echo "Looking up IP for $fqhost"
                check_failed=0
                find_host_ip $fqhost
                [ $check_failed -eq 0 ] && echo "$(getent hosts $fqhost | awk '{ print $1 }')      $(getent hosts $fqhost | awk '{ print $2 }')      $(echo $fqhost |cut -d '.' -f 1)" >> /etc/hosts
        fi
        let node++
	done
}

#[ -n ${MAPR_CLDB_HOSTS} ] && check_hosts ${MAPR_CLDB_HOSTS}
#[ -n ${MAPR_ZK_HOSTS} ] && check_hosts ${MAPR_ZK_HOSTS}
#[ -n ${MAPR_RM_HOSTS} ] && check_hosts ${MAPR_RM_HOSTS}
#[ -n ${MAPR_HS_HOST} ] && check_hosts ${MAPR_HS_HOST}
#[ -n ${MYSQL_HOST} ] && check_hosts ${MYSQL_HOST}
#[ -n ${MAPR_ES_HOSTS} ] && check_hosts ${MAPR_ES_HOSTS}
#[ -n ${MAPR_OT_HOSTS} ] && check_hosts ${MAPR_OT_HOSTS}
#[ -n ${MAPR_FS_HOSTS} ] && check_hosts ${MAPR_FS_HOSTS}
#[ -n ${MAPR_YARN_HOSTS} ] && check_hosts ${MAPR_YARN_HOSTS}

#echo "MAPR Cluster containers added to /etc/hosts"

#Confirm cluster services are ready
cycles=0
check_cldb=1
until $(curl --output /dev/null -Iskf https://${MAPR_MCS}:${MAPR_MCS_PORT}); do
	echo "Waiting for MCS to start..."
	if [ $cycles -le 10 ]; then
		sleep 60
	else
		echo "Cluster not responding after 10 minutes...continuing"
		check_cldb=0
		break
	fi
	let cycles+=1
done

find_cldb="curl -sSk -u mapr:$MAPR_ADMIN_PASSWORD https://${MAPR_MCS}:${MAPR_MCS_PORT}/rest/node/cldbmaster"
if [ $check_cldb -eq 1 ]; then
	until [ "$($find_cldb | jq -r '.status')" = "OK" ]; do
		echo "Waiting for cldb host validation..."
	done
	
	echo "Ready to configure client for $MAPR_CLUSTER with $MAPR_CLDB_HOSTS"
fi

#configure mapr services
if [ -f "$MAPR_CLUSTER_CONF" ]; then
	args=-R
	args="$args -v"
	echo "Re-configuring MapR client ($args)..."
	$MAPR_CONFIGURE_SCRIPT $args
else
	. $MAPR_HOME/conf/env.sh
	args="$args -c -on-prompt-cont y -N $MAPR_CLUSTER -C $MAPR_CLDB_HOSTS"
	[ -n "$MAPR_TICKETFILE_LOCATION" ] && args="$args -secure"
	args="$args -v"
	echo "Configuring MapR client ($args)..."
	$MAPR_CONFIGURE_SCRIPT $args
fi

#Before starting the services, make sure some file permissions are set correctly
chown -R $MAPR_CLIENT_USER:$MAPR_CLIENT_GROUP "$MAPR_HOME"
chown -fR root:root "$MAPR_HOME/conf/proxy"

if [ -n "$MAPR_MOUNT_PATH" -a -f $MAPR_HOME"/conf/fuse.conf" ]; then
	sed -i "s|^fuse.mount.point.*$|fuse.mount.point=$MAPR_MOUNT_PATH|g" \
		$MAPR_FUSE_FILE || echo "Could not set FUSE mount path"
	mkdir -p -m 755 "$MAPR_MOUNT_PATH"
	service mapr-posix-client-container start
fi

if [ $# -eq 0 ]; then
	exec /usr/sbin/sshd -D
elif [ "$1" = "/usr/sbin/sshd" ]; then
	exec "$@"
else
	echo "Starting client container with command: $@"
	service sshd start
	exec "sudo -E -H -n -u $MAPR_CLIENT_USER -g $MAPR_CLIENT_GROUP $@"
fi