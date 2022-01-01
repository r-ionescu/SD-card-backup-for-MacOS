#!/bin/bash

readonly SCRIPT_VERSION='0.5.5'
readonly LINE='==============================================================================='
declare tmp="${BASH_SOURCE[0]}"
readonly SCRIPT_PATH="$( cd -- "$(dirname "${tmp}")" >/dev/null 2>&1 ; pwd -P )"
readonly SCRIPT_NAME="${tmp##*/}"
readonly SCRIPT_HEADER="\n${LINE}\n ${SCRIPT_NAME} v${SCRIPT_VERSION} - SD card backup for MacOS \n${LINE}\n"
readonly OS_TYPE="$(uname)"

declare TS _doNotAskForConfirmation _disk disk _imgFile imgFile
declare -i diskSize

readonly defaultBS='1m'
readonly defaultImgFile="./SD-card.bs${defaultBS}.dd.img"

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

  ${SCRIPT_NAME} [disk-device] [backup-file-name] [-y]

    disk-device          = disk device (SD card, eg: /dev/disk2).
    backup-file-name     = backup file name; default value is "${defaultImgFile}"".
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
 if [ ! "$disk" ]
 	then
		declare md isMatch regexPattern="$1"
		shift
  	declare -a mountedDisks=("$@")

		for md in "${mountedDisks[@]}"
		do
			isMatch=$(diskutil info "$md" 2>/dev/null | grep -oE "${regexPattern}")

			if [ "$isMatch" ]
				then
					disk="$md"
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



disk="$1"
if [[ "$disk" =~ -y ]]
  then
     disk=''
  fi
if [ ! "$disk" ]
  then
    declare -a mountedDisks=($(diskutil list | grep -oE '\/dev\/disk[0-9]+' | sort -u))

		searchDisks 'SD\s+Card\s+Reader' "${mountedDisks[@]}"
		searchDisks 'USB\s+SD\s+Reader' "${mountedDisks[@]}"

		unset mountedDisks
  fi
if [ ! "$disk" ]
then
  getTimeStamp
  echo -e "[${TS}] ERROR - Unable to detect SD card automatically.\nPlease specify \"disk-device\" as first parameter of the script.\n"
  SHOW_USAGE
  exit 254
fi
if [[ ! "$disk" =~ ^/dev/ ]]
  then
    disk="/dev/${disk}"
  fi
disk="${disk/\/dev\/disk//dev/rdisk}"
_disk="${disk/\/dev\/rdisk//dev/disk}"
readonly _disk disk


diskSize=$(diskutil info "$disk" 2>/dev/null | grep -E 'Disk\s+Size' | tr ' ' '\n' | grep -E '\S' | head -5 | tail -1 | grep -oE '[0-9]+')
readonly diskSize
if [ ! "$diskSize" ]
  then
    getTimeStamp
		echo "[${TS}] ERROR - Disk not found: ${disk}"
		exit 253
  fi

#////////////////////////////////////////////////////////////////////////////////////////////

imgFile="${2:-$defaultImgFile}"
if [[ "$imgFile" =~ -y ]]
  then
     imgFile="${defaultImgFile}"
  fi
_imgFile="${imgFile##*/}"
readonly _imgFile imgFile

#////////////////////////////////////////////////////////////////////////////////////////////

printf '%-20s %s\n' "Disk:" "${disk} (${diskSize} bytes)"
printf '%-20s %s\n' "Backup file:" "${imgFile}.zip"
echo


if [ ! "${_doNotAskForConfirmation}" ]
  then
    read -p "Start backup process? " -n 1 -r
    echo -e "\n"
    if [[ ! $REPLY =~ ^y$ ]]; then exit 1; fi
  fi


if [ "$(mount | grep "${_disk}")" ]
  then
    getTimeStamp
    echo -e "[${TS}] Unmounting disk ${disk}..."
    diskutil umountdisk "$disk" || exit 252
    echo
  fi


rm -f "${imgFile}" 2>&1 1>/dev/null
rm -f "${imgFile}.zip" 2>&1 1>/dev/null
getTimeStamp
echo "[${TS}] Backup process started."
mkfifo "${imgFile}" || exit 251
if [ "$(pv -V)" ]
  then
    dd if="${disk}" bs="${defaultBS}" | pv  --progress --wait --width 79 --size $diskSize | dd of="${imgFile}" bs="${defaultBS}" &
  else
    dd if="${disk}" of="${imgFile}" bs="${defaultBS}" &
  fi
zip -9q --fifo "${imgFile}.zip" "${imgFile}" || exit 250
rm -f "${imgFile}" 2>&1 1>/dev/null
getTimeStamp
echo -e "[${TS}] Backup process finished\n"


sync 2>/dev/null
exit 0
