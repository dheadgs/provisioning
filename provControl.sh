#!/bin/bash
#########################################################
#                                                       #
#                                                       #
#       Simple scirpt to check provisioner/notif        #
#            daemons and restarts if requested          #
#                  gedaskalakis                         #
#                                                       #
#########################################################

function start()
{
provisioner=`pgrep -lf provisioner | head -n1 | cut -d' ' -f1`
notification=`pgrep -lf notification | head -n1 | cut -d' ' -f1`

echo "Killing PID $provisioner for provisioner and PID $notification for notifications"

if [[ -z ${provisioner} && -z ${notification} ]] ; then
	echo "No need to kill anything, restarting daemons"
else
	echo "Killing PIDs"
	/bin/kill $provisioner
	/bin/kill $notification
	#sleep 10 seconds to SIGKILL the PIDs
	echo "Waiting 10 seconds to SIGKILL the PIDs"
	sleep 10
fi

pgrep -lf provisioner   1>/dev/null 2>&1
res=$?
pgrep -lf notification   1>/dev/null 2>&1
res_notif=$?


while (( $res == 1 && $res_notif == 1 )); do
	if [[ ${res} == 1   &&  ${res_notif} == 1 ]] ; then 
		echo "Both daemons are down, restarting..."
		/opt/status/bin/rundeamon -pid curbas_provisioner /opt/status/bin/run_curbas-provisioner
		/opt/status/bin/rundeamon -pid curbas_notifications /opt/status/bin/run_notifications
		echo -e "New PIDs : \n" ;  pgrep -lf provisioner | head -n1 ; pgrep -lf notification | head -n1
		pgrep -lf provisioner   1>/dev/null 2>&1
		res=$?
		pgrep -lf notification   1>/dev/null 2>&1
		res_notif=$?
	elif [[ ${res} == 1   &&  ${res_notif} == 0 ]]; then
		echo "Provisioning daemon is down but Notification is up"
		pgrep -lf provisioner   1>/dev/null 2>&1
		res=$?
		pgrep -lf notification   1>/dev/null 2>&1
		res_notif=$?
	elif [[ ${res} == 0   &&  ${res_notif} == 1 ]]; then
		echo "Provisioning daemon is up but Notification is down"
		pgrep -lf provisioner   1>/dev/null 2>&1
		res=$?
		pgrep -lf notification   1>/dev/null 2>&1
		res_notif=$?
	else
		echo "Both provisioners are up"
		pgrep -lf provisioner   1>/dev/null 2>&1
		res=$?
		pgrep -lf notification   1>/dev/null 2>&1
		res_notif=$?
	fi
done
}


function terminate()
{
provisioner=`pgrep -lf provisioner | head -n1 | cut -d' ' -f1`
notification=`pgrep -lf notification | head -n1 | cut -d' ' -f1`

echo "Killing PID $provisioner for provisioner and PID $notification for notifications"

if [[ -z ${provisioner} && -z ${notification} ]] ; then
	echo "No need to kill anything, daemons are already down"
else
	echo "Killing PIDs"
	/bin/kill $provisioner
	/bin/kill $notification
	#sleep 10 seconds to SIGKILL the PIDs
	echo "Waiting 10 seconds to SIGKILL the PIDs"
	sleep 10
fi

return
}

echo -en "\n"
#echo "******************************"
echo -e '\033[35mThe pending provisioner configurations in Vurbas DB are as follows...:\033[0m'


echo -e '\033[033mPrototype_id - Prototype_name - Number\033[0m'
#echo "select CONCAT(ps.prototype_id, ' ~ ', pro.name, ' ~ ',  count(*)) as Pending_Commands from pservices ps, prototypes pro where pro.id=ps.prototype_id and pending_cmd !=0 group by ps.prototype_id order by ps.prototype_id;" | dbgo
/opt/status/bin/dbrun curbas "select CONCAT(ps.prototype_id, ' ~ ', pro.name, ' ~ ',  count(*)) as Pending_Commands from pservices ps, prototypes pro where pro.id=ps.prototype_id and pending_cmd !=0 group by ps.prototype_id order by ps.prototype_id;" dbprintf "%s \n" 2>/dev/null
echo -en '\n'
#echo -e '\033[033mKlll any "suspicious" prototype_id like 5,10,20,31,23,55,85 etc...\033[0m'
echo -en '\n'
echo -e '\033[35mCount of pending notifications in Vurbas DB is:\033[0m'
echo -e '\033[033mTotal number of em... \033[0m'
/opt/status/bin/dbrun curbas "select a.group_id, a.prototype_id, b.id from received_notifications a left outer join pservices b on a.group_id = b.group_id and a.prototype_id = b.prototype_id where b.id is null;" dbprintf "%s %s\n" 2>/dev/null | awk '{printf("delete from received_notifications where group_id = %s and prototype_id = %s limit 2; \n", $1, $2);}' | wc -l

echo -e '\033[033mIf the notifications are exceeding 200, the script will be auto delete them \033[0m'

