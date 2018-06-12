#!/bin/bash
# This file is part of archaeologit which is released under the MIT license. See LICENSE.md.
# Archaeologit was originally written by Peter Jaric <peter@jaric.org>

# Fail script immediately if something goes wrong
set -e

if which tput > /dev/null
then
		TPUT=tput
else
		TPUT=:
fi

UNDERLINE_START=$(${TPUT} smul)
UNDERLINE_END=$(${TPUT} rmul)

# Log message
# -d Suppress date
# -u Underline text
# -n No new line
# In message: _S_ -> Start underlining, _E_ -> Stop underlining
log() {
		local OPTIND
		local SUPPRESS_DATE
		local SUPPRESS_NEWLINE
		local OVERWRITE
		local UNDERLINE
		local FILE
		
		while getopts "rndf:" opt; do
				case $opt in
						d) SUPPRESS_DATE=true	;;
						f) FILE=${OPTARG} ;;
						n) SUPPRESS_NEWLINE=true ;;
						r) OVERWRITE=true; SUPPRESS_NEWLINE=true ;;
						\?)	echo "Invalid option to log: -${OPTSTRING}" >&2 ;;
				esac
		done
		
		shift $((OPTIND-1))
		MSG=$@
		FMSG=${MSG}

		# Handle special strings
		MSG=${MSG//_S_/$UNDERLINE_START}
		MSG=${MSG//_E_/$UNDERLINE_END}
		FMSG=${FMSG//_S_/}
		FMSG=${FMSG//_E_/}
		
		if [ "${SUPPRESS_DATE}" != true ]
		then
				MSG="[$(date)] ${MSG}"
				FMSG="[$(date)] ${FMSG}"
		fi

		if [ "${OVERWRITE}" == true ]
		then
				MSG="\r${MSG}"
		fi

		echo -en "${MSG}"
		
		if [ "${SUPPRESS_NEWLINE}" != true ]
		then
				echo
		fi
		
		if [ "${FILE}" != "" ]
		then
				echo "${FMSG}"	>> ${FILE}
		fi

		
}


faketimeout() {
		shift 1
		eval $@
}

if which timeout > /dev/null
then
		TIMEOUT_BIN=timeout
elif which gtimeout > /dev/null
then
		TIMEOUT_BIN=gtimeout
else
		TIMEOUT_BIN=faketimeout
		log -d "No timeout command found, disabling timeout functionality."
fi

SED_BIN=sed
if which gsed > /dev/null 
then
		SED_BIN=gsed
fi
