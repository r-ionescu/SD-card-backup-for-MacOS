#!/bin/bash
#
#////////////////////////////////////////////////////////////////////////////////////////////
#
#
#
# SD card backup for MacOS
# https://github.com/r-ionescu/SD-card-backup-for-MacOS/blob/main/sd-backup.sh
# Copyright (C) 2021  Raul Ionescu <raul.ionescu@outlook.com>
#
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
# or https://raw.githubusercontent.com/r-ionescu/SD-card-backup-for-MacOS/main/LICENSE
#
#
#
#////////////////////////////////////////////////////////////////////////////////////////////

set -o pipefail
shopt -s nocasematch

#////////////////////////////////////////////////////////////////////////////////////////////

readonly SCRIPT_VERSION='0.8'
readonly LINE='==============================================================================='
declare tmp="${BASH_SOURCE[0]}"
readonly SCRIPT_PATH="$( cd -- "$(dirname "${tmp}")" >/dev/null 2>&1 ; pwd -P )"
readonly SCRIPT_NAME="${tmp##*/}"
readonly SCRIPT_HEADER="\n${LINE}\n ${SCRIPT_NAME} v${SCRIPT_VERSION} - SD card backup for MacOS \n${LINE}\n"
readonly OS_TYPE="$(uname)"

declare TS _disk disk _imgFile imgFile
declare -i diskSize imgSize

readonly defaultBS='1m'
readonly defaultImgFile="./SD-card.bs${defaultBS}.dd.img"

#////////////////////////////////////////////////////////////////////////////////////////////
#////////////////////////////////////////////////////////////////////////////////////////////
#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_doNotAskForConfirmation
if [[ "$@" =~ "-".*y.* || "$@" =~ "--yes" ]]; then CLI_param_doNotAskForConfirmation="true"; fi
readonly CLI_param_doNotAskForConfirmation

#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_action
if [[ "$@" =~ "-".*r.* || "$@" =~ "--restore" ]]
	then
                CLI_param_action="RESTORE"
	else
                CLI_param_action="BACKUP"
	fi
readonly CLI_param_action

#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_disk
if [[ "$@" =~ --disk[[:space:]]+([^[:space:]]+)([[:space:]]*|$) ]]
	then
		CLI_param_disk="${BASH_REMATCH[1]}"
	fi
readonly CLI_param_disk

#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_file
if [[ "$@" =~ --file[[:space:]]+([^[:space:]]+)([[:space:]]*|$) ]]
	then
		CLI_param_file="${BASH_REMATCH[1]}"
	fi
readonly CLI_param_file

#////////////////////////////////////////////////////////////////////////////////////////////

