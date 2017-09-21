#!/bin/bash

MAPR_UID=${MAPR_UID:-5000}
MAPR_GID=${MAPR_GID:-5000}
MAPR_USER=${MAPR_USER:-mapr}
MAPR_GROUP=${MAPR_GROUP:-mapr}
MAPR_USER_PASSWORD=${MAPR_USER_PASSWORD:-mapr522301}
MAPR_SUDOERS_FILE="/etc/sudoers.d/mapr_user"


if getent group $MAPR_GID > /dev/null 2>&1 ; then
    echo "Group ID already exists"
else
	groupadd -g $MAPR_GID $MAPR_GROUP
fi

if getent passwd $MAPR_UID > /dev/null 2>&1 ; then
    echo "User ID already exists"
else
	useradd -m -u $MAPR_UID -g $MAPR_GID -G $(stat -c '%G' /etc/shadow) $MAPR_USER 
	echo "MAPR user added to container"
fi

echo $MAPR_USER_PASSWORD | passwd $MAPR_USER --stdin

cat > $MAPR_SUDOERS_FILE << EOM
$MAPR_USER	ALL=(ALL)	NOPASSWD:ALL
Defaults:$MAPR_USER		!requiretty
EOM
chmod 0440 $MAPR_SUDOERS_FILE
    
mkdir /home/$MAPR_USER/.ssh

sudo mv /tmp/authorized_keys /home/$MAPR_USER/.ssh/authorized_keys


exit 0

