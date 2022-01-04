#!/bin/bash
#
#////////////////////////////////////////////////////////////////////////////////////////////
#
#
#
#--------------------------------------------------------------------------------------------
# SD card backup for MacOS
#--------------------------------------------------------------------------------------------
# https://github.com/r-ionescu/SD-card-backup-for-MacOS/blob/main/sd-backup.sh
# Copyright (C) 2021  Raul Ionescu <raul.ionescu@outlook.com>
#
#
# An easy to use command line tool for backup/restore SD cards/USB sticks,
# using on-the-fly BZ2 compression.
# Usage scenario example: Raspberry Pi SD card.
#
#
#
# USAGE:
#
#   sd-backup.sh [options in any order]
#
#
#     --file file-name            backup file name, WITHOUT extension
#                                 default value is "SD-backup"
#                                 eg: --file SD-backup
#
#     --disk disk-device          SD/USB card, eg: --disk /dev/disk2
#
#     -s or --skip-archive-test   skip archive testing
#
#     -r or --restore             restore to disk from backup file
#                                 without this parameter, a backup is performed
#
#     -y or --yes                 do NOT ask for confirmation
#                                 (use this with extra precautions)
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

readonly SCRIPT_VERSION='0.9.1'
readonly LINE='-------------------------------------------------------------------------------'
declare tmp="${BASH_SOURCE[0]}"
readonly SCRIPT_PATH="$( cd -- "$(dirname "${tmp}")" >/dev/null 2>&1 ; pwd -P )"
readonly SCRIPT_NAME="${tmp##*/}"
readonly SCRIPT_HEADER="\n${LINE}\n ${SCRIPT_NAME} v${SCRIPT_VERSION} - SD card backup for MacOS \n${LINE}\n"
readonly OS_TYPE="$(uname)"

declare TS _disk disk imgFile
declare -i diskSize imgSize

readonly defaultBS='1m'
readonly defaultImgFileName='SD-backup'
readonly defaultImgFileExtension=".bs${defaultBS}.dd.img"

#////////////////////////////////////////////////////////////////////////////////////////////
#////////////////////////////////////////////////////////////////////////////////////////////
#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_shortOptions
if [[ "$@" =~ [[:space:]]("-"[rsy]+)([[:space:]]|$) ]]
        then
                CLI_param_shortOptions="${BASH_REMATCH[1]}"
        fi
readonly CLI_param_shortOptions

#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_action
if [[ "$@" =~ [[:space:]]"--restore"([[:space:]]|$) || "${CLI_param_shortOptions}" =~ "r" ]]
	then
                CLI_param_action="RESTORE"
	else
                CLI_param_action="BACKUP"
	fi
readonly CLI_param_action

#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_skipArchiveTest
if [[ "$@" =~ [[:space:]]"--skip-archive-test"([[:space:]]|$) || "${CLI_param_shortOptions}" =~ "s" ]]
	then
                CLI_param_skipArchiveTest="true"
	fi
readonly CLI_param_skipArchiveTest

#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_doNotAskForConfirmation
if [[ "$@" =~ [[:space:]]"--yes"([[:space:]]|$) || "${CLI_param_shortOptions}" =~ "y" ]]
        then
                CLI_param_doNotAskForConfirmation="true"
        fi
readonly CLI_param_doNotAskForConfirmation

#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_disk
if [[ "$@" =~ [[:space:]]"--disk"[[:space:]]+([^[:space:]]+)([[:space:]]*|$) ]]
	then
		CLI_param_disk="${BASH_REMATCH[1]}"
	fi
readonly CLI_param_disk

#////////////////////////////////////////////////////////////////////////////////////////////

declare CLI_param_file
if [[ "$@" =~ [[:space:]]"--file"[[:space:]]+([^[:space:]]+)([[:space:]]*|$) ]]
	then
		CLI_param_file="${BASH_REMATCH[1]}"
	fi
readonly CLI_param_file

#////////////////////////////////////////////////////////////////////////////////////////////

