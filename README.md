# uidtool

This document provides instructions on how to incorporate `/usr/local/sbin/uidtool` into a Jamf Connect configuration, with the aim of assigning a unique user ID (UID) to every user logging in through Jamf Connect and storing it in a flat text file for future reference. This deployment is designed to be pushed out to Macs during the initial install of Jamf Connect. *Please see the 'Considerations' section at the end of this document prepare macs with Jamf Connect already deployed*

After assigning a UID, the user's account can be removed from the Mac's internal directory service, while preserving their home folder. This ensures that permissions are aligned correctly for their home folder without prompting the user to update their local account password at login, or if a forced password reset occurs for security purposes.

Upon logout, a script will execute to remove the user's local account, while keeping the home folder intact. The command used is `/usr/bin/dscl . -delete /users/$user`. However, keep in mind that there may be edge cases where a user may hard-power off a Mac where a logout wouldn't occur. If you'd like this to run at reboot as well, you can add the logout script in Jamf Pro as a startup policy scoped to Jamf Connect Macs to run at startup, on-going.

#### *This tool is not intended to be used on Macs with FileVault enabled, its more for a shared lab situation*

## Creating the UIDTool and adding it to a PKG
You can customize this script for the uidtool however you’d like to meet the needs of your organization:

```
#!/bin/bash

######## ABOUT #########
# This tool will start at UID 800 and increment
# for every new user until the end of time
# the uid_database will keep track of the users UID
#
# author: steven russell
# date: May 2024

###### VARIABLES ######
company_name="your_org_name"
uid_database="/Library/Application Support/$company_name/.uid_database"
# The starting ID can be changed to whatever value you'd like
starting_uid="800"

###### MAIN ######
# ensure the company folder exists
if [ -d "/Library/Application Support/$company_name/" ]; then
	mkdir -p "/Library/Application Support/$company_name"
fi

# $1 is passed to this tool from jamfConnect containing the user’s username
# see if the user has an entry
if [ -f "$uid_database" ]; then
    # grabs the uid from the database for the user logging in
    database_uid=$(cat "$uid_database" | grep "$1" | cut -d "," -f2)
    if [ ! -z "$database_uid" ]; then
        echo "$database_uid"
        exit 0
    fi
fi

#find the last UID in the list
if [ -f "$uid_database" ]; then
    last_uid=$(tail -n 1 "$uid_database" | cut -d "," -f2)
    let "next_uid=last_uid+1"
    # this records the uid this users has been assigned
    printf "$1",${next_uid}'\n' >> "$uid_database"
    # this echo command is what tells jamfConnect the UID to use
    echo "$next_uid"
fi

#create the uid_database with the first user and the starting uid
if [ ! -f "$uid_database" ]; then
    printf "$1",${starting_uid}'\n' >> "$uid_database"
    echo "$starting_uid"
fi

exit 0
```

Customize this script however you’d like. This is going to be saved to the `/usr/local/sbin/` directory. Remove `.sh` and make sure the file is only stored as `uidtool`. Set the permissions to:
```
chown root:wheel /usr/local/sbin/uidtool
chmod 755 /usr/local/sbin/uidtool
xattr -c /usr/local/sbin/uidtool 
```
The `xattr` command is to ensure there are no quarantine tags or anything linked to this file you created. Read the `xattr` man page here: https://ss64.com/osx/xattr.html

### Add script to Composer
Use composer and drag this file from that `/usr/local/sbin` location into Composer. 

![Screenshot of Jamf Composer showing the layout of the PKG for uidtool](/composer_uidtool.png?raw=true "Screenshot of Composer")

## Creating the logout hook script for the PKG

```
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
    if [[ "$user" == $admin1 ]] || [[ "$user" == $admin2 ]]; then
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
```

You can choose where to save this file. I have it saved to `/Library/Application Support/$company_name/scripts/`

Run these commands on the file and save it to the location of your choice.
```
chown root:wheel /Library/Application Support/$company_name/scripts/logout.sh
chmod 755 /Library/Application Support/$company_name/scripts/logout.sh
chmod +x /Library/Application Support/$company_name/scripts/logout.sh
xattr -c /Library/Application Support/$company_name/scripts/logout.sh
```

Put this file in the desired location, example above, then drag this to Composer into the same project as the uidtool. 

### postinstall script for the package in Composer
Next, click the triangle disclouse button under the package in Composer to show the "Scripts" folder. Right-click on the folder, choose 'Add Shell Script', and create a postinstall script. Then paste in the script below and modify it for your environment ***must be postinstall*** and add the logout hook in the postinstall for the PKG.

```
#!/bin/bash
## postinstall
# set the loginwindow preference

# set the company name
company_name="your_org_name"

# make sure hte directory exists
if [ ! -d "/Library/Application Support/$company_name/scripts/" ]; then
  mkdir -p "/Library/Application Support/$company_name/scripts/"
fi

# update the preference file
defaults write /var/root/Library/Preferences/com.apple.loginwindow LogoutHook "/Library/Application Support/$company_name/scripts/logout.sh"

# verify
if [ "$(defaults read /var/root/Library/Preferences/com.apple.loginwindow LogoutHook; echo $?)" != 0 ]; then
	echo "root loginwindow LogoutHook successfully updated"
else
	echo "An Unknown Error Occurred"
	exit 1
fi
```

## Configuring the jamfConnect Configuration Profile to use the UIDTool

In the Configuration Profile, add this line to your existing configuration. 

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
...
  <key>UIDTool</key>
  <string>/usr/local/sbin/uidtool</string>
...  
</dict>
</plist>
```

## Considerations:
Typically macOS will start assigning UID’s to local users starting at 501 and increase from there. If you apply this to Macs that already have accounts created and their UIDs are before 800. This will not apply to those accounts. 

If you wanted to roll this out to previously deployed Macs that already have user accounts before UID 800, then we’d need to push out a script that will generate the .uid_database Ahead of time and we’d adjust the script to function on UIDs below 800.

We could create a script to pre-deploy before applying this change that takes the UID of every local account above 501 and add them to the database which would look like this:

```
firstname,501
seconduser,502
thirduser,503
```

I didn’t have to do this in my environment because we rolled this out at the same time we rolled out Jamf Connect so we never had local accounts created without the user added to the `.uid_database` at login. The pre-deploy script could be like this. This is not tested and should be considered as a starting point:

```
#!/bin/bash
# prepare environment for Macs with Jamf Connect already deployed

## Grab all the users with a UID above 500
company_name="your_org_name"
admin1="*-admin" #any admin account ending in -admin
admin2="supercool_admin"
users=$(dscl . -list /Users UniqueID | awk '$2 > 499  {print $1}')
uid_database=”/Library/Application Support/$company_name/.uid_database”

# first determine if this script has already run on this Mac, if so, exit
if [ -f "$uid_database" ]; then
	echo "This pre-deply script has already run on this Mac. The uid_database file is found"
	exit 0
fi

# for every user above UID 500 store their uid and username in the .uid_database
eval "array=($users)"
for user in "${array[@]}"; do
    if [[ "$user" == $admin1 ]] || [[ "$user" == $admin2 ]]; then
        echo "Ignoring any accounts we do not want to added to this .uid_database"
    else
    	# adding user to the $uid_database file
	user_id=$(id -u "$user")
	# loops through all users and the \n will add a new line to each entry
	printf "${user}","${user_id}"'\n' >> "$uid_database"
    fi
done
```

Once this is done you can then deploy the script and the next time the user logs out or the computer reboots it’ll apply the changes.
