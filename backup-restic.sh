#!/bin/bash

# forked from https://github.com/joltcan/backup-restic

# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.

#exit if sth. fails...
#set -euo pipefail

# Some default variables
ERROR=''
EXCLUDEFILE="$HOME/opt/backup_restic/restic-excludes"

# Now get your vars (and a big description if not)
VARSFILE="$HOME/.config/restic-vars"
if [ -f "$VARSFILE" ]; then
    source $VARSFILE
else
    cat <<EOF

Hello! Restic vars are not set, please create $VARSFILE with the following content:

export RESTIC_PASSWORD="replaceMe"

# Backupvolume
export BACKUPVOLUME=/Volumes/Backup
export VOLUMEUUID=332F312A-A582-4368-9EC1-257A7DBDC76B

# Repofolders
export RESTIC_REPOSITORY=$BACKUPVOLUME/restic-repo
export RESTIC_CACHE_DIR=$BACKUPVOLUME/.restic_caches
export TMPDIR=$BACKUPVOLUME/.restic_tmp

# BackupPath:

# export BACKUPPATH="--one-file-system /Users/johannes/Documents/Make"
export BACKUPPATH="--one-file-system /Users/johannes/ /Volumes/Daten /Volumes/Fotos"

# Excludes:
export EXCLUDEFILE="$HOME/opt/backup_restic/restic-excludes"

# and backend specific ones (I use s3-compatible storage with mautic).
#export AWS_ACCESS_KEY_ID=<s3 access key>
#export AWS_SECRET_ACCESS_KEY=<s3 secret key>

# And unset them at the end of the script!
#export POSTRUN='unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY'

# other options

# prune backups if run between these hours
export PRUNE_START=01
export PRUNE_STOP=05

# Optional: Override cache file location if you want (I put them on fast storage)
#export XDG_CACHE_HOME=/share/Cache/restic
#export TMPDIR=/share/Cache/restic/tmp

# or read the [Restic documentation](http://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html) for more options.

EOF
    exit 1
fi

# try to mount repo volume:

[ -d $BACKUPVOLUME ] && echo "Already mounted $BACKUPVOLUME in OS X" || echo "Not mounted, trying to mount"

if ! [ -d $BACKUPVOLUME ]; then
    echo "mounting $BACKUPVOLUME, UUID: $VOLUMEUUID"
    diskutil mount $VOLUMEUUID
fi
if ! [ -d $BACKUPVOLUME ]; then
    echo "cannot mount $BACKUPVOLUME, exiting"
    exit 1
fi


    echo "trying to mount FotoDisk"
    diskutil mount $FOTODISKUUID
    echo "trying to mount DataDisk"
    diskutil mount $DATADISKUUID


# try to mount second repo Volume:
#osascript -e "try
#	mount volume "$NETWORKVOLUME"
#end try
#"
#if [ $? -eq 0 ]; then
#    echo "second repo location mounted"
#else
#    echo "cannot mount, continuing with only one repo"
#fi

# set some defaults (if the aren't set in restic-vars file)
if [ -z ${ALWAYSUPDATEEXCLUDEFILE+x} ]; then ALWAYSUPDATEEXCLUDEFILE="TRUE"; fi
if [ -z ${BACKUPPATH+x} ]; then BACKUPPATH=$HOME; fi
if [ -z ${CHECK_DOM+x} ]; then CHECK_DOM="02"; fi # check the arkiv if it's this day-of-month
if [ -z ${LOCALEXCLUDE+x} ]; then LOCALEXCLUDE=""; fi
if [ -z ${KEEP_DAILY+x} ]; then KEEP_DAILY=7; fi
if [ -z ${KEEP_WEEKLY+x} ]; then KEEP_WEEKLY=4; fi
if [ -z ${KEEP_MONTHLY+x} ]; then KEEP_MONTHLY=12; fi
if [ -z ${OPTIONS+x} ]; then OPTIONS=" --exclude-caches "; fi # exclude dirs with CACHEDIR.TAG file present (should contain "Signature: 8a477f597d28d172789f06886806bc5")
if [ -z ${POSTRUN+x} ]; then POSTRUN=""; fi
if [ -z ${PRUNE_START+x} ]; then PRUNE_START="00"; fi
if [ -z ${PRUNE_STOP+x} ]; then PRUNE_STOP="24"; fi

