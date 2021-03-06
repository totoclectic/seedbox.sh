#! /bin/bash

# Bash interface to the PushBullet api.
# Author: Red5d - https://github.com/Red5d

PB_API_KEY="o.nvoAhD9NvdhCFmrAqpbu76VPz2Ab2bq4"  # access token @ https://www.pushbullet.com/#settings
API_URL=https://api.pushbullet.com/v2
PROGDIR="$(cd "$( dirname "$0" )" && pwd )"
 
if [ ! $(which curl) ]; then
	echo "Erreur: pushbullet-bash requires curl to run. Please install curl"
	exit 1
fi

printUsage() {
echo "Usage: pushbullet <action> <device> <type> <data>

Actions:
list - List all devices and contacts in your PushBullet account. (does not require
       additional parameters)
push - Push data to a device or contact. (the device name can simply be
       a unique part of the name that \"list\" returns)
pushes active - List your 'active' pushes (pushes that haven't been deleted).
delete \$iden - Delete a specific push.
delete except \$number - Delete all pushes except the last \$number.
delete all - Delete all pushes.
setup - Use OAuth to retrieve a PushBullet API key for pushbullet-bash.

Types: 
note
link
file

Type Parameters: 
(all parameters must be put inside quotes if more than one word)
\"note\" type: 	give the title and an optional message body.
\"link\" type: 	give the title of the link, an optional message and the url.
\"file\" type: 	give the path to the file and an optional message body.
Hint:  The message body can also be given via stdin, leaving the message parameter empty.
"

}

function getactivepushes () {
	allpushes=$("$PROGDIR"/JSON.sh -l)
	activepushes=$(echo "$allpushes" | egrep "\[\"pushes\",[0-9]+,\"active\"\].*true"|while read line; do echo "$line"|cut -f 2 -d ,; done)
	for id in $activepushes; do
		iden=$(echo "$allpushes" | grep "^\[\"pushes\",$id,\"iden\"\]"|cut -f 2)
		title=$(echo "$allpushes" | grep "^\[\"pushes\",$id,\"title\"\]"|cut -f 2)
		if [[ -z "$title" ]]; then
			title="(no title)"
		fi
		echo "$title $iden"
	done
}

checkCurlOutput() {
	res=$(echo "$1" | grep -o "created" | tail -n1)
	if [[ "$1" == *"The param 'channel_tag' has an invalid value."* ]] && [[ "$1" == *"The param 'device_iden' has an invalid value."* ]]; then
		echo "Erreur: Destination inconnue"
		exit 1
	elif [[ "$res" != "created" ]] && [[ ! "$1" == "{}" ]]; then
		echo "Erreur: Error submitting the request. The error message was:" $1
		exit 1
	fi
	echo -en "\r     \e[32m✓\e[0m Notification push envoyée"
}

case $1 in
list)
	echo "Appareils disponibles :"
	echo "------------------"
	curl -s "$API_URL/devices" -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" | tr ',' '\n' | grep \"nickname\" | sort -n | cut -d '"' -f4
	echo "all"
	echo
	echo "Contacts :"
	echo "------------------"
	curl -s "$API_URL/contacts" -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" | tr ',' '\n' | grep \"email\" | sort -n | cut -d '"' -f4
	;;
pushes)
	case $2 in
	active)
		echo "Push actifs :"
		echo "------------------"
		curl -s "$API_URL/pushes?active=true" -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" | getactivepushes
		;;
	*)
		printUsage
		;;
	esac
	;;
