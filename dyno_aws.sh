#!/bin/bash
# Version 2
# Date 6/19/2018 16:59:09

url="https://ip-ranges.amazonaws.com/ip-ranges.json"

timeout=43200
LOG_FILE="$FWDIR/log/dyno_awd.log"

x=0
y=0
z=0

#is_fw_module=$($CPDIR/bin/cpprod_util FwIsFirewallModule)
is_fw_module=1

IS_FW_MODULE=$($CPDIR/bin/cpprod_util FwIsFirewallModule)

MY_PROXY=$(clish -c 'show proxy address'|awk '{print $2}'| grep  '\.')
MY_PROXY_PORT=$(clish -c 'show proxy port'|awk '{print $2}'| grep -E '[0-9]+')
if [ ! -z "$MY_PROXY" ]; then
        HTTPS_PROXY="$MY_PROXY:$MY_PROXY_PORT"
fi

while getopts o:f:u:a:h: option
  do
	case "${option}"
	in	
	o) objName=${OPTARG};;
	u) url=${OPTARG};;
	f) filein=${OPTARG};;
	a) action=${OPTARG};;
	h) dohelp=${OPTARG};;
	?) dohelp=${OPTARG};;
	esac
done

function log_line {
        # add timestamp to all log lines
        message=$1
        local_log_file=$2
        echo "$(date) $message" >> $local_log_file
}
function convert {
	a=0
        for ip in ${addrs[@]} ; do
		a=$a+1
#		echo $ip
		first=$(ipcalc -n $ip | awk -F"=" '{print $2}')
		last=$(ipcalc -b $ip | awk -F"=" '{print $2}')

		laddr=$(echo $first| awk -F"." '{print $4}')
		if [[ "$laddr" -eq 0 ]]; then
			first=$(echo $first| awk -F"." '{print $1"."$2"."$3".1"}')
		fi	
		laddr=$(echo $last| awk -F"." '{print $4}')
		if [[ "$laddr" -eq 255 ]]; then
			last=$(echo $last| awk -F"." '{print $1"."$2"."$3".254"}')
		fi	
		
		#echo $first" - "$last
		#echo ""
		if [[ "$a" -eq 1 ]]; then
                	dynamic_objects -n $objName -r $first $last -a
		
		else
                	dynamic_objects -o $objName -r $first $last -a
		fi
        done

	unset addrs
}

function check_url {
        if [ ! -z $url ]; then
                test_url=$url

                #verify curl is working and the internet access is avaliable
                if [ -z "$HTTPS_PROXY" ]
                then

                        test_curl=$(curl_cli --head -k -s --cacert $CPDIR/conf/ca-bundle.crt --retry 2 --retry-delay 20 $test_url | grep HTTP)
                else
                        test_curl=$(curl_cli --head -k -s --cacert $CPDIR/conf/ca-bundle.crt $test_url --proxy $HTTPS_PROXY | grep HTTP)
                fi

                if [ -z "$test_curl" ]
                then
                        echo "Warning, cannot connect to $test_url"
                        exit 1
                fi
                log_line "done testing http connection" $LOG_FILE
        fi
}


function print_help {
                echo ""
                echo "This script is intended to run on a Check Point Firewall"
                echo ""
                echo "Usage:"
                echo "  dyno_aws.sh <options>"
                echo ""
                echo "Options:"
		echo "  -o			Dynamic Object Name (required)"
               	echo "  -u			url to retrieve IP Address list (optional) "
		echo "				default is https://ip-ranges.amazonaws.com/ip-ranges.json "
		echo "  -f			local file name of IP Address list (optional)"
		echo "  -a			action to perform (required) includes:"
		echo "				run (once), on (schedule), off (from schedule), stat (status)"
		echo "  -h			show help"
                echo ""
                echo ""
}

if [[ "$is_fw_module" -eq 1 && /etc/appliance_config.xml ]]; then
        case "$action" in

                on)
		check_url
		log_line "adding dynamic object $objName to cpd_sched " $LOG_FILE
                $CPDIR/bin/cpd_sched_config add $objName -c "$CPDIR/bin/dyno_aws.sh" -v "-a run -o $objName $optin" -e $timeout -r -s
                log_line "Automatic updates of $onjName is ON" $LOG_FILE
                ;;

                off)
		log_line "Turning off dyamic object updates for $objName" $LOG_FILE
                $CPDIR/bin/cpd_sched_config delete $objName -r
                remove_existing_sam_rules
                log_line "Automatic updates of $objName is OFF" $LOG_FILE
                ;;

                stat)
                cpd_sched_config print | awk 'BEGIN{res="OFF"}/Task/{flag=0}/'$objName'/{flag=1}/Active: true/{if(flag)res="ON"}END{print "'$objName' list status is "res}'
		;;
				
		run)
		log_line "running update of dyamic object $objName" $LOG_FILE
		check_url
		if [ -z "$url" ]
		then
			cat "$filein" | dos2unix | convert
		else
			if [ -z "$HTTPS_PROXY" ]
	                then
        	                $(curl_cli -k -s --cacert $CPDIR/conf/ca-bundle.crt --retry 10 --retry-delay 60 $url -o /var/tmp/ip-ranges.json )
                	else
                        	ipranges=`curl_cli -k -s --cacert $CPDIR/conf/ca-bundle.crt --retry 10 --retry-delay 60 $url --proxy $HTTPS_PROXY `
			fi

			addrs=$(jq '.prefixes[].ip_prefix'  /var/tmp/ip-ranges.json -r )
			convert
			logProds+=$objName" "$addrsLen" ranges updated\n"
		        log_line "update of dynamic object $objName completed" $LOG_FILE
		fi
		log_line "update of dyamic object $objName completed" $LOG_FILE
		;;
				
                *)
		print_help
	esac

fi
#	rmfile=$(rm -rf /var/tmp/ip-ranges.json)
echo -e $logProds