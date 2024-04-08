#!/usr/bin/env bash
###############################################################################
# Last Updated: 19 Sep 2022
###############################################################################
# Reftab Toolkit for Mac

  # defines source of this script

source "$(dirname "$0")/global-var.cfg"

###############################################################################
# Check API Access
###############################################################################

api-check() {
    printf "Checking API Configuration...\n" # Make sure you api.conf file configured with your keys from Reftab
#Check if api conf file exists, if not then create it otherwise 
# [ ! -f $SRC/api.conf ] && echo "$FILE does not exist."
sleep 2

CONF=$SRC/api.conf
    while [ ! -f "$CONF" ]; 
    
    do
        printf "X  No API Configuration Exists !\n"
        sleep 1
        echo "Let's Fix that Up !"
        sleep 1
        osascript -e  'display alert "Please obtain your API keys:" & "\nhttps://www.reftab.com/account#Api" buttons {"Continue"} default button 1' &&
        publickey_input="$(osascript -e 'display dialog "Please enter your Public Key from Reftab:" default answer "" with answer' -e 'text returned of result' 2>/dev/null)" &&
        secretkey_input="$(osascript -e 'display dialog "Please enter your Secret Key from Reftab:" default answer "" with answer' -e 'text returned of result' 2>/dev/null)"
        
    if [ ! -z $publickey_input ]; then
        publickey="PUBLICKEY=\"$publickey_input\""
        echo $publickey > $CONF
        else 
        echo "No Public Key Input"
    fi

    if [ ! -z $secretkey_input ]; then
        secretkey="SECRETKEY=\"$secretkey_input\""
        echo $secretkey >> $CONF
        else
        echo "No Secret Key Input"
    fi
done

#Finished Check - if it didnt exist it does now
printf "✓ API Configuartion Exists, Continuing !\n"
sleep 2
}

###############################################################################
# Get the next available asset tag and update
###############################################################################

get_next_asset_tag() {
    # Pull 'nextasset' info from Reftab API and make a JSON response
    local next_asset_tag=$("$SRC/reftab.sh" -m GET -e "nextasset" | "$SRC/gojq" -r '.next')

    # Check if the value is not empty
    if [ -n "$next_asset_tag" ]; then
        echo "Next available tag is $next_asset_tag"
        # Append and overwrite NEXT_TAG variable in global-var.cfg every time this script is run using sed
        sed -i '' "s/NEXT_TAG=.*/NEXT_TAG=\"$next_asset_tag\"/" "$SRC/global-var.cfg"
        return 0  # Success
    else
        echo "Error: 'next' value not found in JSON"
        return 1  # Failure
    fi
}


###############################################################################
# GET Asset Details
# This Script will find an asset in Reftab
# with the serial number from this device
###############################################################################

get_asset_details() {

## Gather Details of Local PC
serial="$(ioreg -l | grep IOPlatformSerialNumber | sed -e 's/.*\"\(.*\)\"/\1/')"
uuid="$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}')"
hostname=$(hostname -s)
computername=$(networksetup -getcomputername)
CPU=$(system_profiler SPHardwareDataType | grep "Processor Name:" | cut -d':' -f2)

        echo "This information will be used to search Reftab:"
        echo " Serial: $serial "
        echo " Hostname: $hostname "
        echo " UUID: $uuid "

./reftab.sh -m GET -e "assets?limit=1&offset=0&query=77784%7C$serial" >$SRC/asset.json

REFTAB_ASSET=$(cat $SRC/asset.json | $SRC/gojq)
#Pull the 'aid' from the asset.json file as use as a variable '$aid'
aid=$(cat $SRC/asset.json | $SRC/gojq '.[0].aid' | sed 's/"//g')
status=$(cat $SRC/asset.json | $SRC/gojq '.[0].status.name' | sed 's/"//g')
loanee=$(cat $SRC/asset.json | $SRC/gojq '.[0].loanee' | sed 's/"//g')
location=$(cat $SRC/asset.json | $SRC/gojq '.[0].locationName' | sed 's/"//g')
get_next_asset_tag

if [ "$REFTAB_ASSET" == "[]" ]; then
    echo "Asset not found in Reftab"
    echo "Creating Asset in Reftab"
    create_asset_details -q
else
    printf "✓ Asset found in Reftab, Updating !\n"
sleep 3
if [ "$hostname" != "$aid" ]; then
   printf "X Hostname does not match Asset Tag\n\n"
   printf "Current Hostname: $hostname\n"
   printf "The Hostname should be: $aid\n"
   echo "Renaming Device to $aid, please input your password if prompted"
   echo "$aid" | sudo scutil --set ComputerName "$aid" 
   echo "$aid" | sudo scutil --set LocalHostName "$aid"
   echo "$aid" | sudo scutil --set HostName "$aid"
   echo "Renaming Complete"
    else    
   printf "✓ Hostname and Asset Tag match\n Moving on ...\n"
    fi
    printf "Fetched Asset Details\n"
 fi


}



