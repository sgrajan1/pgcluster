#!/bin/bash
# this script will re-attach a failed standby database
# or recover a failed primary database
# it requires that pgpool is available and that the database on this node is running
# this script might be called when the postgres container is starting but then it must do so
# when both pgpool and the database is running. Since the db is started with supervisor, this would
# require to lauch the script in the background after the start of postgres
# the script can also be started manually or via cron

# Created by argbash-init v2.6.1
# ARG_OPTIONAL_BOOLEAN([auto-recover-standby],[],[reattach a standby to pgpool if possible],[on])
# ARG_OPTIONAL_BOOLEAN([auto-recover-primary],[],[recover the degenerated master],[off])
# ARG_OPTIONAL_SINGLE([lock-timeout-minutes],[],[minutes after which a lock will be ignored (optional)],[120])
# ARG_HELP([<The general help message of my script>])
# ARGBASH_GO()
# needed because of Argbash --> m4_ignore([
### START OF CODE GENERATED BY Argbash v2.6.1 one line above ###
# Argbash is a bash code generator used to get arguments parsing right.
# Argbash is FREE SOFTWARE, see https://argbash.io for more info

die()
{
	local _ret=$2
	test -n "$_ret" || _ret=1
	test "$_PRINT_HELP" = yes && print_help >&2
	echo "$1" >&2
	exit ${_ret}
}

begins_with_short_option()
{
	local first_option all_short_options
	all_short_options='h'
	first_option="${1:0:1}"
	test "$all_short_options" = "${all_short_options/$first_option/}" && return 1 || return 0
}



# THE DEFAULTS INITIALIZATION - OPTIONALS
_arg_auto_recover_standby="on"
_arg_auto_recover_primary="off"
_arg_lock_timeout_minutes="120"

print_help ()
{
	printf '%s\n' "<The general help message of my script>"
	printf 'Usage: %s [--(no-)auto-recover-standby] [--(no-)auto-recover-primary] [--lock-timeout-minutes <arg>] [-h|--help]\n' "$0"
	printf '\t%s\n' "--auto-recover-standby,--no-auto-recover-standby: reattach a standby to pgpool if possible (on by default)"
	printf '\t%s\n' "--auto-recover-primary,--no-auto-recover-primary: recover the degenerated master (off by default)"
	printf '\t%s\n' "--lock-timeout-minutes: minutes after which a lock will be ignored (optional) (default: '120')"
	printf '\t%s\n' "-h,--help: Prints help"
}

parse_commandline ()
{
	while test $# -gt 0
	do
		_key="$1"
		case "$_key" in
			--no-auto-recover-standby|--auto-recover-standby)
				_arg_auto_recover_standby="on"
				test "${1:0:5}" = "--no-" && _arg_auto_recover_standby="off"
				;;
			--no-auto-recover-primary|--auto-recover-primary)
				_arg_auto_recover_primary="on"
				test "${1:0:5}" = "--no-" && _arg_auto_recover_primary="off"
				;;
			--lock-timeout-minutes)
				test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
				_arg_lock_timeout_minutes="$2"
				shift
				;;
			--lock-timeout-minutes=*)
				_arg_lock_timeout_minutes="${_key##--lock-timeout-minutes=}"
				;;
			-h|--help)
				print_help
				exit 0
				;;
			-h*)
				print_help
				exit 0
				;;
			*)
				_PRINT_HELP=yes die "FATAL ERROR: Got an unexpected argument '$1'" 1
				;;
		esac
		shift
	done
}

parse_commandline "$@"

# OTHER STUFF GENERATED BY Argbash

### END OF CODE GENERATED BY Argbash (sortof) ### ])
# [ <-- needed because of Argbash


printf "'%s' is %s\\n" 'auto-recover-standby' "$_arg_auto_recover_standby"
printf "'%s' is %s\\n" 'auto-recover-primary' "$_arg_auto_recover_primary"
printf "'%s' is %s\\n" 'lock-timeout-minutes' "$_arg_lock_timeout_minutes"

PIDFILE=/home/postgres/recover_failed_node.pid

trap cleanup EXIT

PGP_NODE_ID=$(( NODE_ID-1 ))
PGP_STATUS_WAITING=1
PGP_STATUS_UP=2
PGP_STATUS_DOWN=3

LOGFILENAME="${PROGNAME%.*}.log"


if [ -d /logs ] ; then
 LOGFILE=/logs/${LOGFILENAME}
else
 LOGFILE=${PGDATA}/log/${LOGFILENAME}
fi
if [ ! -f $LOGFILE ] ; then
 touch $LOGFILE
fi

log_info(){
 echo $( date +"%Y-%m-%d %H:%M:%S.%6N" ) - INFO - $1 | tee -a $LOGFILE
}

