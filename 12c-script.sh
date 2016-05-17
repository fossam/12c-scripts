#!/bin/bash -x
ORACLE_ZIPFILES=linuxamd64_12102_database_*

ORACLE_MOUNTPOINT=/u01

ORACLE_USER=oracle
ORACLE_BASE=${ORACLE_MOUNTPOINT}/app/oracle
ORACLE_HOME=${ORACLE_BASE}/product/12.1.0/dbhome_1
ORACLE_INVENTORY_LOCATION=/u01/app/oracle/oraInventory
ORACLE_ACCOUNT_LOCATION=/home/${ORACLE_USER}
ORACLE_INSTALLFILES_LOCATION=${ORACLE_ACCOUNT_LOCATION}/12.1.0.2

ORACLE_INVENTORY_GROUP=oinstall #the Oracle Inventory group
ORACLE_OSDBA_GROUP=dba          #users with in the group have SYSDBA 
ORACLE_OSOPER_GROUP=oper        #for user for starting and shutting down - SYSOPER
ORACLE_OSBACKUPDBA_GROUP=backupdba #group for users with SYSBACKUP
ORACLE_OSDGDBA_GROUP=dgdba      #group for users with SYSDG, data guard admin
ORACLE_OSKMDBA_GROUP=kmdba      #group for users with SYSKM, wallet manager magement
ORACLE_OSASM_GROUP=asmadmin     #group for users with SYSASM, asm admin
ORACLE_OSASMDBA_GROUP=asmdba    #group for users with SYSDBA for ASM, all users with OSDBA on databases that have access to files managed by ASM must be members of the OSDBA for ASM
ORACLE_OSASMOPER_GROUP=asmoper  #group for users with SYSOPER for ASM, for starting and shutting down

#grid specific stuff is not used for now, but defined for future use.
GRID_USER=grid
GRID_BASE=${ORACLE_MOUNTPOINT}/app/grid
GRID_HOME=${ORACLE_MOUNTPOINT}/app/12.1.0/grid_1 
#${GRID_BASE}/product/12.1.0/grid_1

#ORACLE_MEMORY_SIZE=2048M  #not used
DBSOFTWARE_RESPONSE_FILE=database/response/db_install.rsp
DBCA_RESPONSE_FILE=database/response/dbca.rsp
NETCA_RESPONSE_FILE=database/response/netca.rsp

#names and ids must match between cluster hosts, to future proof we're setting them
groupadd -g 54321 ${ORACLE_INVENTORY_GROUP}
groupadd -g 54322 ${ORACLE_OSDBA_GROUP}
groupadd -g 54323 ${ORACLE_OSOPER_GROUP}
groupadd -g 54324 ${ORACLE_OSBACKUPDBA_GROUP}
groupadd -g 54326 ${ORACLE_OSDGDBA_GROUP}
groupadd -g 54327 ${ORACLE_OSKMDBA_GROUP}
groupadd -g 54328 ${ORACLE_OSASM_GROUP}
groupadd -g 54325 ${ORACLE_OSASMDBA_GROUP}
groupadd -g 54329 ${ORACLE_OSASMOPER_GROUP}

#user is created to own only Oracle Grid Infrastructure software installations
useradd -u 54322 -g ${ORACLE_INVENTORY_GROUP} -G ${ORACLE_OSASM_GROUP},${ORACLE_OSASMDBA_GROUP} ${GRID_USER}

#user is created to own only Oracle database software installations
useradd -u 54321 -d ${ORACLE_ACCOUNT_LOCATION} -g ${ORACLE_INVENTORY_GROUP} -G ${ORACLE_OSDBA_GROUP},${ORACLE_OSBACKUPDBA_GROUP},${ORACLE_OSDGDBA_GROUP},${ORACLE_OSKMDBA_GROUP},${ORACLE_OSASMDBA_GROUP},${ORACLE_OSASMOPER_GROUP},${ORACLE_OSOPER_GROUP} ${ORACLE_USER}

mkdir -p ${GRID_HOME}
mkdir -p ${GRID_BASE}
mkdir -p ${ORACLE_BASE}
chown -R ${GRID_USER}:${ORACLE_INVENTORY_GROUP} ${ORACLE_MOUNTPOINT}
chmod -R 775 ${ORACLE_MOUNTPOINT}/
chown ${ORACLE_USER}:${ORACLE_INVENTORY_GROUP} ${ORACLE_BASE}

#shell environment setup
#echo "umask 022" >> /home/${GRID_USER}/.bash_profile
cat <<EOL >> ${ORACLE_ACCOUNT_LOCATION}/.bash_profile
umask 022
export TMP=/tmp
export TMPDIR=$TMP

export ORACLE_HOSTNAME=$(hostname -s)
export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_HOME=${ORACLE_HOME}

export PATH=/usr/sbin:$PATH
export PATH=$ORACLE_HOME/bin:$PATH

export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib
export CLASSPATH=$ORACLE_HOME/jlib:$ORACLE_HOME/rdbms/jlib
EOL

