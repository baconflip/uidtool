#!/bin/bash

### ABOUT ###############################################################
#   This script is going to run at startup on Jamf Connect Macs
#   It is designed to look for any left over UID > 800 accounts
#   It will remove them and make sure that they can login with their latest password
#
### By steven russell
########################################################################
admin1="*-admin" #any admin account ending in -admin
admin2="supercool_admin"

exec >> /Library/Logs/jamf_logout.log
## Grab all the users with a UID above 800 (my UIDTool will make sure they are UID 800+)
users=$(dscl . -list /Users UniqueID | awk '$2 > 799  {print $1}')
eval "array=($users)"
# for every user above UID 800 remove their dscl entry
for user in "${array[@]}"; do
    # first verify that we are FOR SURE not going to be applying this for our protected users (none should be above 800 UID, but just incase)
    if [[ "$user" == "$admin1" ]] || [[ "$user" == "$admin2" ]]; then
        echo "$(date) :: Startup :: Protected Account Found: $user, skipping"
    else
        /usr/bin/dscl . -delete /Users/$user
        # verify it ran successfully and log it
        if [ $? = 0 ]; then
            echo "$(date) :: Successfully deleted the dscl entry for $user"
        else
            echo "$(date) :: Failed to delete the dscl entry for $user"
        fi
    fi
done