###############################################################################
# Fetch Loanee Info
# - pulls everyone into a single json and filters out the user by email to find the UID
###############################################################################
fetch_loanees(){
printf "looking for user "  
sleep 1 
CONF=$SRC/api.conf
while [ ! -f "$CONF" ]; 
do
    $SRC/api-check
done
user_email="$(osascript -e 'display dialog "Please enter the users email to check out this asset:" default answer "" with answer' -e 'text returned of result' 2>/dev/null)"

# Fetch all loanees
$SRC/reftab.sh -m GET -e "loanees?limit=2000" > $SRC/loanee_list.json

# Filter the results based on the email
uid=$($SRC/gojq -r --arg email "$user_email" '.[] | select(.email == $email) | .uid' $SRC/loanee_list.json)

if [ -n "$uid" ]; then
    echo "UID for $user_email: $uid"
else
    echo "No loanee found with email: $user_email"
fi
}


###############################################################################
# Checkout Asset Function
# - pulls everyone into a single json and filters out the user by email to find the UID
# - Use the uid to checkout the device
###############################################################################
checkout_asset(){
printf "\n Checking device out to user "  
sleep 1
get_asset_details
aid=$(cat $SRC/asset.json | $SRC/gojq '.[0].aid' | sed 's/"//g')

# Gather user's email
user_email="$(osascript -e 'display dialog "Please enter the users email to check out this asset:" default answer "" with answer' -e 'text returned of result' 2>/dev/null)"
if [ ! -z "$user_email" ]; then
    printf "\n Checking $aid out to $user_email"
    
 # Fetch all loanees
$SRC/reftab.sh -m GET -e "loanees?limit=2000" > $SRC/loanee_list.json

# Filter the results based on the email
uid=$($SRC/gojq -r --arg email "$user_email" '.[] | select(.email == $email) | .uid' $SRC/loanee_list.json)

uid=$(printf "%.0f" "$uid" 2>/dev/null)
if [ -z "$uid" ]; then
    echo "Error: Unable to convert uid to an integer."
    exit 1
fi

if [ -n "$uid" ]; then
    echo "UID for $user_email: $uid"
else
    echo "No loanee found with email: $user_email"
fi

else 
    echo "No Email Input"
fi


# Define the loan model
loan_model='{
    "aids": ["'$aid'"],
    "due": "",
    "details": {"title":"'$serial'"},
  "notes": "Checked out by Reftab Agent",
    "loan_uid": '$uid'
}'
echo "UID: $uid"
echo "Email: $user_email"
echo "Loan Model: $loan_model"

# logic to send the loan model to the Reftab API
response=$($SRC/reftab.sh -m POST -e "loans" -b "${loan_model}" 2>&1)

# Check if the loan was successful by looking for the "status" field in the response
if [[ "$response" == *"\"status\":\"out\""* ]]; then
    echo "Loan successful"
    exit 0
elif [[ "$response" == *"Asset is already checked out."* ]]; then
    echo "Asset is already checked out."
    exit 1
else
    echo "Loan failed: $response"
    exit 1
fi
}