function SHOW_USAGE()
{
cat <<EOF
USAGE:

  ${SCRIPT_NAME} [options in any order]


    --file file-name            backup file name, WITHOUT extension
                                default value is "${defaultImgFileName}"
                                eg: --file ${defaultImgFileName}

    --disk disk-device          SD/USB card, eg: --disk /dev/disk2

    -s or --skip-archive-test   skip archive testing

    -r or --restore             restore to disk from backup file
                                without this parameter, a backup is performed

    -y or --yes                 do NOT ask for confirmation
                                (use this with extra precautions)

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

function unmountDisk()
{
 if [ "$(mount | grep "${_disk}")" ]
        then
                getTimeStamp
                echo -e "[${TS}] Unmounting disk ${disk}..."
                diskutil umountdisk "$disk" || exit 254
                echo
        fi
}

#////////////////////////////////////////////////////////////////////////////////////////////

echo -e "${SCRIPT_HEADER}"


if [[ ! $OS_TYPE == 'darwin' ]]
	then
                getTimeStamp
                echo "[${TS}] ERROR - This script is intented to run on MacOS"
                exit 253
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
                exit 252
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
                exit 251
        fi

#////////////////////////////////////////////////////////////////////////////////////////////

imgFile="${CLI_param_file:-$defaultImgFileName}"
if [[ ! "${imgFile}" =~ "/" ]]
        then
                imgFile="./${imgFile}"
        fi
if [[ ! "${imgFile}" =~ ".${diskSize}.${defaultImgFileExtension}"$ ]]
        then
                imgFile="${imgFile}.size-${diskSize}${defaultImgFileExtension}"
        fi
readonly imgFile

#////////////////////////////////////////////////////////////////////////////////////////////

printf '%-30s %s\n'   "Disk:"          "${disk} (${diskSize} bytes)"
printf '%-30s %s\n'   "Backup file:"   "${imgFile}.bz2"
printf '%-30s %s\n'   "Action:"        "${CLI_param_action}"
echo -e "\n"



if [ ! "${CLI_param_doNotAskForConfirmation}" ]
        then
                read -p "Start ${CLI_param_action} process? " -n 1 -r
                if [[ ! $REPLY =~ ^y$ ]]; then exit 1; fi
                echo -e "\n"
        fi


sync 2>/dev/null
unmountDisk


case "${CLI_param_action}" in

       "backup")
                getTimeStamp
                echo "[${TS}] ${CLI_param_action} process started."

                rm -f "${imgFile}.bz2" 2>&1 1>/dev/null

                {
                if [ "$(pv -V 2>/dev/null)" ]
                       then
                               dd if="${disk}" bs="${defaultBS}" | pv  --progress --wait --width 79 --size ${diskSize} | bzip2 --quiet --compress --best --stdout | dd of="${imgFile}.bz2" bs="${defaultBS}"
                       else
                               dd if="${disk}" bs="${defaultBS}" | bzip2 --verbose --compress --best --stdout | dd of="${imgFile}.bz2" bs="${defaultBS}"
                       fi
               } || { getTimeStamp; echo "[${TS}] ${CLI_param_action} ERROR."; exit 250; }


               if [ ! "${CLI_param_skipArchiveTest}" ]
                        then
                               getTimeStamp
                               echo -e "\n[${TS}] Testing archive."
                               sync 2>/dev/null
                               if ! bzip2 --test --verbose "${imgFile}.bz2"; then exit 249; fi
                        fi
               ;;


       "restore")
                if [ ! -f  "${imgFile}.bz2" ]
                        then
                                getTimeStamp
                                echo "[${TS}] ERROR - file not found: \"${imgFile}.bz2\""
                                exit 248
                        fi

                if [ ! "${CLI_param_skipArchiveTest}" ]
                        then
                               getTimeStamp
                               echo -e "\n[${TS}] Testing archive."
                               sync 2>/dev/null
                               if ! bzip2 --test --verbose "${imgFile}.bz2"; then exit 249; fi
                        fi

               if [[ "${imgFile}" =~ '.size-'([0-9]+)"${defaultImgFileExtension}"$ ]]
                        then
                                imgSize="${BASH_REMATCH[1]}"
                        else
                                getTimeStamp
                                echo "[${TS}] Counting uncompressed image size: ${imgFile}.bz2"
                                imgSize=$(bunzip2 --stdout "${imgFile}.bz2" | wc -c)
                        fi
               if [ ! "${imgSize}" ]
                       then
                               getTimeStamp
                               echo "[${TS}] ERROR getting uncompressed image size."
                               exit 247
                       fi
               readonly imgSize


               echo
               printf '%-30s %s\n'   "Uncompressed image size:"   "${imgSize} bytes"
               printf '%-30s %s\n'   "Disk size (${disk}):"       "${diskSize} bytes"
               if [ "${imgSize}" -gt "${diskSize}" ]
                       then
                               getTimeStamp
                               echo "[${TS}] ERROR - Disk size too small."
                               exit 246
                       fi

               getTimeStamp
               echo "[${TS}] ${CLI_param_action} process started."
               {
               if [ "$(pv -V 2>/dev/null)" ]
                        then
                               bzip2 --quiet --decompress --stdout "${imgFile}.bz2" | pv  --progress --wait --width 79 --size ${imgSize} | dd of="${disk}" bs="${defaultBS}"
                        else
                               bzip2 --verbose --decompress --stdout "${imgFile}.bz2" | dd of="${disk}" bs="${defaultBS}"
                        fi
                } || { getTimeStamp; echo "[${TS}] ${CLI_param_action} ERROR."; exit 245; }
               ;;


       *)
               getTimeStamp
               echo "[${TS}] ERROR - Invalid operation: ${CLI_param_action}"
               exit 2
               ;;

esac


sync 2>/dev/null
unmountDisk
getTimeStamp
echo -e "\n[${TS}] ${CLI_param_action} process finished.\n"

exit 0