#pre setup - this also needs to happen at every boot from /etc/rc.d/rc.local to adjust to different addresses VM might get across boots
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "$(ip addr ls | grep global |grep -o "[[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*/" | sed s'/.$//') $(hostname -s)" >> /etc/hosts

cat <<'EOL' >> /etc/rc.d/rc.local
#sleep for a bit in hopes of not being run before an address is assigned
sleep 20
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "$(ip addr ls | grep global |grep -o "[[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*/" | sed s'/.$//') $(hostname -s)" >> /etc/hosts
EOL
chmod +x /etc/rc.d/rc.local

#put /tmp on disk
systemctl mask tmp.mount

# kernel parameters for 12c installation
cat <<EOL >> /etc/sysctl.conf
fs.file-max = 6815744
kernel.sem = 250 32000 100 128
kernel.shmmni = 4096
kernel.shmall = 1073741824
kernel.shmmax = 4398046511104
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
fs.aio-max-nr = 1048576
net.ipv4.ip_local_port_range = 9000 65500
EOL

# shell limits for users oracle 12c
cat <<EOL >> /etc/security/limits.conf
${ORACLE_USER}  soft   nofile   4096
${ORACLE_USER}  hard   nofile   65536
${ORACLE_USER}  soft   nproc    2047
${ORACLE_USER}  hard   nproc    16384
${ORACLE_USER}  soft   stack    10240
${ORACLE_USER}  hard   stack    32768
EOL

#install location file
cat <<EOL > /etc/oraInst.loc
inventory_loc=${ORACLE_INVENTORY_LOCATION}
inst_group=${ORACLE_INVENTORY_GROUP}
EOL

chown ${ORACLE_USER}:${ORACLE_INVENTORY_GROUP} /etc/oraInst.loc
chmod 644 /etc/oraInst.loc

#packages required for 12c installation
yum -y install unzip binutils compat-libcap1 compat-libstdc++ gcc gcc-c++ glibc glibc-devel ksh libaio libaio-devel libgcc libstdc++ libstdc++-devel make sysstat net-tools glibc.i686 glibc-devel.i686 libaio.i686 libaio-devel.i686 libgcc.i686 libstdc++.i686 libstdc++-devel.i686
## libXi.i686 libXi.x86_64 libXtst.i686 libXtst.x86_64

mv /tmp/${ORACLE_ZIPFILES} ${ORACLE_ACCOUNT_LOCATION}/
mkdir ${ORACLE_INSTALLFILES_LOCATION}
unzip -d ${ORACLE_INSTALLFILES_LOCATION} "${ORACLE_ACCOUNT_LOCATION}/${ORACLE_ZIPFILES}"  #quotes needed
###cp ${ORACLE_INSTALLFILES_LOCATION}/${DBSOFTWARE_RESPONSE_FILE} ${ORACLE_ACCOUNT_LOCATION}
chown -R ${ORACLE_USER}:${ORACLE_INVENTORY_GROUP} ${ORACLE_ACCOUNT_LOCATION}/${ORACLE_ZIPFILES} ${ORACLE_INSTALLFILES_LOCATION} ${ORACLE_INSTALLFILES_LOCATION}/${DBSOFTWARE_RESPONSE_FILE}

#db-install response file
cat <<EOL >> ${ORACLE_INSTALLFILES_LOCATION}/${DBSOFTWARE_RESPONSE_FILE} 
oracle.install.option=INSTALL_DB_SWONLY
ORACLE_HOSTNAME=$(hostname)
UNIX_GROUP_NAME=${ORACLE_INVENTORY_GROUP}
#INVENTORY_LOCATION=/u01/12.1.0.2/database/stage/products.xml
INVENTORY_LOCATION=${ORACLE_INVENTORY_LOCATION}
SELECTED_LANGUAGES=en
ORACLE_HOME=${ORACLE_HOME}
ORACLE_BASE=${ORACLE_BASE}
oracle.install.db.InstallEdition=EE
oracle.install.db.DBA_GROUP=${ORACLE_OSDBA_GROUP}
oracle.install.db.OPER_GROUP=${ORACLE_OSOPER_GROUP}
oracle.install.db.BACKUPDBA_GROUP=${ORACLE_OSDBA_GROUP}
oracle.install.db.DGDBA_GROUP=${ORACLE_OSDBA_GROUP}
oracle.install.db.KMDBA_GROUP=${ORACLE_OSDBA_GROUP}
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
DECLINE_SECURITY_UPDATES=true
EOL

#netca response file
#[GENERAL] 
#RESPONSEFILE_VERSION="12.1" 
#CREATE_TYPE="CUSTOM" 
#[oracle.net.ca] 
#INSTALLED_COMPONENTS={"server","net8","javavm"} 
#INSTALL_TYPE=""typical"" 
#LISTENER_NUMBER=1 
#LISTENER_NAMES={"LISTENER"} 
#LISTENER_PROTOCOLS={"TCP;1521","TCPS;2484"} 
#LISTENER_START=""LISTENER"" 
#NAMING_METHODS={"TNSNAMES","ONAMES","HOSTNAME"}


#start install as the user 'oracle'
sudo -u oracle -s ${ORACLE_INSTALLFILES_LOCATION}/database/runInstaller -force -waitforcompletion -showProgress -silent -responseFile ${ORACLE_INSTALLFILES_LOCATION}/${DBSOFTWARE_RESPONSE_FILE} 
${ORACLE_HOME}/root.sh

#netca run
#sudo -u oracle -s ${ORACLE_HOME}/bin/netca -silent -waitforcompletion -showProgress -responseFile ${ORACLE_INSTALLFILES_LOCATION}/${NETCA_RESPONSE_FILE}
