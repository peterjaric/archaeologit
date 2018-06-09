#!/bin/bash
# This file is part of archaeologit which is released under the MIT license. See LICENSE.md.
# Archaeologit was originally written by Peter Jaric <peter@jaric.org>

DESCRIPTION=\
"This script scans the history of a user's GitHub repositories
for a given pattern to find sensitive things that may have been there
but have been overwritten in a later commit. For example passwords or
secret tokens.

Example:
./archaeologit.sh USERNAME 'password.....|secret.....|passwd.....|credentials.....|creds.....|aws.?key.....|consumer.?key.....|api.?key.....|aws.?token.....|oauth.?token.....|access.?token.....|api.?token.....'
"

# Fail script immediately if something goes wrong (some commands need "|| true" after them because of this)
set -e

# Load some useful utility functions
source utils.sh

# Timeout of git clone and git fetch per repository
TIMEOUT=5m

# Max number of commits to scan. Will scan the latest commits if more than this limit.
MAX_COMMITS=10000

# Where to store repositories locally
WORKINGPATH=/tmp/archaeologit/repos

# Where results are logged by default
DEFAULT_LOG_FILE=archaeologit.log

# Do not show files matching this pattern
export PATH_BLACKLIST_PATTERN='.*\.md|.*\.markdown|.*\.html?|.*\.css|.*\.min.js|.*\.rst|.*\.jquery\..*\.js|.*/node_modules/.*|.*test.*|.*example.*|.*sample.*|.*rdoc|.*spec.rb'

# Get script arguments
USERNAME=$1
PATTERN=$2
LOG_FILE=$3

export PATTERN
export SED_PATTERN=$(echo "${PATTERN}" | ${SED_BIN} 's/\([|?*]\)/\\\1/g')
export SED_BIN

# Validate arguments
if [ "${USERNAME}" = "" -o "${PATTERN}" = "" ]
then
		echo "${DESCRIPTION}"
		echo "Usage:   $0 <github username or git repo url> '<regular expression to search for>' [<log file>]"
		echo "Example: $0 peterjaric 'password|secret|token' scan.log"
		echo "Warning: do not use capturing groups in pattern."
		exit 1
fi


# Cleanup function for when script is interrupted
function prematurefinish {
		log -f ${LOG_FILE} "Script exited prematurely, probably due to an error."
		if [ "${ONGOING_CLONE}" != "" -a -d "${ONGOING_CLONE}" ]
		then
				log -d "Cleaning up interrupted clone folder ${ONGOING_CLONE}."
				rm -rf ${ONGOING_CLONE}
		fi
}
trap prematurefinish EXIT

mkdir -p ${WORKINGPATH}

# Create list of repos, either just one from command line, or by
# fetching it from GitHub
if [[ "${USERNAME}" == http* ]]
then
		# Check file argument and set to default if missing
		if [ "${LOG_FILE}" = "" ]
		then
				LOG_FILE="${DEFAULT_LOG_FILE}"
		fi
		REPOS=${USERNAME}
		log -d "Writing output to _S_${LOG_FILE}_E_"
		log -f ${LOG_FILE} "Fetching just one repo: _S_${REPOS}_E_"
else
		# Check file argument and set to default if missing
		if [ "${LOG_FILE}" = "" ]
		then
				LOG_FILE="${USERNAME}_${DEFAULT_LOG_FILE}"
		fi

		log -d "Writing output to _S_${LOG_FILE}_E_"
		log -f ${LOG_FILE} "Fetching _S_${USERNAME}_E_'s GitHub repos..."

 		# User
		JSON=$(curl -s "https://api.github.com/users/${USERNAME}/repos?type=all&per_page=100") # Currently not paging above 100 repos
		REPOS=$(echo "${JSON}" | grep clone_url | cut -d'"' -f4)

 		# Organization
		JSON=$(curl -s "https://api.github.com/orgs/${USERNAME}/repos?type=all&per_page=100") # Currently not paging above 100 repos
		REPOS="${REPOS}"$(echo "${JSON}" | grep clone_url | cut -d'"' -f4)
fi

LOG_FILE=$(realpath ${LOG_FILE})

REPO_COUNT=$(echo -n "${REPOS}" | wc -w) 

log  -f ${LOG_FILE} "Going to search for: /${PATTERN}/i in ${REPO_COUNT} repos."