log_error(){
 echo $( date +"%Y-%m-%d %H:%M:%S.%6N" ) - ERROR - $1 | tee -a $LOGFILE
}

cleanup(){
  # remove pid file but only if it is mine, dont remove if another process was running
  if [ -f $PIDFILE ] ; then
    MYPID=$$
    STOREDPID=$(cat $PIDFILE)
    if [ "${MYPID}" == "${STOREDPID}" ] ; then
      rm -f $PIDFILE
    fi
  fi 
  if [ -z $INSERTED_ID ] ; then
    return
  fi
  log_info "delete from recover_failed with id $INSERTED_ID"
  psql -U repmgr -h pgpool -p 9999 repmgr -t -c "delete from recover_failed_lock where id=${INSERTED_ID};"
}

# test if there is lock in the recover_failed_lock table
# return 0 if there is no lock, 1 if there is one
is_recovery_locked(){
  #clean-up old records
  psql -U repmgr -h pgpool -p 9999 repmgr -c "delete from recover_failed_lock where ts < current_timestamp - INTERVAL '1 day';"
  # check if there is already an operation in progress
  str=$(psql -U repmgr -h pgpool -p 9999 repmgr -c "select ts,node from recover_failed_lock where ts > current_timestamp - INTERVAL '${_arg_lock_timeout_minutes} min';")
  if [ $? -ne 0 ] ; then
    log_error "psql error when selecting from recover_failed_lock table"
    exit 1
  fi 
  echo $str | grep "(0 rows)"
  if [ $? -eq 0 ] ; then
    return 0
  fi
  log_info "there is a lock record in recover_failed_lock : $str"
  return 1
}

# take a lock on the the recovery operation
# by inserting a record in table recover_failed_lock
# fails if there is already a recovery running (if an old record still exist)
# exit -1 : error 
#  return 0: cannot acquire a lock because an operation is already in progress
  
lock_recovery(){
  MSG=$1
  # create table if not exists
  psql -U repmgr -h pgpool -p 9999 repmgr -c "create table if not exists recover_failed_lock(id serial,ts timestamp with time zone default current_timestamp,node varchar(10) not null,message varchar(120));"
  if [ $? -ne 0 ] ; then
    log_error "Cannot create table recover_failed_lock table"
    exit 1
  fi
  is_recovery_locked
  if [ $? -eq 1 ] ; then
    return 0
  fi
  str=$(psql -U repmgr -h pgpool -p 9999 repmgr -t -c "insert into recover_failed_lock (node,message) values ('${NODE_NAME}','${MSG}') returning id;")
  if [ $? -ne 0 ] ; then
    log_info "cannot insert into recover_failed_lock"
    exit 1
  fi
  INSERTED_ID=$(echo $str | awk '{print $1}')
  log_info "inserted lock in recover_failed_log with id $INSERTED_ID"
  return $INSERTED_ID
}


pg_is_in_recovery(){
  psql -t -c "select pg_is_in_recovery();" | head -1 | awk '{print $1}'
}

check_is_streaming_from(){
  PRIMARY=$1
  # first check if is_pg_in_recovery is t
  in_reco=$( pg_is_in_recovery )
  if [ "a${in_reco}" != "at" ] ; then
    return 0
  fi
  psql -t -c "select * from pg_stat_wal_receiver;" > /tmp/stat_wal_receiver.tmp
  # check that status is streamin
  status=$( cat /tmp/stat_wal_receiver.tmp | head -1 | cut -f2 -d"|" | sed -e "s/ //g" )
  if [ "a${status}" != "astreaming" ] ; then
    log_info "status is not streaming"
    return 0
  fi
  #check that is recovering from primary
  conninfo=$( cat /tmp/stat_wal_receiver.tmp | head -1 | cut -f12 -d"|" )
  echo $conninfo | grep "host=${PRIMARY}"
  if [ $? -eq 1 ] ; then
    log_info "not streaming from $PRIMARY"
    return 0
  fi
  return 1
}

# arg: 1 message
recover_failed_master(){
  # try to acquire a lock
  MSG=$1
  lock_recovery "$MSG"
  LOCK_ID=$?
  if [ ${LOCK_ID} -eq 0 ] ; then
    log_info "cannot acquire a lock, probably an old operation is in progress ?"
    return 99
  fi
  log_info "acquired lock $LOCK_ID"
  #echo "First try node rejoin"
  #echo "todo"
  log_info "Do pcp_recovery_node of $PGP_NODE_ID"
  pcp_recovery_node -h pgpool -p 9898 -w $PGP_NODE_ID
  ret=$?
  cleanup
  return $ret
}