###############################################################################
#Update asset
# - pulls everyone into a single json and filters out the user by email to find the UID
###############################################################################
update_asset_details(){
printf "Updating this Asset in Reftab "  
sleep 1 
    ###############################################################################
    # Static Data From Device
    ###############################################################################
    todays_date=$(date +%F)

    ## Gather Details of Local PC
    serial="$(ioreg -l | grep IOPlatformSerialNumber | sed -e 's/.*\"\(.*\)\"/\1/')"
    uuid="$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}')"
    hostname=$(hostname -s)
    computername=$(networksetup -getcomputername)
    CPU=$(sysctl -n machdep.cpu.brand_string)
    #CPU=$(system_profiler SPHardwareDataType | grep "Processor Name:" | cut -d':' -f2)
    RAM=$(system_profiler SPHardwareDataType | grep "Memory:" | cut -d':' -f2 | tr -d "[:space:]")
    LOCAL_IP=$(osascript -e "IPv4 address of (system info)")
    os=$(sw_vers -productName)
    model=$(system_profiler SPHardwareDataType | grep "Model Identifier:" | cut -d':' -f2)
    udid=$(system_profiler SPHardwareDataType | grep "Provisioning UDID:" | cut -d':' -f2)
    screen=$(system_profiler SPDisplaysDataType | grep "Resolution:" | cut -d':' -f2)
    hdd=$(system_profiler SPStorageDataType | grep "Capacity:" | cut -d':' -f2)
    NOTE="Updated by Reftab Agent"
    ###############################################################################
    ###############################################################################
printf ""
                echo "Gathering info on $hostname\n"
                printf "\n"
                sleep 2
            printf "Hostname:$hostname\n"
            printf "Serial:$serial\n"
            printf "UUID:$uuid\n"
            printf "CPU:$CPU\n"
            printf "RAM:$RAM\n"
            printf "Local IP:$LOCAL_IP\n"
            printf "OS:$os\n"
            printf "\n"
            printf "\n"
                echo "searching reftab for $hostname" 

    #Pull info from Reftab API and make a JSON file
            $SRC/reftab.sh -m GET -e "assets/$hostname" &>$SRC/asset_to_update.json

                echo "The device is being updated in Reftab."
                sleep 1

# Update JSON asset file asset.json with new details directly from device
updated_json=$(
  cat "$SRC/asset_to_update.json" \
    | $SRC/gojq ".title=\"$serial\" | .details.uuid=\"$uuid\" | .details.Vendor=\"Apple\" | .details.Manufacturer=\"Apple\" | .details.\"End-User Name\"=\"$USER\" | .details.Model=\"$model\" | .details.\"Screen Size\"=\"$screen\" | .details.\"Serial Number\"=\"$serial\" | .details.Hostname=\"$hostname\" | .details.Processor=\"$CPU\" | .details.\"Operating System\"=\"$os\" | .details.\"IP Address\"=\"$LOCAL_IP\" | .details.\"Physical Memory\"=\"$RAM\" | .details.catName=\"MacBook Pro\" | .notes=\"$NOTE on $todays_date\""
)

                
   # Write the updated JSON back to the file
echo "$updated_json" > "$SRC/asset_to_update.json"

                
    #Push new JSON to Reftab asset
        asset_details=$(cat $SRC/asset_to_update.json)
            $SRC/reftab.sh -m PUT -e "assets/$hostname" -b "${asset_details}" >/dev/null 2>&1
            echo "$hostname has been updated in Reftab"
            sleep 2
            printf "https://www.reftab.com/search?q=$uuid&limiter=keyword"
}


###############################################################################
#Update asset
# - pulls everyone into a single json and filters out the user by email to find the UID
###############################################################################
create_asset_details(){

echo "Next available tag is $NEXT_TAG"
sleep 2
printf "\nCreating new asset in Reftab with $NEXT_TAG "
         
#create new asset JSON payload value using uuid          
            echo $(cat $SRC/create.json | $SRC/gojq ".aid=\"$NEXT_TAG\"") > $SRC/create.json
            

#Finish Tag

   

    ### THIS IS STATIC INFO FOR THE JSON FILE
    ###
    #   Status of Asset - Use statid 
            echo $(cat $SRC/create.json | $SRC/gojq ".status.name=\"In Stores\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".loan_status=\"in\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".statid=51362") > $SRC/create.json
    #   Set Location (clid) & Category (cid)
           echo $(cat $SRC/create.json | $SRC/gojq ".clid=22684") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".cid=28018") > $SRC/create.json
    #   Basic Details of Asset
            echo $(cat $SRC/create.json | $SRC/gojq ".title=\"$serial\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.uuid=\"$uuid\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.Vendor=\"Apple\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.Manufacturer=\"Apple\"") > $SRC/create.json
    #   Required Fields for API creation
            echo $(cat $SRC/create.json | $SRC/gojq ".details.Model=\"$model\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Screen Size\"=\"$screen\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Serial Number\"=\"$serial\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Warranty Expires\"=null") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.Hostname=\"$hostname\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.JIRA_status=\"\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.MDM=\"Update\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.S1=\"Update\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.Processor=\"$CPU\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Operating System\"=\"$os\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Hard Drive Size\"=\"null\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"IP Address\"=\"$LOCAL_IP\"") > $SRC/create.json
            #echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Date Purchased\"=\"\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Purchase Cost\"=\"0\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Physical Memory\"=\"$RAM\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Last Update\"=\"$todays_date\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.catName=\"MacBook Pro\"") > $SRC/create.json
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Device Type\"=\"MacBook Pro\"") > $SRC/create.json
            # Azure ID
            echo $(cat $SRC/create.json | $SRC/gojq ".details.\"Azure AD Device ID\"=\"$azure_id\"") > $SRC/create.json


            #echo $(cat $SRC/create.json | $SRC/gojq ".lid=2070205") > $SRC/create.json
    #   Note   
            echo $(cat $SRC/create.json | $SRC/gojq ".details.notes=\"$NOTE\"") > $SRC/create.json


    
# Pipe New Asset JSON to reftab API and POST a new asset   
    cat $SRC/create.json | $SRC/reftab.sh -m POST -e "assets"
    #cat $SRC/create.json | $SRC/gojq  
echo ""
echo ""
    echo "Creat Function Run, check device in reftab https://www.reftab.com/search?q=$serial&limiter=keyword"   

sleep 5
exit 0
}
