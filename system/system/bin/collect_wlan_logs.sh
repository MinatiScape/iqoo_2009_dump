#!/system/bin/sh

TAG="cnss_collect_wlan_logs"
# This path should be synced with defination in cnss diag
BASE_DIR="/sdcard/cache/wlan_logs/"
# Post fix for zipped files
POST_FIX=".gz"
# Put zipped file to specified location and will be uploaded
MODULE_LOCATION="/data/logData/modules/"
DEST_LOCATION="/data/logData/modules/2900/"

# No used yet; place holder
EVENT_SUBTYPE="0"

# Command to trigger log dumping(sending SIGTERM to cnss_diag_system)
TRIGGER_CMD="trigger_dump"

function dump_sys_service {
    log -t ${TAG} "dumpsys start ${1}"
    dumpsys wifi > "${1}/wifi.dump"
    dumpsys connectivity > "${1}/connectivity.dump"
    #dumpsys netd > "${1}/netd.dump"
    dumpsys wificond > "${1}/wificond.dump"
    dumpsys network_management > "${1}/network_management.dump"
    logcat -d > "${1}/logcat.log"
}

if [ "$1" == "$TRIGGER_CMD" ]; then
    log -t $TAG "Start dumping wlan logs"
    pid_str=`getprop sys.circulated_wlan_logs.pid`
    kill -15 $pid_str

    sleep 5
    log -t $TAG "Restart circulated wlan logs"
    start circulated_wlan_logs
    return
fi

log -t $TAG "Start collecting wlan logs"
# main starts here
cd $BASE_DIR
# It is not really the correct case to have multiple wlan logs
# But it is safe to take actions in a loop
for file in `ls .`; do
    src_file="$file"
    if [[ $file == *"wlan_logs"* && -d $src_file ]]
    then
        log -t ${TAG} "Handling log files ${src_file}"
        dump_sys_service $file
        tar_file="$file$POST_FIX"
        tar -czf $tar_file $file
        if [ $? -eq 0 ]; then
            # Remove unzipped log files
            rm -rf $file
            if [ $? -eq 0 ]; then
                log -t ${TAG} "rm -rf $file successful"
            else
                log -t ${TAG} "rm -rf $file Failed!"
                exit -1
            fi
        else
            log -t ${TAG} " Failed to tar and zip log files"
            exit -1
        fi

        # Rename log file as cloud diag required:
        # extype_subtype_filecontenthash@TIME.info
        # split file name and get the first token as trigger reason
        arrIN=(${file//_/ })
        reason=${arrIN[0]}
        log -t ${TAG} "Last trigger reason is ${reason}"

        # Hash with seed (imei + time in millisec)
        timestamp=`date +%s%3N`
        imei=`getprop persist.sys.vtouch.imei`
        hash=`echo "$imei$timestamp" | md5sum -b`
        #log -t ${TAG} "imei+time:${imei}${timestamp}"
        #log -t ${TAG} "hash: ${hash}"
        full_name="${reason}_${EVENT_SUBTYPE}_${hash}@${timestamp}.info"
        mv "$tar_file" "$full_name"
        if [ $? -eq 0 ]; then
            log -t ${TAG} "Formated log files: ${full_name}"
        fi

        # TODO: move to cloud and notify
        # Always make sure dest dir exists
        if [ ! -d "$MODULE_LOCATION" ]; then
            mkdir $MODULE_LOCATION -m 777
        fi
        if [ ! -d "$DEST_LOCATION" ]; then
            mkdir $DEST_LOCATION -m 777
        fi
        #mkdir -p $DEST_LOCATION -m 777
        mv $full_name $DEST_LOCATION
        if [ $? != 0 ]; then
            log -t ${TAG} "Failed to move logs to cloud diag modules"
            exit -1
        fi
        full_name=$DEST_LOCATION$full_name
        chmod 777 $full_name
        if [ $? != 0 ]; then
            log -t ${TAG} "Failed to make log $full_name accessible"
            exit -1
        fi

        #Notify cloud app to upload logs
        os_version=`getprop ro.build.version.bbk`
        #cur_date=`date "+%Y-%m-%d %H:%M:%S"`
        cur_date=`date +%s%N`
        #log -t ${TAG} $os_version
        #log -t ${TAG} $cur_date
        #log -t ${TAG} $full_name
        #log -t ${TAG} "data" "{\"moduleid\":\"2900\",\"eventId\":\"00055|012\",\"dt\":{\"exptype\":${reason},\"osysversion\":\"${os_version}\",\"otime\":\"${cur_date}\",\"oapp_version_code\":\"1.0\",\"caller_shell\":\"\",\"caller_pid\":\"\",\"caller_name\":\"\"},\"fullhash\":\"${hash}\",\"logpath\":\"${full_name}\"}"
        am broadcast -a "com.vivo.intent.action.CLOUD_DIAGNOSIS" --ei "attr" 1 --ei "module" 2900 --es "data" "{\"moduleid\":\"2900\",\"eventId\":\"00055|012\",\"dt\":{\"exptype\":${reason},\"osysversion\":\"${os_version}\",\"otime\":\"${cur_date}\",\"oapp_version_code\":\"1.0\",\"caller_shell\":\"\",\"caller_pid\":\"\",\"caller_name\":\"\"},\"fullhash\":\"${hash}\",\"logpath\":\"${full_name}\"}" com.bbk.iqoo.logsystem
        if [ $? -eq 0 ]; then
            log -t ${TAG} "Send broadcast to cloud diag successfully!!"
        fi
    fi
done

