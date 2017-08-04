# To bypass default powershell security rules run explicitly as:
#
#   powershell -ExecutionPolicy Bypass "C:\path\to\dynamic-setup.ps1"


# Make sure we're running as Administrator.  (for the background task)
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
	exit
}

$DYNAMIC_DOMAIN="dynamic.name"
$DYNAMIC_API_DOMAIN="api.$DYNAMIC_DOMAIN"
$DYNAMIC_PING_DOMAIN="update.$DYNAMIC_DOMAIN"
$DYNAMIC_PING6_DOMAIN="update6.$DYNAMIC_DOMAIN"

function Dynamic-Resolve {
	Param([string]$type, [string]$hostname, [string]$server)
	try {
		$result = Resolve-DnsName -DnsOnly -Type "$type" -Server "$server" "$hostname" -ErrorAction Stop
		$result | Where-Object Section -eq Answer | ForEach-Object { $_.IPAddress } | Select -First 1
	}
	catch { }
}

echo ".-------------------------------------------."
echo "| Dynamic.name: Automatic Dynamic DNS Setup |"
echo "'-------------------------------------------'"

# Contact the API to create or access a dynamic.name subdomain.
while([string]::IsNullOrEmpty($dynamic_passcode)) {
	try {
		$DYNAMIC_USER = Read-Host -Prompt 'Enter your new or current subdomain (ex. "mysubdomain")'
		$DYNAMIC_PASS = Read-Host -Prompt 'Enter your new or current password'
		$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($DYNAMIC_USER):$($DYNAMIC_PASS)"))
		$headers = @{ Authorization = "Basic $auth" }
		$result = Invoke-WebRequest -Uri "https://$DYNAMIC_API_DOMAIN/create" -Headers $headers
		$DYNAMIC_PASSCODE = $result.Headers.'X-Passcode'
	}
	catch { echo $_.Exception.Message }
}

$DYNAMIC_USER_DOMAIN="$DYNAMIC_USER.$DYNAMIC_DOMAIN"
$DYNAMIC_UPDATE_USER_DOMAIN="$DYNAMIC_PASSCODE.$DYNAMIC_USER_DOMAIN"

echo "[*] Authenticated!"
echo "[*] Your passcode             : $DYNAMIC_PASSCODE"
echo "[*] Your subdomain            : $DYNAMIC_USER_DOMAIN"
echo "[*] Your update subdomain     : $DYNAMIC_UPDATE_USER_DOMAIN"


# Test IPv4/A update capability.
$DYNAMIC_RESOLVE_RESULT = Dynamic-Resolve A $DYNAMIC_UPDATE_USER_DOMAIN $DYNAMIC_PING_DOMAIN
if([string]::IsNullOrEmpty($DYNAMIC_RESOLVE_RESULT)) {
	echo "Sorry, the initial update test failed.  (trying again may work)"
	exit 1
}
echo "[*] Public IPv4 update result : $DYNAMIC_RESOLVE_RESULT"
$DYNAMIC_TASK_NAME="$DYNAMIC_USER_DOMAIN IP Updater"
echo "[*] Attempting to add task    : '$DYNAMIC_TASK_NAME'"
schtasks /create /tn $DYNAMIC_TASK_NAME /ru SYSTEM /tr "nslookup -nosearch -type=A $DYNAMIC_UPDATE_USER_DOMAIN $DYNAMIC_PING_DOMAIN" /sc minute /mo 5


# Test IPv6/AAAA update capability.
$DYNAMIC_RESOLVE_RESULT = Dynamic-Resolve AAAA $DYNAMIC_UPDATE_USER_DOMAIN $DYNAMIC_PING6_DOMAIN
if(-not [string]::IsNullOrEmpty($DYNAMIC_RESOLVE_RESULT)) {
	$DYNAMIC_TASK_NAME="$DYNAMIC_USER_DOMAIN IPv6 Updater"
	echo "[*] Attempting to add task    : '$DYNAMIC_TASK_NAME'"
	schtasks /create /tn $DYNAMIC_TASK_NAME /ru SYSTEM /tr "nslookup -nosearch -type=AAAA $DYNAMIC_UPDATE_USER_DOMAIN $DYNAMIC_PING6_DOMAIN" /sc minute /mo 5
}


# Make sure we leave the window open if windows automatically close.
Read-Host -Prompt "Press Enter to exit"
