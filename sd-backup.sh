#!/bin/bash

readonly SCRIPT_VERSION='0.5.3'
readonly LINE='==============================================================================='
declare tmp="${BASH_SOURCE[0]}"
readonly SCRIPT_PATH="$( cd -- "$(dirname "${tmp}")" >/dev/null 2>&1 ; pwd -P )"
readonly SCRIPT_NAME="${tmp##*/}"
readonly SCRIPT_HEADER="\n${LINE}\n ${SCRIPT_NAME} v${SCRIPT_VERSION} - SD card backup for MacOS \n${LINE}\n"
readonly OS_TYPE="$(uname)"

declare TS _doNotAskForConfirmation defaultBS _srcDisk srcDisk srcDiskSize destFile defaultDestFile

readonly defaultBS='1m'
readonly defaultDestFile="./SD-card.bs${defaultBS}.dd.img"

if [[ "$@" =~ -y ]]
	then
		_doNotAskForConfirmation="true"
	fi
readonly _doNotAskForConfirmation

#////////////////////////////////////////////////////////////////////////////////////////////

shopt -s nocasematch

#////////////////////////////////////////////////////////////////////////////////////////////

function SHOW_USAGE()
{
cat <<EOF
USAGE:

  ${SCRIPT_NAME} [source-device] [backup-file-name] [-y]

    source-device        = source device (SD card, eg: /dev/disk2).
    backup-file-name     = backup file name; default value is "${defaultDestFile}"".
    -y                   = do NOT ask for confirmation for starting backup process.

EOF

}

#////////////////////////////////////////////////////////////////////////////////////////////

function getTimeStamp()
{
 TS="$(date +'%Y-%m-%d %H:%M:%S')"
}
readonly -f getTimeStamp

#////////////////////////////////////////////////////////////////////////////////////////////

function searchDisks()
{
 if [ ! "$srcDisk" ]
 	then
		declare md isMatch regexPattern="$1"
		shift
  	declare -a mountedDisks=("$@")

		for md in "${mountedDisks[@]}"
		do
			isMatch=$(diskutil info "$md" 2>/dev/null | grep -oE "${regexPattern}")

			if [ "$isMatch" ]
				then
					srcDisk="$md"
					break
				fi
		done
	fi
}

#////////////////////////////////////////////////////////////////////////////////////////////

echo -e "${SCRIPT_HEADER}"



if [[ ! $OS_TYPE == 'darwin' ]]
	then
		getTimeStamp
	  echo "[${TS}] ERROR - This script is intented to run on MacOS"
	  exit 255
	fi



if [[ "$@" =~ -{1,2}help ]]
	then
		SHOW_USAGE
		exit 0
	fi



srcDisk="$1"
if [[ "$srcDisk" =~ -y ]]
  then
     srcDisk=''
  fi
if [ ! "$srcDisk" ]
  then
    declare -a mountedDisks=($(diskutil list | grep -oE '\/dev\/disk[0-9]+' | sort -u))

		searchDisks 'SD\s+Card\s+Reader' "${mountedDisks[@]}"
		searchDisks 'USB\s+SD\s+Reader' "${mountedDisks[@]}"

		unset mountedDisks
  fi
if [ ! "$srcDisk" ]
then
  getTimeStamp
  echo -e "[${TS}] ERROR - Unable to detect SD card automatically.\nPlease specify \"source-device\" as first parameter of the script.\n"
  SHOW_USAGE
  exit 254
fi
if [[ ! "$srcDisk" =~ ^/dev/ ]]
  then
    srcDisk="/dev/${srcDisk}"
  fi
srcDisk="${srcDisk/\/dev\/disk//dev/rdisk}"
_srcDisk="${srcDisk/\/dev\/rdisk//dev/disk}"
readonly _srcDisk srcDisk

srcDiskSize=$(diskutil info "$srcDisk" 2>/dev/null | grep -E 'Disk\s+Size' | tr ' ' '\n' | grep -E '\S' | head -5 | tail -1 | grep -oE '[0-9]+')
readonly srcDiskSize
if [ ! "$srcDiskSize" ]
  then
    getTimeStamp
		echo "[${TS}] ERROR - Disk not found: ${srcDisk}"
		exit 253
  fi

#////////////////////////////////////////////////////////////////////////////////////////////

destFile="${2:-$defaultDestFile}"
if [[ "$destFile" =~ -y ]]
  then
     destFile="${defaultDestFile}"
  fi

#////////////////////////////////////////////////////////////////////////////////////////////

printf '%-20s %s\n' "Source disk:" "${srcDisk} (${srcDiskSize} bytes)"
printf '%-20s %s\n' "Destination file:" "${destFile}.zip"
echo


if [ ! "${_doNotAskForConfirmation}" ]
  then
    read -p "Start backup process? " -n 1 -r
    echo -e "\n"
    if [[ ! $REPLY =~ ^y$ ]]; then exit 1; fi
  fi


if [ "$(mount | grep "${_srcDisk}")" ]
  then
    getTimeStamp
    echo -e "[${TS}] Unmounting disk ${srcDisk}..."
    diskutil umountdisk "$srcDisk" || exit 252
    echo
  fi


rm -f "${destFile}.zip" 2>&1 1>/dev/null
getTimeStamp
echo "[${TS}] Backup process started."
if [ "$(pv -V)" ]
  then
    dd if="$srcDisk" bs="$defaultBS" | pv  --progress --wait --width 79 --size $srcDiskSize | zip -9q | dd of="${destFile}.zip" bs="$defaultBS" || exit 251
  else
    dd if="$srcDisk" bs="$defaultBS" | zip -9q | dd of="${destFile}.zip" bs="$defaultBS" || exit 251
  fi
getTimeStamp
echo -e "[${TS}] Backup complete\n"


sync 2>/dev/null
exit 0
