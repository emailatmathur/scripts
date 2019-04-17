#!/bin/bash
# set -vx

# File: cbbackup.sh for couchbase database backup
# Created: Rajesh Kumar
# This scripts takes the full backup on every Saturday and incremental backup for rest of the days.
# Keeps last three backups and cleaned up older than that, you can change the keep value for longer retention.
# Couchbase username and passwords can be encrypted using openssl

LOG_DATE=`date +%Y%m%d%H%M`
DAY_OF_WEEK=`date +%a`
CB_HOME=/opt/couchbase
PATH=$PATH:$CB_HOME/bin; export PATH
CBBACKUP=$CB_HOME/bin/cbbackupmgr
BACKUP_PATH=/backup/couchbase
CLUSTER_NODE_URL=http://192.168.56.20:8091
RSTATUS=1
HNAME=`hostname`
#CB_REPO=`date +%Y%m%d`
#CB_REPO=CB_BACKUP_$(date +%d_%b_%y_%H_%M_%s)
CB_REPO=CB_BACKUP_$(date +%d_%b_%y)
cd $BACKUP_PATH
CB_THREADS=10

RTUSER=`id |cut -d"(" -f2 | cut -d ")" -f1`
CBUSER=couchbase
DBU=Administrator
DBP=******

FBU_DAY=Sat

#-- check if parent directory for backup exist

if [ ! -d $BACKUP_PATH ];
then
  mkdir -p $BACKUP_PATH
fi

#-- check if a log directory for backup logs exist

if [ ! -d $BACKUP_PATH/log ];
then
  mkdir -p $BACKUP_PATH/log
fi

#-- check if required backup subdir exist(current)

if [ ! -d $BACKUP_PATH/current ];
then
  mkdir $BACKUP_PATH/current
fi  

#-- Select backup mode full (full) or incremental (incr)

if [ "$DAY_OF_WEEK" = "$FBU_DAY" ]
then
  CBB_MODE=full
else
  CBB_MODE=incr
fi

#-- Initialize the log file.
CBB_LOG_FILE=${BACKUP_PATH}/log/couchbase_backup_${CBB_MODE}_${LOG_DATE}.log
echo >> $CBB_LOG_FILE
chmod 666 $CBB_LOG_FILE
echo Runtime Script: $0 >> $CBB_LOG_FILE
echo Runtime User: $RTUSER >> $CBB_LOG_FILE
echo PID: $$ >> $CBB_LOG_FILE
echo Hostname: $HNAME >> $CBB_LOG_FILE
echo Couchbase OS User: $CBUSER >> $CBB_LOG_FILE
echo ==== started on `date` ==== >> $CBB_LOG_FILE
echo >> $CBB_LOG_FILE

#-- Run the backup

if [ ! -f $BACKUP_PATH/.cbb_lock ];
then
   echo $$ >> $BACKUP_PATH/.cbb_lock

   if [ "$CBB_MODE" = "full" ]
   then
      cd $BACKUP_PATH/current
      keep=`ls -ld CB_BACKUP_* |wc -l` >> /dev/null 2>&1
      if [ $keep -gt 2 ]; then
		oldest=`ls -ld CB_BACKUP_*|awk '{print $NF}'|head -1`
		$CBBACKUP remove -a $BACKUP_PATH/current -r $oldest
		echo "$oldest backup has been removed as per retention policy"
		$CBBACKUP config -a $BACKUP_PATH/current -r $CB_REPO
                CMD_STR="${CBBACKUP} backup -a $BACKUP_PATH/current -r ${CB_REPO} -c $CLUSTER_NODE_URL -u ${DBU} -p $DBP -t ${CB_THREADS}"
	  else	
	        $CBBACKUP config -a $BACKUP_PATH/current -r $CB_REPO
			CMD_STR="${CBBACKUP} backup -a $BACKUP_PATH/current -r ${CB_REPO} -c $CLUSTER_NODE_URL -u ${DBU} -p $DBP -t ${CB_THREADS}"	
	  fi
   fi

   if [ "$CBB_MODE" = "incr" ]
   then
      cd $BACKUP_PATH/current
      CURREPO=`ls -td CB_BACKUP_* |awk '{print $NF}'|head -n 1`
      echo Backup Mode: $CBB_MODE >> $CBB_LOG_FILE
      CMD_STR="${CBBACKUP} backup -a $BACKUP_PATH/current -r $CURREPO -c $CLUSTER_NODE_URL -u ${DBU} -p $DBP -t ${CB_THREADS}"
   fi

   if [ "$RTUSER" = "root" ]
   then
       su - $CBUSER -c "$CMD_STR" >> $CBB_LOG_FILE
       RSTATUS=$?  
   else
       /bin/bash -c "$CMD_STR" >> $CBB_LOG_FILE
       RSTATUS=$?
   fi

   #-- release lock file
   rm $BACKUP_PATH/.cbb_lock
else
   echo >> $CBB_LOG_FILE
   echo WARNING: Backup aborted. >> $CBB_LOG_FILE
   echo An existing backup process is still be running, please check. >> $CBB_LOG_FILE
   echo PID: >> $CBB_LOG_FILE
   cat $BACKUP_PATH/.cbb_lock >> $CBB_LOG_FILE
   echo >> $CBB_LOG_FILE
fi

if [ "$RSTATUS" = "0" ]
then
    LOGMSG="Backup Ended Successfully"
else
    LOGMSG="Backup Ended with Error"   
fi

echo >> $CBB_LOG_FILE
echo Runtime Script: $0 >> $CBB_LOG_FILE
echo ==== $LOGMSG on `date` ==== >> $CBB_LOG_FILE
echo >> $CBB_LOG_FILE

if [ $RSTATUS -ne 0 ]
then
cat $CBB_LOG_FILE | /bin/mailx -s "$HNAME: Couchbase database backup failed" rajesh.kumar@xyz.com
fi;

exit $RSTATUS
