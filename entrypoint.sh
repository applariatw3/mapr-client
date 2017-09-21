#!/bin/sh
#mapr server entrypoint script

echo "Starting container from entrypoint.sh"

#export variables
export JAVA_HOME=/usr/lib/jvm/java-openjdk
export MAPR_HOME=/opt/mapr
export MAPR_CLUSTER=${MAPR_CLUSTER:-my.cluster.com}
export MAPR_CLDB_HOSTS=${MAPR_CLDB_HOSTS:$HOST}
export MAPR_ZK_HOSTS=${MAPR_ZK_HOSTS:$HOST}
export MAPR_RM_HOSTS=${MAPR_RM_HOSTS:$HOST}
export MAPR_YARN_HOSTS=$MAPR_YARN_HOSTS
export MAPR_MRV1_HOSTS=$MAPR_MRV1_HOSTS
export MAPR_CLIENT_HOSTS=$MAPR_CLIENT_HOSTS
export MAPR_HS_HOST=$MAPR_HS_HOST
export MAPR_OT_HOSTS=$MAPR_OT_HOSTS
export MAPR_ES_HOSTS=$MAPR_ES_HOSTS
export MAPR_ENVIRONMENT=docker
export MAPR_ORCHESTRATOR=k8s
export PATH=$JAVA_HOME/bin:$MAPR_HOME/bin:$PATH
export CLASSPATH=$CLASSPATH

#set environment
MAPR_DISKS=${MAPR_DISKS:-/dev/sdb}
MAPR_LICENSE_MODULES=DATABASE,HADOOP,STREAMS
MAPR_SECURITY=${MAPR_SECURITY:-disabled}
MAPR_MEMORY=${MAPR_MEMORY:-8G}
MAPR_SUBNETS=$MAPR_SUBNETS
MAPR_ULIMIT_U=64000
MAPR_ULIMIT_N=64000
MAPR_SYSCTL_SOMAXCONN=20000
MAPR_UMASK=022


MAPR_ENV_FILE=/etc/profile.d/mapr.sh
MAPR_UID=${MAPR_UID:-5000}
MAPR_GID=${MAPR_GID:-5000}
MAPR_USER=${MAPR_USER:-mapr}
MAPR_USER_PASSWORD=${MAPR_USER_PASSWORD:-mapr522301}
MAPR_GROUP=${MAPR_GROUP:-mapr}
MAPR_CONTAINER_DIR=$MAPR_HOME/installer/docker
MAPR_LIB_DIR=${MAPR_LIB_DIR:-$MAPR_HOME/lib}
MAPR_VERSION_CORE=${MAPR_VERSION_CORE:-5.2.2}
MAPR_VERSION_MEP=${MAPR_VERSION_MEP:-3.0.1}

MAPR_CLUSTER_CONF="$MAPR_HOME/conf/mapr-clusters.conf"
MAPR_CONFIGURE_SCRIPT="$MAPR_HOME/server/configure.sh"
MAPR_RUN_DISKSETUP=0
USE_FAKE_DISK=${USE_FAKE_DISK:-0}
ADD_SWAP=${ADD_SWAP:-1}
MAPR_DISKSETUP="$MAPR_HOME/server/disksetup"
FORCE_FORMAT=1
STRIPE_WIDTH=3

#interrupt entrypoint if command overridden
if [[ "$1" != "/usr/bin/supervisord" ]]; then
	echo "Found command override, running command"
	echo "$@"
	exec "$@"
fi

#create the admin user
if id $MAPR_USER >/dev/null 2>&1; then
	echo "Mapr user already exists"
else
	$MAPR_CONTAINER_DIR/mapr-create-user.sh

	#set user environment
	echo ". $MAPR_ENV_FILE" >> /home/$MAPR_USER/.bashrc

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
fi

#configure sshd
if [ ! -d /var/run/sshd ]; then
	mkdir /var/run/sshd
	echo "root:$MAPR_USER_PASSWORD" | chpasswd

	rm -f /run/nologin
	if [ -f /etc/ssh/sshd_config ]; then
		sed -ri 's/^PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
		sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config
		sed -i 's/^ChallengeResponseAuthentication no$/ChallengeResponseAuthentication yes/g' \
			/etc/ssh/sshd_config || echo "Could not enable ChallengeResponseAuthentication"
		echo "ChallengeResponseAuthentication enabled"
	fi

	# SSH login fix. Otherwise user is kicked off after login
	sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
fi

#set memory for container
if [ "$MAPR_ORCHESTRATOR" = "k8s" ]; then
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
	chown $MAPR_USER:$MAPR_GROUP $mem_file
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
	
#configure OS properties
# max processes
ulimit -u ${MAPR_ULIMIT_U:-64000}
# max file descriptors
ulimit -n ${MAPR_ULIMIT_N:-64000}
# max socket connections
sysctl -q -w net.core.somaxconn=${MAPR_SYSCTL_SOMAXCONN:-20000}
# umask 022 instead of non-root 002
umask ${MAPR_UMASK:-022}


#set variables MAPR_HOME, JAVA_HOME and MAPR_SUBNETS (if set) in conf/env.sh
env_file="$MAPR_HOME/conf/env.sh"
sed -i "s:^#export JAVA_HOME.*:export JAVA_HOME=${JAVA_HOME}:" "$env_file" || \
	echo "Could not edit JAVA_HOME in $env_file"
sed -i "s:^#export MAPR_HOME.*:export MAPR_HOME=${MAPR_HOME}:" "$env_file" || \
	echo "Could not edit MAPR_HOME in $env_file"
if [ -n "$MAPR_SUBNETS" ]; then
	sed -i "s:^#export MAPR_SUBNETS.*:export MAPR_SUBNETS=${MAPR_SUBNETS}:" "$env_file" || \
		echo "Could not edit MAPR_SUBNETS in $env_file"