# Try to be sensible with notifications. I mainly use this on OSX, but I'm trying to be nice here.
notification() {
    PLATFORM=$(uname)
    if [ "$PLATFORM" == "Darwin" ]; then
        osascript -e "display notification \"$1\" with title \"Restic Error\""
    elif [ "$PLATFORM" == "Linux" ]; then
        if [ -f $(which xmessage) ] && [ ! -z ${DISPLAY} ]; then
            # notify via GUI
            xmessage "Restic error: $1"
        else
            echo "Restic error: $1"
        fi
    else
        # Report to syslog log if nothing else
        echo "Error: Restic: $1" | logger -p ERROR
    fi
}

# Download the excludefile
exclude_file() {
    curl -sSL -f -z $EXCLUDEFILE "https://raw.githubusercontent.com/pcace/backup-restic/master/restic-excludes" -o $EXCLUDEFILE
}

# if we dont' have the excludefile, then it's the first run
if [ ! -f $EXCLUDEFILE ]; then
    # Get the exclude file
    exclude_file $EXCLUDEFILE
fi

# Update the excludefile (default)
[ "$ALWAYSUPDATEEXCLUDEFILE" == "TRUE" ] && exclude_file $EXCLUDEFILE

# Append a local exclude file to options if exist
[ "$LOCALEXCLUDE" != "" ] && OPTIONS+=" --exclude-file=$LOCALEXCLUDE "

case "$1" in
init)
    # make it possible to init here
    restic -r $RESTIC_REPOSITORY init
    ((ERROR += $?))
    ;;

backup)
    # Perform backup
    # always check repo:
    restic check
    if [ $? -eq 0 ]; then
        echo "repo looks good"
    else
        echo "repo does not look good, exiting"
        exit 1
    fi

    # actual Backup
    restic backup $OPTIONS --exclude-file=$EXCLUDEFILE $BACKUPPATH
    # Store there error here, so we can add errors later if needed.
    ((ERROR += $?))
    ;;

check)
    restic check
    ((ERROR += $?))
    ;;

forget)
    restic forget --prune --keep-daily=$KEEP_DAILY --keep-weekly=$KEEP_WEEKLY --keep-monthly=$KEEP_MONTHLY
    ((ERROR += $?))
    ;;

unlock)
    restic unlock
    ((ERROR += $?))
    ;;
prune)
    restic forget --prune --keep-daily=$KEEP_DAILY --keep-weekly=$KEEP_WEEKLY --keep-monthly=$KEEP_MONTHLY
    ((ERROR += $?))
    ;;
*)
    echo "Usage: restic [backup|init|check|forget|prune]"
    exit 1
    ;;
esac

if [ $ERROR -eq 0 ]; then
    # Make sure we only clean old snapshots during night, regardless on when we run backup
    HOUR=$(date +%H)
    if [ $HOUR -gt $PRUNE_START ] && [ $HOUR -lt $PRUNE_STOP ]; then
        restic forget --prune --keep-daily=$KEEP_DAILY --keep-weekly=$KEEP_WEEKLY --keep-monthly=$KEEP_MONTHLY

        # report errors
        if [ $? -ne 0 ]; then
            notification "Restic Prune failed. Please investigate!"
        fi

        # do a check if it's early day of month
        DOM=$(date +%d)
        if [ $DOM -eq $CHECK_DOM ]; then
            restic check

            # Report errors
            if [ $? -ne 0 ]; then
                notification "Restic Check failed. Please investigate!"
            fi
        fi
    fi
else
    notification "Restic Backup failed. Please investigate!"
fi

if [ "$POSTRUN" != "" ] && [ $ERROR -eq 0 ]; then
    echo -n "Running post-script: "
    eval "$POSTRUN"
    echo "Done."
fi

# Clean up:
unset RESTIC_PASSWORD
unset RESTIC_REPOSITORY

# unmount Backupdisk

    echo "everything seems fine, now unmounting $BACKUPVOLUME, UUID: $VOLUMEUUID"
    diskutil umount $VOLUMEUUID
#    echo "trying to unmount FotoDisk"
#    diskutil umount $FOTODISKUUID
#    echo "trying to unmount DataDisk"
#    diskutil umount $DATADISKUUID

# Exit with the error code from above
exit $ERROR