export LOG_FILE

for REPO in ${REPOS}
do
		# Create the local folder name for this repository
		CLONEPATH=${WORKINGPATH}/$(echo ${REPO} |
																			rev |                # Reverse path
																			cut -d "/" -f 1-2 |  # Get rid of everything after the second slash
																			cut -c 5- |          # Remove "tig." (".git")
																			rev)                 # Reverse back - now we have username/reponame

		export GITHUBURL=$(echo ${REPO} | rev | cut -d "." -f 2- | rev) # Remove .git  
				
		# If repository already present, just update it, otherwise clone it
		if [ -e "${CLONEPATH}" -a -d "${CLONEPATH}" ]
		then
				# Update existing repository
				GIT_GET="bash -c 'cd ${CLONEPATH} && git fetch -q origin HEAD:HEAD ; cd -'"
		else
				# Clone repository
				mkdir -p ${CLONEPATH}
				
				# Inject fake username and password into repo url to avoid prompting when
				# cloning private or removed repo
				REPO_WITH_CREDS=$(echo $REPO | sed 's|//|//git:git@|')

				GIT_GET="git clone --bare -q ${REPO_WITH_CREDS} ${CLONEPATH}"
		fi

		log -f ${LOG_FILE} "Getting _S_${REPO}_E_..."

		# Going to fetch this repo
		ONGOING_CLONE=${CLONEPATH}

		# Fetch repo, timeout if it takes too much time
		if eval ${TIMEOUT_BIN} ${TIMEOUT} ${GIT_GET}  > /dev/null 2> /dev/null
		then
				# Done fetching this repo
				unset ONGOING_CLONE
				
				log "Searching repository..."
				cd ${CLONEPATH}
				
				# Make a list of all commit hashes
				ALL_COMMITS=$(git log --all --pretty=format:%h --max-count ${MAX_COMMITS}) > /dev/null 2> /dev/null || true 
				
				export ALL_COMMITS
				
				if [ "${ALL_COMMITS}" != "" ]
				then
						# Grep for all occurences of PATTERN in all commits of the repository
						if ! ${TIMEOUT_BIN} ${TIMEOUT} bash -c 'git grep -I --ignore-case --line-number --extended-regexp -e "${PATTERN}" ${ALL_COMMITS} |
						  sort -u -t":" -k4 |                                       # Remove duplicate lines	
						  while IFS= read -r LINE; do                               # Fold lines and keep only the parts with the pattern
							  	HASH=$(echo "${LINE}" | cut -d: -f1)
							 	  GITPATH=$(echo "${LINE}" | cut -d: -f2)
								  LINENUMBER=$(echo "${LINE}" | cut -d: -f3)
                  GITHUBPATH="${GITHUBURL}/blob/${HASH}/${GITPATH}"
                  if [[ ! ${GITPATH} =~ ${PATH_BLACKLIST_PATTERN} ]]
                  then
								    echo "${LINE}" |
									    	tr -d "\015" |                                    # Remove Windows line ending character (^M)
									    	cut -d: -f4- |                                    # Remove location
									  	  fold -s |                                         # Fold long lines on spaces
									  	  fold |                                            # Fold again if any lines still are too long
									  	  grep -iE "${PATTERN}" |                           # Only keep lines matching the pattern
                        ${SED_BIN} "s@\(${SED_PATTERN}\)@KILLUNTILHERE\1@i" | # 
                        ${SED_BIN} "s@^.*KILLUNTILHERE\(${SED_PATTERN}\)\(.\{0,30\}\).*@\1\2~${GITHUBPATH}#L${LINENUMBER}@i"  # Format line to fit the column command 
                  fi
						  done |                                                    # Echo to stdout
            column -t -s"~" |                      # Format line in columns
						tee -a ${LOG_FILE} |                                      # Also echo to file
					  grep --color -iE "${PATTERN}" || true'                    # Colorize pattern in stdout
			  	  then
						  log -f "${LOG_FILE}" "Timed out after ${TIMEOUT}."
			  		fi
				else
						log "Empty repository, no commits!"
				fi
				cd - > /dev/null
		else
				log -f "${LOG_FILE}" "Timed out after ${TIMEOUT} or could not fetch repository."
		fi
		log -f "${LOG_FILE}" "Done."
done

# Remove trap, we are going to exit correctly
trap EXIT