fi


#configure mapr services
if [ -f "$MAPR_CLUSTER_CONF" ]; then
	args=-R
	args="$args -v"
	echo "Re-configuring MapR services ($args)..."
	$MAPR_CONFIGURE_SCRIPT $args
else
	. $MAPR_HOME/conf/env.sh
	if [ -n "$MAPR_CLDB_HOSTS" ]; then
		args="$args -f -no-autostart -on-prompt-cont y -N $MAPR_CLUSTER -C $MAPR_CLDB_HOSTS -Z $MAPR_ZK_HOSTS -u $MAPR_USER -g $MAPR_GROUP"
		if [ "$MAPR_SECURITY" = "master" ]; then
			args="$args -secure -genkeys"
		elif [ "$MAPR_SECURITY" = "enabled" ]; then
			args="$args -secure"
		else
			args="$args -unsecure"
		fi
		[ -n "${LICENSE_MODULES##*DATABASE*}" -a -n "${LICENSE_MODULES##*STREAMS*}" ] && args="$args -noDB"
	else
		args="-R $args"
	fi
	[ -n "$MAPR_RM_HOSTS" ] && args="$args -RM $MAPR_RM_HOSTS"
	[ -n "$MAPR_HS_HOST" ] && args="$args -HS $MAPR_HS_HOST"
	[ -n "$MAPR_OT_HOSTS" ] && args="$args -OT $MAPR_OT_HOSTS"
	[ -n "$MAPR_ES_HOSTS" ] && args="$args -ES $MAPR_ES_HOSTS"
	args="$args -v"
	echo "Configuring MapR services ($args)..."
	$MAPR_CONFIGURE_SCRIPT $args
fi

if rpm -qa |grep mapr-fileserver >/dev/null 2>&1; then
        MAPR_RUN_DISKSETUP=1
else
        MAPR_RUN_DISKSETUP=0
fi

#Update /etc/hosts file
if [ -n ${MAPR_CLDB_HOSTS} ]; then
	IFS=',' read -ra CLDBH <<< "$MAPR_CLDB_HOSTS"
	for i in "${CLDBH[@]}"; do
    	host=$(echo $i | cut -d ':' -f 1)
    	if [[ $host != $(cat ${MAPR_HOME}/hostname) ]]; then
    	 	echo "$(dig +short $host)      $host      $(echo $host |cut -d '.' -f 1)" >> /etc/hosts
    	fi
	done
fi

if [ -n ${MAPR_ZK_HOSTS} ]; then
	IFS=',' read -ra ZKH <<< "$MAPR_ZK_HOSTS"
	for i in "${ZKH[@]}"; do
    	host=$(echo $i | cut -d ':' -f 1)
    	if [[ $host != $(cat ${MAPR_HOME}/hostname) ]]; then
    	 	echo "$(dig +short $host)      $host      $(echo $host |cut -d '.' -f 1)" >> /etc/hosts
    	fi
	done
fi

if [ -n ${MAPR_RM_HOSTS} ]; then
	IFS=',' read -ra RMH <<< "$MAPR_RM_HOSTS"
	for i in "${RMH[@]}"; do
    	host=$(echo $i | cut -d ':' -f 1)
    	if [[ $host != $(cat ${MAPR_HOME}/hostname) ]]; then
    	 	echo "$(dig +short $host)      $host      $(echo $host |cut -d '.' -f 1)" >> /etc/hosts
    	fi
	done
fi

if [ -n ${MAPR_YARN_HOSTS} ]; then
	IFS=',' read -ra YARNH <<< "$MAPR_YARN_HOSTS"
	for i in "${YARNH[@]}"; do
    	host=$(echo $i | cut -d ':' -f 1)
    	if [[ $host != $(cat ${MAPR_HOME}/hostname) ]]; then
    	 	echo "$(dig +short $host)      $host      $(echo $host |cut -d '.' -f 1)" >> /etc/hosts
    	fi
	done
fi

echo "MAPR Cluster containers added to /etc/hosts"

#configure the disks
if [ "$MAPR_RUN_DISKSETUP" -eq 1 ]; then
    if [ "$USE_FAKE_DISK" -eq 1 ]; then
		echo "Setting up psuedo disk for mapr..."
		[ -d /data/mapr ] || mkdir -p /data/mapr
		dd if=/dev/zero of=/data/mapr/storagefile bs=1G count=20
		echo "/data/mapr/storagefile" > /tmp/disks.txt
	else
		echo "Setting up $MAPR_DISKS for mapr..."
		echo "$MAPR_DISKS" > /tmp/disks.txt
	fi
	
	sed -i -e 's/mapr/#mapr/g' /etc/security/limits.conf
    sed -i -e 's/AddUdevRules(list(gdevices));/#AddUdevRules(list(gdevices));/g' $MAPR_HOME/server/disksetup
    
    [ $FORCE_FORMAT -eq 1 ] && ARGS="$ARGS -F"
    [ $STRIPE_WIDTH -eq 0 ] && ARGS="$ARGS -M" || ARGS="$ARGS -W $STRIPE_WIDTH"
    $MAPR_DISKSETUP $ARGS /tmp/disks.txt
    if [ $? -eq 0 ]; then
        echo "Local disks formatted for MapR-FS"
    else
        rc=$?
        rm -f /tmp/disks.txt $MAPR_HOME/conf/disktab
        echo "$MAPR_DISKSETUP failed with error code $rc"
    fi
fi

#Before starting the services, make sure some file permissions are set correctly
chown root:$MAPR_GROUP $MAPR_HOME/server/maprexecute
chmod u+s $MAPR_HOME/server/maprexecute

sleep 30
echo "$@"
#exec "$@"
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf