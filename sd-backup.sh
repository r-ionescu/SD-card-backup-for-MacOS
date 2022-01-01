#!/bin/bash

readonly SCRIPT_VERSION='0.2'
readonly LINE='==============================================================================='
declare tmp="${BASH_SOURCE[0]}"
readonly SCRIPT_PATH="$( cd -- "$(dirname "${tmp}")" >/dev/null 2>&1 ; pwd -P )"
readonly SCRIPT_NAME="${tmp##*/}"
readonly SCRIPT_HEADER="\n${LINE}\n ${SCRIPT_NAME} - SD card backup for MacOS v${SCRIPT_VERSION}\n${LINE}\n"

declare TS _hasPV _isSD _isMounted _doNotAskForConfirmation defaultBS _srcDisk srcDisk srcDiskSize destFile defaultDestFile

readonly _hasPV=$(pv -V)
readonly defaultBS='64m'
readonly defaultDestFile="SD-card.bs${defaultBS}.dd.img"

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

srcDisk="$1"
if [[ "$srcDisk" =~ -y ]]
  then
     srcDisk=''
  fi
if [ ! "$srcDisk" ]
  then
    declare md
    declare -a mountedDisks=($(diskutil list | grep -oE '\/dev\/disk[0-9]+' | sort -u))

    for md in "${mountedDisks[@]}"
    do
      _isSD=$(diskutil info "$md" 2>/dev/null | grep -oE 'SD\s+Card')

			if [ "$_isSD" ]
        then
          srcDisk="$md"
          break
        fi
    done
    unset md mountedDisks
  fi
if [ ! "$srcDisk" ]
then
  getTimeStamp
  echo -e "${SCRIPT_HEADER}\n[${TS}] ERROR - Unable to detect SD card automatically.\nPlease specify \"source-device\" as first parameter of the script.\n"
  SHOW_USAGE
  exit 255
fi
if [[ ! "$srcDisk" =~ ^/dev/ ]]
  then
    srcDisk="/dev/${srcDisk}"
  fi
srcDisk="${srcDisk/\/dev\/disk//dev/rdisk}"
_srcDisk="${srcDisk/\/dev\/rdisk//dev/disk}"
_isMounted=$(mount | grep "${_srcDisk}")
readonly _srcDisk _isMounted srcDisk

srcDiskSize=$(diskutil info "$srcDisk" 2>/dev/null | grep -E 'Disk\s+Size' | tr ' ' '\n' | grep -E '\S' | head -5 | tail -1 | grep -oE '[0-9]+')
readonly srcDiskSize
if [ ! "$srcDiskSize" ]
  then
    getTimeStamp
		echo "${SCRIPT_HEADER}\n[${TS}] ERROR - Disk not found: ${srcDisk}"
		exit 254
  fi

#////////////////////////////////////////////////////////////////////////////////////////////

destFile="${2:-$defaultDestFile}"
if [[ "$destFile" =~ -y ]]
  then
     destFile="${defaultDestFile}"
  fi

#////////////////////////////////////////////////////////////////////////////////////////////

echo -e "\n${SCRIPT_HEADER}\n"
printf '%-20s %s\n' "Source disk:" "${srcDisk} (${srcDiskSize} bytes)"
printf '%-20s %s\n' "Destination file:" "${destFile}"
echo
if [ ! "${_doNotAskForConfirmation}" ]
  then
    read -p "Start backup process? " -n 1 -r
    echo -e "\n"
    if [[ ! $REPLY =~ ^y$ ]]; then exit 1; fi
  fi

if [ "${_isMounted}" ]
  then
    getTimeStamp
    echo -e "[${TS}] Unmounting disk ${_srcDisk}..."
    diskutil umountdisk "$srcDisk" || exit 253
    echo
  fi


getTimeStamp
echo "[${TS}] Starting backup..."
if [ "$_hasPV" ]
  then
    dd if="$srcDisk" bs="$defaultBS" | pv -s $srcDiskSize | dd of="$destFile" bs="$defaultBS" || exit 252
  else
    dd if="$srcDisk" of="$destFile" bs="$defaultBS" || exit 252
  fi

getTimeStamp
echo "[${TS}] done"
exit 0