recover_standby(){
  #dont do it if there is a lock on recover_failed_lock
  is_recovery_lock
  if [ $? -eq 1 ] ; then
    return 0
  fi
  if [ "$_arg_auto_recover_standby" == "on" ] ; then
    log_info "attach node back since it is in recovery streaming from $PRIMARY_NODE_ID"
    pcp_attach_node -h pgpool -p 9898 -w ${PGP_NODE_ID}
    if [ $? -eq 0 ] ; then
      log_info "OK attached node $node back since it is in recovery and streaming from $PRIMARY_NODE_ID"
      exit 0
    fi
    log_error "attach node failed for node $node"
    exit 1
  else
    log_info "auto_recover_standby is off, do nothing"
    exit 0
  fi
}

if [ -f $PIDFILE ] ; then
  PID=$(cat $PIDFILE)
  ps -p $PID > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
    log_info "script already running with PID $PID"
    exit 0
  else
    log_info "PID file is there but script is not running, clean-up $PIDFILE"
    rm -f $PIDFILE
  fi
fi
echo $$ > $PIDFILE
if [ $? -ne 0 ] ; then
  log_error "Could not create PID file"
  exit 1
fi
log_info "Create $PIDFILE with value $$"

str=$( pcp_node_info -h pgpool -p 9898 -w $PGP_NODE_ID )
if [ $? -ne 0 ] ; then
  log_error "pgpool cannot be accessed"
  rm -f $PIDFILE
  exit 1
fi

read node port status weight status_name role <<< $str
if [ $status -ne $PGP_STATUS_DOWN ] ; then
  log_info "pgpool status for node $node is $status_name and role $role, nothing to do"
  rm -f $PIDFILE
  exit 0
fi
log_info "Node $node is down (role is $role)"
# status down, the node is detached
# get the primary from pool_nodes
psql -h pgpool -p 9999 -U repmgr -c "show pool_nodes;" > /tmp/pool_nodes.log
if [ $? -ne 0 ] ; then
  log_error "cannot connect to postgres via pgpool"
  rm -f $PIDFILE
  exit 1
fi
PRIMARY_NODE_ID=$( cat /tmp/pool_nodes.log | grep primary | grep -v down | cut -f1 -d"|" | sed -e "s/ //g")
PRIMARY_HOST=$( cat /tmp/pool_nodes.log | grep primary | grep -v down | cut -f2 -d"|" | sed -e "s/ //g")
log_info "Primary node is $PRIMARY_HOST"

# check if this node is a failed master (degenerated master)
# if yes then pcp_recovery_node or node rejoin is needed
if [ $role == "primary" ] ; then
  # this should never happen !!
  log_info "This node is a primary and it is down: recovery needed"
  # sanity check
  if [ $PRIMARY_NODE_ID -ne $PGP_NODE_ID ] ; then
     log_error "Unpextected state, this node $PGP_NODE_ID is a primary according to pcp_node_info but pool_nodes said $PRIMARY_NODE_ID is master"
     rm -f $PIDFILE
     exit 1
  fi
  if [ "$_arg_auto_recover_primary" == "on" ] ; then
    recover_failed_master "primary node reported as down in pgpool"
    ret=$?
    rm -f $PIDFILE
    exit $ret
  else
    log_info "auto_recover_primary is off, do nothing"
    rm -f $PIDFILE
    exit 0
  fi
fi

log_info "This node is a standby and it is down: check if it can be re-attached"
log_info "Check if the DB is running, if not do not start it but exit with error"
pg_ctl status
if [ $? -ne 0 ] ; then
  log_error "the DB is not running"
  rm -f $PIDFILE
  exit 1
  # we cannot use supervisorctl start postgres
  # because if this script is called from initdb.sh it would recurse
  #pg_stl start -w
  #if [ $? -ne 0 ] ; then
  #  echo "Cannot start DB"
  #  exit 1
  #fi
  #DB_WAS_STARTED=1
fi
check_is_streaming_from $PRIMARY_HOST
res=$?
if [ $res -eq 1 ] ; then
  recover_standby
  ret=$?
  rm -f $PIDFILE
  exit $ret
fi
if [ "$_arg_auto_recover_primary" == "on" ] ; then
  log_info "node is standby in pgpool but it is not streaming from the primary, probably a degenerated master. Lets do pcp_recovery_node"
  recover_failed_master "standby node not streaming from the primary"
  ret=$?
  rm -f $PIDFILE
  exit $ret
else
  log_info "node is supposed to be a standby but it is not streaming from the primary, however auto_recovery_primary is off so do nothing"
fi
rm -f $PIDFILE
exit 0

# ] <-- needed because of Argbash