function SHOW_USAGE()
{
cat <<EOF
USAGE:

  ${SCRIPT_NAME} [--disk disk-device] [--file file-name] [-r] [-y]



      --disk disk-device   SD/USB card, eg: --disk /dev/disk2

      --file file-name     backup file name
                           default value is "${defaultImgFile}"
                           eg: --file ${defaultImgFile}

      -r | --restore       restore to disk from backup file

      -y | --yes           do NOT ask for confirmation for starting

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

cleanup()
{
 if [ "${imgFile}" ]; then rm -f "${imgFile}" 2>&1 1>/dev/null; fi
}
trap cleanup EXIT

#////////////////////////////////////////////////////////////////////////////////////////////

echo -e "${SCRIPT_HEADER}"



if [[ ! $OS_TYPE == 'darwin' ]]
	then
                getTimeStamp
                echo "[${TS}] ERROR - This script is intented to run on MacOS"
                exit 255
	fi



if [[ "$@" =~ -{1,2}h(elp)? ]]
	then
		SHOW_USAGE
		exit 0
	fi



disk="${CLI_param_disk}"
if [[ ! "${disk}" =~ ^/dev/r{0.1}disk[0-9]+ ]]; then disk=''; fi

if [ ! "$disk" ]
        then
                declare -a mountedDisks=($(diskutil list | grep -oE '\/dev\/disk[0-9]+' | sort -u))
                searchDisks 'SD\s+Card\s+Reader' "${mountedDisks[@]}"
                searchDisks 'USB\s+SD\s+Reader'  "${mountedDisks[@]}"
                unset mountedDisks
        fi
if [ ! "$disk" ]
        then
                getTimeStamp
                echo -e "[${TS}] ERROR - Unable to detect SD card automatically.\nPlease specify \"disk-device\" as first parameter of the script.\n"
                SHOW_USAGE
                exit 254
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

imgFile="${CLI_param_file:-$defaultImgFile}"
_imgFile="${imgFile##*/}"
readonly _imgFile imgFile

#////////////////////////////////////////////////////////////////////////////////////////////

printf '%-30s %s\n'   "Action:"        "${CLI_param_action}"
printf '%-30s %s\n'   "Backup file:"   "${imgFile}.zip"
printf '%-30s %s\n'   "Disk:"          "${disk} (${diskSize} bytes)"
echo -e "\n"



if [ ! "${CLI_param_doNotAskForConfirmation}" ]
        then
                read -p "Start ${CLI_param_action} process? " -n 1 -r
                if [[ ! $REPLY =~ ^y$ ]]; then exit 1; fi
                echo -e "\n"
        fi

sync 2>/dev/null

if [ "$(mount | grep "${_disk}")" ]
        then
                getTimeStamp
                echo -e "[${TS}] Unmounting disk ${disk}..."
                diskutil umountdisk "$disk" || exit 252
                echo
        fi

case "${CLI_param_action}" in

       "backup")
               declare -i pidDD pidZIP
               rm -f "${imgFile}"     2>&1 1>/dev/null
               rm -f "${imgFile}.zip" 2>&1 1>/dev/null
               getTimeStamp
               mkfifo "${imgFile}" || exit 251

               if [ "$(pv -V 2>/dev/null)" ]
                       then
                               {
                                       dd if="${disk}" bs="${defaultBS}" | pv  --progress --wait --width 79 --size ${diskSize} | dd of="${imgFile}" bs="${defaultBS}"
                               } 2>&1 &
                       else
                               dd if="${disk}" of="${imgFile}" bs="${defaultBS}" 2>&1 &
                       fi
               pidDD=$!

               if ps -p ${pidDD} 2>&1 1>/dev/null
                       then
                               echo "[${TS}] ${CLI_param_action} process started."
                               zip -q --fifo "${imgFile}.zip" "${imgFile}" &
                               pidZIP=$!
                               while :
                                       do
                                               if ps -p ${pidZIP} 2>&1 1>/dev/null
                                                       then
                                                               if ! ps -p ${pidDD} 2>&1 1>/dev/null
                                                                       then
                                                                               if disown ${pidZIP} 2>&1 1>/dev/null; then kill -9 ${pidZIP} 2>&1 1>/dev/null; fi
                                                                               getTimeStamp
                                                                               echo "[${TS}] ${CLI_param_action} ERROR."
                                                                               exit 250
                                                                       fi
                                                       else
                                                               break
                                                       fi
                                               sleep 1
                                       done
                       else
                               getTimeStamp
                               echo "[${TS}] ${CLI_param_action} ERROR."
                               exit 250
                       fi

                       getTimeStamp
                       echo -e "\n[${TS}] Testing ZIP archive."
                       sync 2>/dev/null
                       if ! zip -vT "${imgFile}.zip"; then exit 249; fi
                       ;;

       "restore")
               getTimeStamp
               echo -e "\n[${TS}] Testing ZIP archive."
               sync 2>/dev/null
               if ! zip -vT "${imgFile}.zip"; then exit 249; fi

               imgSize=$(unzip -l "${imgFile}.zip" | tail -1 | grep -oE '^[0-9]+\s+1\s+file' | grep -oE '^[0-9]+')
               readonly imgSize
               if [ ! "$imgSize" ]
                       then
                               getTimeStamp
                               echo "[${TS}] ERROR - Unsupported archive: ${imgFile}.zip"
                               exit 248
                       fi

               echo
               printf '%-30s %s\n'   "Backup image size:"     "${imgSize} bytes"
               printf '%-30s %s\n'   "Disk size (${disk}):"   "${diskSize} bytes"
               if [ "${imgSize}" -gt "${diskSize}" ]
                       then
                               getTimeStamp
                               echo "[${TS}] ERROR - Disk size too small."
                               exit 247
                       fi

               getTimeStamp
               echo "[${TS}] ${CLI_param_action} process started."
               if [ "$(pv -V 2>/dev/null)" ]
                       then
                               if ! unzip -p "${imgFile}.zip" | pv  --progress --wait --width 79 --size ${imgSize} | dd of="${disk}" bs="${defaultBS}"
                                       then
                                               getTimeStamp
                                               echo "[${TS}] ${CLI_param_action} ERROR."
                                               exit 246
                                       fi
                       else
                               if ! unzip -p "${imgFile}.zip" | dd of="${disk}" bs="${defaultBS}"
                                       then
                                               getTimeStamp
                                               echo "[${TS}] ${CLI_param_action} ERROR."
                                               exit 246
                                       fi
                               fi
                       ;;

       *)
               getTimeStamp
               echo "[${TS}] ERROR - Invalid operation: ${CLI_param_action}"
               exit 2
               ;;
esac

getTimeStamp
echo -e "\n[${TS}] ${CLI_param_action} process finished.\n"
sync 2>/dev/null
exit 0
