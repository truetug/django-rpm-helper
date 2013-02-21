#!/bin/sh
name="superprogramm"

# gunicorn startup script
#
# chkconfig: - 85 15
# processname: $prog
# config: /etc/sysconfig/$prog
# pidfile: /var/run/$prog.pid
# description: $prog

# Setting `prog` here allows you to symlink this init script, making it easy to run multiple processes on the system.
prog="$(basename $0)"

# Source function library.
. /etc/rc.d/init.d/functions

# Also look at sysconfig; this is where environmental variables should be set on RHEL systems.
[ -f "/etc/sysconfig/$prog" ] && . /etc/sysconfig/$prog

pidfile="/var/run/${prog}.pid"
lockfile="/var/lock/subsys/${prog}"

bin="/usr/bin/${name}"
opts="celeryd_detach -EB --pidfile=${pidfile} -c 5 -l INFO --logfile=/var/log/${name}/celeryd.log --uid=$(id -u ${name}) --gid=$(id -g ${name})"

RETVAL=0


start() {
	echo -n $"Starting $prog: "
	${bin} ${opts}
	RETVAL=$?
	echo
	[ $RETVAL = 0 ] && touch ${lockfile}
	return $RETVAL
}

stop() {
	echo -n $"Stopping $prog: "
	killproc -p ${pidfile} ${name}
	RETVAL=$?
	echo
	[ $RETVAL = 0 ] && rm -f ${lockfile} ${pidfile}
}

rh_status() {
	status -p ${pidfile} ${prog}
}

# See how we were called.
case "$1" in
	start)
		rh_status > /dev/null 2>&1 && exit 0
		start
	;;
	stop)
		stop
	;;
	status)
		rh_status
		RETVAL=$?
	;;
	restart)
		stop
		start
	;;
	*)
		echo $"Usage: $0 {start|stop|restart|status}"
		RETVAL=2
esac

exit $RETVAL