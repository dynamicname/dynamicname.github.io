#!/bin/sh
#
# Dynamic.name: Automatic Dynamic DNS Setup for UNIX-based environments.
#

DYNAMIC_DOMAIN="dynamic.name"
DYNAMIC_API_DOMAIN="api.$DYNAMIC_DOMAIN"
DYNAMIC_PING_DOMAIN="ping.$DYNAMIC_DOMAIN"
DYNAMIC_PING6_DOMAIN="ping6.$DYNAMIC_DOMAIN"

dynamic_get_credentials() {
	unset DYNAMIC_USER DYNAMIC_PASS
	while [ -z "$DYNAMIC_USER" ] ; do
		printf "Enter your new or current subdomain (ex. \"mysubdomain\"): "
		read DYNAMIC_USER
	done
	while [ -z "$DYNAMIC_PASS" ] ; do
		printf "Enter your new or current password: "
		read DYNAMIC_PASS
	done
}
dynamic_create_curl() {
	HEADERS_OUTFILE=$(mktemp /tmp/dynamic.XXXXXX)
	curl -D "$HEADERS_OUTFILE" https://"$DYNAMIC_USER":"$DYNAMIC_PASS"@"$DYNAMIC_API_DOMAIN"/create
	if [ $? -eq 0 -a -f "$HEADERS_OUTFILE" ]; then
		DYNAMIC_PASSCODE=$(grep X-Passcode "$HEADERS_OUTFILE" | sed 's/.* //' | sed 's/[^a-zA-Z0-9]//g' )
	fi
	rm -f "$HEADERS_OUTFILE" 2>/dev/null
}
dynamic_create_wget() {
	HEADERS_OUTFILE=$(mktemp /tmp/dynamic.XXXXXX)
	wget -SO- https://"$DYNAMIC_USER":"$DYNAMIC_PASS"@"$DYNAMIC_API_DOMAIN"/create 2>"$HEADERS_OUTFILE"
	if [ $? -eq 0 -a -f "$HEADERS_OUTFILE" ]; then
		DYNAMIC_PASSCODE=$(grep X-Passcode "$HEADERS_OUTFILE" | sed 's/.* //' | sed 's/[^a-zA-Z0-9]//g')
	elif [ -f "$HEADERS_OUTFILE" ]; then
		grep -v '^ *$' "$HEADERS_OUTFILE" | tail -1
	fi
	rm -f "$HEADERS_OUTFILE" 2>/dev/null
}
dynamic_create() {
	if dynamic_command_exists curl; then
		dynamic_create_curl
	elif dynamic_command_exists wget; then
		dynamic_create_wget
	else
		echo "Sorry, \"curl\" or \"wget\" must be installed to create dynamic.name accounts."
		exit 1
	fi
}
dynamic_command_exists() {
	type "$1" 1>/dev/null 2>&1
}
dynamic_resolve_nslookup() {
	DYNAMIC_RESOLVE_CMD="nslookup -nosearch -type=$1 $2 $3";
	DYNAMIC_RESOLVE_CMD_EVAL="nslookup -nosearch -type=$1 "$(eval "echo $2")" $3";
	if [ "$3" = "$DYNAMIC_PING6_DOMAIN" ]; then
		DYNAMIC_RESOLVE_RESULT=$($DYNAMIC_RESOLVE_CMD_EVAL 2>&1 | grep -i aaaa | sed 's/.* //')
	else
		DYNAMIC_RESOLVE_RESULT=$($DYNAMIC_RESOLVE_CMD_EVAL 2>&1 | grep -iA2 ^name: | grep -iF address | sed 's/.* //')
	fi
}
dynamic_resolve_host() {
	DYNAMIC_RESOLVE_CMD="host -t $1 $2 $3";
	DYNAMIC_RESOLVE_CMD_EVAL="host -t $1 "$(eval "echo $2")" $3";
	DYNAMIC_RESOLVE_RESULT=$($DYNAMIC_RESOLVE_CMD_EVAL 2>&1 | grep -vi ^address |  grep -i address | grep -vi "not found" | sed 's/.* //')
}
dynamic_resolve() {
	if dynamic_command_exists host; then
		dynamic_resolve_host "$1" "$2" "$3"
	elif dynamic_command_exists nslookup; then
		dynamic_resolve_nslookup "$1" "$2" "$3"
	else
		echo "Sorry, \"host\" or \"nslookup\" must be installed to update your subdomain."
		exit 1
	fi
}


echo ".------------------------------------------."
echo "| Dynamic.name: Automatic Dynamic DNS Setup |"
echo "\`------------------------------------------'"


# Contact the API to create or access a dynamic.name subdomain.
while true; do
	dynamic_get_credentials
	dynamic_create
	if [ ! -z "$DYNAMIC_PASSCODE" ] ; then
		break
	fi