notif_count=`/opt/status/bin/dbrun curbas "select a.group_id, a.prototype_id, b.id from received_notifications a left outer join pservices b on a.group_id = b.group_id and a.prototype_id = b.prototype_id where b.id is null;" dbprintf "%s %s\n" 2>/dev/null | awk '{printf("delete from received_notifications where group_id = %s and prototype_id = %s limit 2; \n", $1, $2);}' | wc -l`

if [ ${notif_count} -gt 200 ] ; then 
	/home/gedaskalakis/db_notifications_curbas.sh
	echo -e '\033[033mNew Total: \033[0m'
	/opt/status/bin/dbrun curbas "select a.group_id, a.prototype_id, b.id from received_notifications a left outer join pservices b on a.group_id = b.group_id and a.prototype_id = b.prototype_id where b.id is null;" dbprintf "%s %s\n" 2>/dev/null | awk '{printf("delete from received_notifications where group_id = %s and prototype_id = %s limit 2; \n", $1, $2);}' | wc -l
else
	echo "Pending Notifications are under 200, no actions are taken, proceeding to check pending configurations on pservices"
fi

kill_prototypeforeign=`/opt/status/bin/dbrun curbas "select COUNT(id)   from pservices where pending_cmd !=0 and prototype_id = 83" dbprintf "%s \n"  2>/dev/null`
threshold=0

echo "Foreign number (prototype_id:83) count is $kill_prototypeforeign"
if [[ ${kill_prototypeforeign} -gt ${threshold} ]] ; then
	echo "Foreign number count is $kill_prototypeforeign, deleting the entries"
	echo "select id from pservices where pending_cmd !=0 and prototype_id = 83" | /usr/local/bin/dbgo |awk NF | grep -iv "id\|connect" |  awk '{printf("delete from  pservices  where pending_cmd !=0 and prototype_id = 83 and id = %s limit 1; \n", $1);}' | dbgo	 | grep -iv "id\|connect"   1>/dev/null 2>&1 
	res=$?
	if [ $res == 0 ] ; then
		echo "All ok, deleted the entries!"
	else
		echo "Something went wrong"
	fi

else 
	echo "No pending configurations identified, proceeding to provisioner/notification statuses"
fi

while true; do
    echo -e "\e[31mDo you wish to check, restart or stop Vurbas Provisioner/Notification daemons status?\e[0m"	
    read -t 60 -p "Answer as y/n/restart/down:" ynrestartdown
       case $ynrestartdown in
               [Yy]* ) echo -e "\n"; date; break;;
	       [Nn]* ) echo "Exiting..."; exit;;
	       [RESTARTrestart]*) echo "Restarting both provisioning and Notification daemons"; restart;; 
	       [DOWNdown]*) echo "Stopping both provisioning and Notification daemons"; terminate;;
		* )     echo "No answer, exiting..."; exit;;
	esac
done

#Let's check provisioner status
pgrep -lf provisioner   1>/dev/null 2>&1
res=$?
pgrep -lf notification   1>/dev/null 2>&1
res_notif=$?

if [[ ${res} == 0   && ${res_notif} == 0 ]] ; then
	echo -e "Both provisioner and notifications are up and running:\n" ;  pgrep -lf provisioner | head -n1 ; pgrep -lf notification | head -n1
	echo -e "\nProvisioner is up since:" ; ps afux | grep -i provisioner | grep -iv grep | head -n 1  | awk '{ print $9 }'
	echo "Notifications is up since:" ; ps afux | grep -i notification | grep -iv grep | head -n 1  | awk '{ print $9 }'
elif [[ ${res} == 0   && ${res_notif} == 1 ]] ; then
	echo -e "Provisioner is up but Notifications seems down!" ;  pgrep -lf provisioner | head -n1 ; pgrep -lf notification | head -n1
	echo "Let's restart Notifications!"
	/opt/status/bin/rundeamon -pid curbas_notifications /opt/status/bin/run_notifications
	echo "Restarted" ; pgrep -lf notification | head -n1
elif [[ ${res} == 1   && ${res_notif} == 0 ]] ; then
	echo -e "Provisioner is down but Notifications seems up!" ;  pgrep -lf provisioner | head -n1 ; pgrep -lf notification | head -n1
	echo "Let's restart Provisioner!"
	/opt/status/bin/rundeamon -pid curbas_provisioner /opt/status/bin/run_curbas-provisioner
	echo "Restarted" ; pgrep -lf provisioner | head -n1
else
        echo -e "Provisioner and Notifications are not running! \n Let's initiate them both!"
	/opt/status/bin/rundeamon -pid curbas_notifications /opt/status/bin/run_notifications
	/opt/status/bin/rundeamon -pid curbas_provisioner /opt/status/bin/run_curbas-provisioner
	echo "Restarted both!"	
	echo -e "New PIDs : \n" ;  pgrep -lf provisioner | head -n1 ; pgrep -lf notification | head -n1
fi


echo -e '\033[35mThat is all...\033[0m'
