#!/bin/bash
# prepare environment for Macs with Jamf Connect already deployed

## Grab all the users with a UID above 500
company_name="your_org_name"
users=$(dscl . -list /Users UniqueID | awk '$2 > 499  {print $1}')
uid_database=”/Library/Application Support/$company_name/.uid_database”

# first determine if this script has already run on this Mac, if so, exit
eval "array=($users)"
# for every user above UID 500 store their uid and username in the .uid_database
for user in "${array[@]}"; do
    if [[ "$user" == *-secureadmin ]] || [[ "$user" == "admin1" ]] || [[ "$user" == "admin2" ]]; then
        echo "$(date) :: ignoring any accounts we do not want to added to this .uid_database"
    else
    	# adding user to the $uid_database file
	user_id=$(id -u "$user")
	# loops through all users and the \n will add a new line to each entry
	printf "${user}","${user_id}"'\n' >> "$uid_database"
    fi
done