done

DYNAMIC_USER_DOMAIN="$DYNAMIC_USER.$DYNAMIC_DOMAIN"
DYNAMIC_UPDATE_USER_DOMAIN="$DYNAMIC_PASSCODE.$DYNAMIC_USER_DOMAIN"

echo "[*] Authenticated!"
echo "[*] Your passcode             : $DYNAMIC_PASSCODE"
echo "[*] Your subdomain            : $DYNAMIC_USER_DOMAIN"
echo "[*] Your update subdomain     : $DYNAMIC_UPDATE_USER_DOMAIN"


# Use hashcode window logic instead of plaintext passcode?
while [ -z "$DYNAMIC_USE_HASH_WINDOWS" ] ; do
	printf "Use hashcode windows to increase security (requires system time to be accurate) [Y/N]? "
	read CHOICE
	case "$CHOICE" in
		y|Y ) DYNAMIC_USE_HASH_WINDOWS='true';;
		n|N ) DYNAMIC_USE_HASH_WINDOWS='false';;
	esac
done
if [ "$DYNAMIC_USE_HASH_WINDOWS" = "true" ]; then
	if dynamic_command_exists sha1sum; then
		HASH_CMD="sha1sum"
	elif dynamic_command_exists md5sum; then
		HASH_CMD="md5sum"
	elif dynamic_command_exists md5; then
		HASH_CMD="md5"
	else
		HASH_CMD=""
		echo "Sorry, \"sha1sum\", \"md5sum\" or \"md5\" are required to use hashcode windows."
	fi
	if [ ! -z "$HASH_CMD" ]; then
		DYNAMIC_UPDATE_USER_DOMAIN="\$(printf \"$DYNAMIC_PASSCODE:\$(expr \$(date +%s) / 1000)\" | $HASH_CMD | awk '{print \$1\".$DYNAMIC_USER_DOMAIN\"}')"
	fi
fi


# Wipe existing crons that relate to this subdomain?
if ! dynamic_command_exists crontab; then
	echo "Sorry, \"crontab\" is required to create background tasks."
	exit 1
fi

CRON_EXISTS_COUNT=$(crontab -l | grep -iF ".$DYNAMIC_USER_DOMAIN" | wc -l |  sed 's/[^0-9]//g')
if [ "$CRON_EXISTS_COUNT" -gt 0 ]; then
	while [ -z "$DYNAMIC_CRON_WIPE" ] ; do
		printf "$CRON_EXISTS_COUNT cronjob(s) already exist for this subdomain, erase them[Y/N]? "
		read CHOICE
		case "$CHOICE" in
			y|Y ) DYNAMIC_CRON_WIPE='true';;
			n|N ) DYNAMIC_CRON_WIPE='false';;
		esac
	done
fi
if [ "$DYNAMIC_CRON_WIPE" = "true" ]; then
	(crontab -l | grep -viF ".$DYNAMIC_USER_DOMAIN") | crontab -
fi


# Test IPv4/A update capability, add cronjob if applicable.
dynamic_resolve A "$DYNAMIC_UPDATE_USER_DOMAIN" "$DYNAMIC_PING_DOMAIN"
if [ -z "$DYNAMIC_RESOLVE_RESULT" ] ; then
	echo "Sorry, the initial update test failed.  (trying again may work)"
	exit 1
fi
echo "[*] Public IPv4 update result : $DYNAMIC_RESOLVE_RESULT"

CRON_COUNT=0
CRON_EXISTS=$(crontab -l | grep -iF ".$DYNAMIC_USER_DOMAIN" | grep -iF " $DYNAMIC_PING_DOMAIN")
if [ -z "$CRON_EXISTS" ]; then
	(crontab -l; echo "*/5 * * * * $DYNAMIC_RESOLVE_CMD") | crontab -
	CRON_COUNT=$((CRON_COUNT + 1))
fi


# Test IPv6/AAAA update capability, add cronjob if applicable.
dynamic_resolve AAAA "$DYNAMIC_UPDATE_USER_DOMAIN" "$DYNAMIC_PING6_DOMAIN"
if [ ! -z "$DYNAMIC_RESOLVE_RESULT" ] ; then
	echo "[*] Public IPv6 update result : $DYNAMIC_RESOLVE_RESULT"
	CRON_EXISTS=$(crontab -l | grep -iF ".$DYNAMIC_USER_DOMAIN" | grep -iF " $DYNAMIC_PING6_DOMAIN")
	if [ -z "$CRON_EXISTS" ]; then
		(crontab -l; echo "*/5 * * * * $DYNAMIC_RESOLVE_CMD") | crontab -
		CRON_COUNT=$((CRON_COUNT + 1))
	fi
fi


# Show what we did.
echo "[*] Total cronjobs created    : $CRON_COUNT"
