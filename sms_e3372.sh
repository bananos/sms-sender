#!/bin/bash
# @author Krzysztof Szewczyk
# @description Script to sending sms by Huawei E3372 HiLink (software/firmware: 22.286.03.00.00, webui: 16.100.05.00.03)
# @description Fixed to work on software/firmware: 22.315.01.00.1080, webui: 17.100.13.02.1080
help()
{
	echo "USAGE:
	$(basename $0) -t|--to <dest_number> -m|--message <message> [-i|--ip <ip>] [-a|--accent] [-l|--log <log_file>] [-h|--help]
		-t|--to dest_number
			Receiver phone number or numbers separated by comma (,) eg. +123456789,987654321.
		-m|--message message
			Message to send.
		-i|--ip ip
			[optional] Custom ip of the modem (default is 192.168.8.1).
		-a|--accent
			[optional] Message with international characters. Without it characters like 'ęó' will be changed to 'eo'.
		-l|--log log_file
			[optional] File to logging.
		-h|--help
			Shows this help and exit.
	
	Environment variables:
		SMS_NUMBERS- the same as --to
		SMS_MESSAGE    - the same as --message
		SMS_IP     - the same as --ip
		SMS_ACCENT - any non empty string, the same as --accent
		SMS_LOG    - the same as --log
	Environment variables will be overwritten by command line parameters.

	Exit codes:
		0 - OK
		1 - command line errors
		2 - modem not available
		3 - sending failed

    Examples: 
        ./sms_e3372.sh --to \"+380123456789\" --message \"Test from cmd\""
}


log()
{
	[ -n "$SMS_LOG" ] && echo "$(date +'%F %T') - $@" >> "$SMS_LOG"
}


_exit()
{
	code=$1
	shift
	echo $@ >&2
	log $@
	[ $code = 1 ] && help
	exit $code
}


#
# set up default modem ip if not specified
#

[ -z "$SMS_IP" ] && SMS_IP='192.168.8.1'


#
# parse cmd line
#

while [[ $# > 1 ]] ; do
	key="$1"

	case $key in
	-t|--to)
		SMS_NUMBERS="$2"
		shift
	;;
	-m|--message)
		SMS_MESSAGE="$2"
		shift
	;;
	-i|--ip)
		SMS_IP="$2"
		shift
	;;
	-a|--accent)
		SMS_ACCENT=1
	;;
	-l|--log)
		SMS_LOG="$2"
		shift
	;;
	-h|--help)
		help
		exit 0
	;;
	*)
		_exit 1 unknown option $key
	;;
	esac
	shift # to next key
done

log -------------------------------------
log $0 called by $USER

[ -z "$SMS_NUMBERS" ] && _exit 1 '-t|--to <dest_number> is required!'
[ -z "$SMS_MESSAGE"     ] && _exit 1 '-m|--message <message> is required!'

log SMS_IP=$SMS_IP


#
# check modem availability
#

ping -c 1 -W 1 $SMS_IP &>/dev/null
[ $? != 0 ] && _exit 2 modem $SMS_IP is not available


#
# set up receivers
#

log SMS_NUMBERS=$SMS_NUMBERS
arr=$(echo $SMS_NUMBERS | tr "," "\n")
unset receivers

for phone in $arr ; do
	receivers="$receivers<Phone>$phone</Phone>"
done


#
# get message and remove accent chars
#

shift

if [ -n "$SMS_ACCENT" ] ; then
	log message with accent
	SMS_MESSAGE=$(echo "$SMS_MESSAGE" | iconv -t UTF-8)
else
	log message without accent
	SMS_MESSAGE=$(echo "$SMS_MESSAGE" | iconv -t ASCII//TRANSLIT)
fi


#
# get request tokens
#

# Obtain SessionID and __RequestVerificationToken
SesTokInfo=$(curl "http://192.168.8.1/api/webserver/SesTokInfo" --silent)
SessionID=$(echo "$SesTokInfo" | grep "SessionID=" | cut -b 20-147)
__RequestVerificationToken=$(echo "$SesTokInfo" | grep "TokInfo" | cut -b 10-41)

#echo -e "Got SessionID: $SessionID"
#echo -e "Got __RequestVerificationToken: $__RequestVerificationToken"
       
#
# send sms
#

response=$(curl -X POST "http://$SMS_IP/api/sms/send-sms"\
	-q -s\
	-H "Cookie: SessionID=$SessionID"\
	-H "__RequestVerificationToken: $__RequestVerificationToken"\
	--data "<?xml version=\"1.0\" encoding=\"UTF-8\"?><request><Index>-1</Index><Phones>$receivers</Phones><Sca></Sca><Content>$SMS_MESSAGE</Content><Length>-1</Length><Reserved>-1</Reserved><Date>-1</Date></request>"\
	| sed -n -e 's/.*<response>\(.*\)<\/response>.*/\1/p')


#
# check response
#

log response=$response
[ "$response" != 'OK' ] && echo $response >&2 && exit 4
