#!/bin/sh

# Copyright (C) 2005-2025 AMIQ EDA s.r.l.

if test "$1" = "--test" ; then
	which "sleep"  >/dev/null 2>&1 && \
	which "cat"    >/dev/null 2>&1 && echo "basic"
	which "setsid" >/dev/null 2>&1 && echo "session"
	which "xterm"  >/dev/null 2>&1 && echo "xterm"
	which "mkfifo" >/dev/null 2>&1 && echo "redirect"
	exit 0
fi 

PID=$$
CMD=''

FIFO="$(dirname $0)/$PID.out"
export FIFO

SIDF="$(dirname $0)/$PID.sid"
export SIDF

WAIT_SIDF_TIMEOUT=5

COMMON_FUNCTIONS='
kill_session() {
	if test -n "$1" ; then
		for child in $(ps -o pid --no-headers --sid $1) ; do
			test "$1" != "$child" && kill -s KILL $child > /dev/null 2>&1
		done
		kill -s TERM $1 > /dev/null 2>&1
	fi
}

print_xterm_end() {
	echo "=== XTERM SESSION HAS ENDED ==="
}

kill_xterm_session() {
	kill_session $$
	print_xterm_end
}

write_sid() {
	echo $$ > "$SIDF"
}
'
export COMMON_FUNCTIONS
eval "$COMMON_FUNCTIONS"

EVAL_CMD='eval "$COMMON_FUNCTIONS"'
SID_CMD='set -m ; write_sid'
XTERM_TRAP_CMD="trap : HUP INT QUIT TERM KILL ; trap 'kill_xterm_session' EXIT"
TEE_CMD='(trap "" HUP INT QUIT TERM KILL ; tee "$FIFO")'


TERMINATE_ON_EXIT=false
USE_XTERM_SESSION=false
REDIRECT_XTERM_OUT=false
HOLD_XTERM_WINDOW=false

cleanup() {
	rm "$FIFO" > /dev/null 2>&1
	rm "$SIDF" > /dev/null 2>&1
}

wait_for_sidf() {
	counter=0
    while test $counter -lt $WAIT_SIDF_TIMEOUT ; do
		test -f "$SIDF" && cat "$SIDF" && return
		counter=$((counter+1))
		sleep 1
	done
	test -n "$1" && kill -s KILL $1 > /dev/null 2>&1
	cleanup
	kill -s KILL $PID > /dev/null 2>&1
}

kill_sid_session() {
	sid=$(wait_for_sidf)
	kill_session $sid
}

handle_exit() {
	$TERMINATE_ON_EXIT && kill_sid_session
	cleanup
}

read_out() {
	while read line ; do
		echo "$line" | sed -r 's/[\x01-\x1F\x7F][\[\(][0-9;]*[ABCDEFGHJKSTfmnsu]//g'
	done < "$FIFO"
	print_xterm_end
}

test $# -gt 0 || exit 1
while test $# -gt 0 ; do
    case "$1" in
    	--terminate-on-exit) 
      		TERMINATE_ON_EXIT=true
		;;
		--use-xterm-session)
			USE_XTERM_SESSION=true
      	;;
		--redirect-xterm-out)
			REDIRECT_XTERM_OUT=true
      	;;
		--hold-xterm-window)
			HOLD_XTERM_WINDOW=true
      	;;
		*) break
      	;;
    esac
    shift       
done

test $# -gt 0 || exit 1

trap 'handle_exit' EXIT

for arg in "$@";do 
	CMD="$CMD '$arg'"
done

if $USE_XTERM_SESSION ; then

	hold_arg=''
	$HOLD_XTERM_WINDOW && hold_arg='-hold' || hold_arg='+hold'

	if $REDIRECT_XTERM_OUT ; then
		CMD="$EVAL_CMD ; $SID_CMD ; $XTERM_TRAP_CMD ; $CMD | $TEE_CMD"
		mkfifo "$FIFO" && read_out &
	else
		CMD="$EVAL_CMD ; $SID_CMD ; $XTERM_TRAP_CMD ; $CMD"
	fi

	xterm $hold_arg -e sh -c "$CMD" > /dev/null 2>&1 & xterm_pid=$!

	sid=$(wait_for_sidf $xterm_pid)
	while kill -s 0 $sid > /dev/null 2>&1 ; do
		sleep 1 > /dev/null 2>&1
	done
	
else

	CMD="$EVAL_CMD ; $SID_CMD ; $CMD "
	setsid sh -c "$CMD"
	
fi

