#!/bin/bash
 
# This can't be run from Jamf. We're just storing it here.
# Download it to your Mac and run it in Terminal.
 
echo "Enter JSS username:"
read USERNAME
echo "Enter JSS password:"
read -s PASSWORD
 
TOKEN_EXPIRATION_EPOCH="0"
 
function getBearerToken() {
    RESPONSE=$(curl -s -u "$USERNAME":"$PASSWORD" "https://jamf.harlemsuccess.org:8443/auth/token" -X POST)
    OS_MAJOR_VERSION=$(sw_vers -buildVersion | cut -c 1-2)
    echo "OS Major Version: $OS_MAJOR_VERSION"
    if [ "$OS_MAJOR_VERSION" -lt 21 ]; then
        # Get the token info
        BEARER_TOKEN=$(echo $RESPONSE | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["token"]')
        # Get the expiration date
        TOKEN_EXPIRATION=$(echo $RESPONSE | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["expires"]')
    # If we are running Monterey or later then we can use plutil to parse json
    else    
        # Get the token info
        BEARER_TOKEN=$(echo "$RESPONSE" | plutil -extract token raw -)    
        # Get the token expiration date
        TOKEN_EXPIRATION=$(echo "$RESPONSE" | plutil -extract expires raw - | awk -F . '{print $1}')
    fi
TOKEN_EXPIRATION_EPOCH=$(date -j -f "%Y-%m-%dT%T" "$TOKEN_EXPIRATION" +"%s")
}
 
function checkTokenExpiration() {
    NOW_EPOCH_UTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
    if [[ TOKEN_EXPIRATION_EPOCH -gt NOW_EPOCH_UTC ]]
    then
        echo "Token valid until the following epoch time: " "$TOKEN_EXPIRATION_EPOCH"
    else
        echo "No valid token available, getting new token"
        getBearerToken
    fi
}
 
function invalidateToken() {
RESPONSE_CODE=$(curl -w "%{http_code}" -H "Authorization: Bearer ${BEARER_TOKEN}" "https://jamf.harlemsuccess.org:8443/api/v1/auth/invalidate-token" -X POST -s -o /dev/null)
if [[ ${RESPONSE_CODE} == 204 ]]
then
echo "Token successfully invalidated"
BEARER_TOKEN=""
TOKEN_EXPIRATION_EPOCH="0"
elif [[ ${RESPONSE_CODE} == 401 ]]
then
echo "Token already invalid"
else
echo "An unknown error occurred invalidating the token"
fi
}
 
echo "Getting API token..."
checkTokenExpiration
 
# Paste in a list of Mac SNs to be removed from management:
 
unmanage=(
C02VQ1P9HX87

)
for SERIAL in ${unmanage[@]}
do
 
# This next commented code is to get the serial number of the Mac from which the script 
# is running in the case of performing the script on this local Mac to remove it from management.
# I've turned it off in favour of using an array of provided SNs of other Macs. See above.
# to remove from management.
 
# Get local serial number:
 
# SERIAL=$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
# /bin/echo "Serial number is $SERIAL"
 
# Get JAMF ID of device from API looked by SN found locally or provided in
# $unmanage array:
JAMF_ID=$(curl -X GET "https://jamf.harlemsuccess.org:8443/JSSResource/computers/serialnumber/$SERIAL" -H "accept: application/xml" -H "Authorization: Bearer $BEARER_TOKEN" | xmllint --xpath '/computer/general/id/text()' -)
 
# API call to de-select "Allow Jamf Pro to perform management tasks" in the JSS for this device:
curl --request PUT --url "https://jamf.harlemsuccess.org:8443/JSSResource/computers/id/$JAMF_ID" -H "Content-Type: application/xml" -H "Accept: application/xml" -H "Authorization: Bearer $BEARER_TOKEN" -d '<computer><general><remote_management><managed>false</managed></remote_management></general></computer>'
 
/bin/echo "JAMF ID for $SERIAL is $JAMF_ID and it is now unmanaged in the JSS"
done
 
# Bin the token
/bin/echo "Invalidating API token..."
invalidateToken
 
/bin/echo "Done."
 
exit 0;