delete)
	case $2 in
	"")
		printUsage
		;;
	all)
		echo "deleting all pushes"
		curlres=$(curl -s "$API_URL/pushes" -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" -X DELETE)
		checkCurlOutput "$curlres"
		;;
	except)
		# test if $3 is not empty and a number
		if [ -z "${3##*[!0-9]}" ]; then
			printUsage
		fi
		echo "deleting all pushes except the last $3"
		number=$(($3+1))
		allpushes=$(curl -s "$API_URL/pushes?active=true" -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" | "$PROGDIR"/JSON.sh -l)
		activepushes=$(echo "$allpushes" | egrep "\[\"pushes\",[0-9]+,\"active\"\].*true"|while read line; do echo "$line"|cut -f 2 -d ,; done | tail -n "+$number")
		for id in $activepushes; do
			iden=$(echo "$allpushes" | grep "^\[\"pushes\",$id,\"iden\"\]"|cut -f 2 | cut -d'"' -f 2)
			$0 delete $iden
		done
		;;
	*)
		echo "deleting $2"
		curlres=$(curl -s "$API_URL/pushes/$2" -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" -X DELETE)
		checkCurlOutput "$curlres"
		;;
	esac
		;;
push)
	if [ -z "$2" ]; then
		printUsage
	fi
	curlres=$(curl -s "$API_URL/devices" -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" )
	devices=$(echo "$curlres" | tr '{' '\n' | tr ',' '\n' | grep \"nickname\" | cut -d'"' -f4)
	idens=$(echo "$curlres" | tr '{' '\n' | grep active\"\:true | tr ',' '\n' | grep iden | cut -d'"' -f4)
	lineNum=$(echo "$devices" | grep -i -n "$2" | cut -d: -f1)
	dev_id=$(echo "$idens" | sed -n $lineNum'p')

	title="$4"
	body=""
	if [ ! -t 0 ]; then
		# we have something on stdin
		body=$(cat)
		# remove unprintable characters, or pushbullet API fails
		body=$(echo "$body"|tr -dc '[:print:]\n')
	fi

	if [[ $5 == http://* ]] || [[ $5 == https://* ]]; then
		url="$5"
	else
		body=${body:-$5}
		url="$6"
	fi

	# replace newlines with an escape sequence
	body="${body//$'\n'/\n}"

	case $3 in
	note)
		type=note
		json="{\"type\":\"$type\",\"title\":\"$title\",\"body\":\"$body\""
	;;
	link)
		type=link
		if [[ ! $url == http://* ]] && [[ ! $url == https://* ]]; then
			echo "Erreur: Error: A valid link has to start with http:// or https://"
            echo "variable concernée: $url"
			exit 1
		fi
		json="{\"type\":\"$type\",\"title\":\"$title\",\"body\":\"$body\",\"url\":\"$url\""
	;;
	file)
		if [[ -z $4 ]] || [[ ! -f $4 ]]; then
			echo "Erreur: Error: no valid file to push was specified"
            echo "variable concernée: $4"
			exit 1
		fi
		# Api docs: https://docs.pushbullet.com/v2/upload-request/
		mimetype=$(file -i -b $4)
		curlres=$(curl -s "$API_URL/upload-request" -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" \
		--data-binary "{\"file_name\":\"$4\",\"file_type\":\"${mimetype%:*}\"}" -X POST)
		curlres2=$(curl -s -i -X POST $(echo $curlres | "$PROGDIR"/JSON.sh -b | grep upload_url |awk -F\" '{print $(NF-1)}') -F file=@$4)

		type=file
		file_name=$(echo $curlres | "$PROGDIR"/JSON.sh -b | grep file_name |awk -F\" '{print $(NF-1)}')
		file_type=$(echo $curlres | "$PROGDIR"/JSON.sh -b | grep file_type |awk -F\" '{print $(NF-1)}')
		file_url=$(echo $curlres | "$PROGDIR"/JSON.sh -b | grep file_url |awk -F\" '{print $(NF-1)}')
		json="{\"type\":\"$type\",\"title\":\"$title\",\"body\":\"$body\",\"file_name\":\"$file_name\",\"file_type\":\"$file_type\",\"file_url\":\"$file_url\""
	;;
	*)
		printUsage
	;;
	esac

	if [ "$2" = "all" ]; then
		echo -ne "   \e[34m➤\e[0m Push à tous les appareils"
		json="$json}"
	# $2 must be a contact/an email address if it contains an @.
	elif [[ "$2" == *@* ]]; then
		echo -ne "   \e[34m➤\e[0m Push à l'adresse mail $2"
		json="$json,\"email\":\"$2\"}"
	# $2 must be a channel_tag if $lineNum is empty.
	elif [ -z "$lineNum" ]; then
		echo -ne "   \e[34m➤\e[0m Push au channel $2"
		json="$json,\"channel_tag\":\"$2\"}"
	# in all other cases $2 must be the identifier of a device.
	else
		echo -ne "   \e[34m➤\e[0m Push vers $2"
		json="$json,\"device_iden\":\"$dev_id\"}"
	fi
	curlres=$(curl -s "$API_URL/pushes" -H "Access-Token: $PB_API_KEY" -H "Content-type: application/json" --data-binary "$json" -X POST)
	checkCurlOutput "$curlres"
;;
setup)
	CLIENT_ID=u1DAx9KcrmMRUjhcMb3qWOZluwE2MjKa
	REDIRECT_URI="https%3A%2F%2Ffbartels.github.io%2Fpushbullet-bash"
	OAUTH_URL="https://www.pushbullet.com/authorize?client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&response_type=token&scope=everything"
	echo
	echo "Please open the following URL manually if it did not open automatically:"
	echo
	echo "$OAUTH_URL"
	echo
	echo "Before continuing you need to save your newly created token in $PB_CONFIG"

	if [ "$(uname)" == "Darwin" ]; then
		open "$OAUTH_URL"
	else
		xdg-open "$OAUTH_URL" &> /dev/null
	fi
;;
ratelimit)
	curl -i -H "Access-Token: $PB_API_KEY" -H "Content-Type: application/json" https://api.pushbullet.com/v2/users/me -sw '%{http_code}'
;;
*)
	printUsage
;;
esac