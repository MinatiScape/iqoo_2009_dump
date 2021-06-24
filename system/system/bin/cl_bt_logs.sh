#!/system/bin/sh

TAG="vivo_cl_bt_logs"

# This path should be synced with defination in cnss diag
#BASE_DIR="/sdcard/cache/bt_logs/"
#BASE_DIR="/data/misc/bluetooth/logs/"
BASE_DIR="/data/logData/modules/bt_log_tmp/"
# this should be sync with bt_snoop.c's path
INNER_BT_SNOOP_FILE_PATH="/data/misc/bluetooth/logs"
SDCARD_BT_SNOOP_FILE_PATH="/data/bbklog/bt_log"
POST_FIX="1.gz"

# Put zipped file to specified location and will be uploaded
MODULE_LOCATION="/data/logData/modules/"
DEST_LOCATION="/data/logData/modules/4000/"
SLEEP_DURATION=15

# Relative props
bt_trigger_reason_prop="sys.vivo.bt_log_trigger_reason"
bt_trigger_err_desc_prop="sys.vivo.bt_log_trigger_err_desc"
bt_trigger_detail_desc_prop="sys.vivo.bt_log_trigger_detail_desc";

function my_print {
    echo "${1}"
    log -t ${TAG} "${1}"
}

function get_logcat_and_snoop_file {
    my_print "dumpsys start ${1}"
    # get logcat log
    logcat -d > "${1}/logcat.log"
    # copy snoop logs from inner and sdcard path
    if [ -d "$INNER_BT_SNOOP_FILE_PATH" ]; then
        cd "$INNER_BT_SNOOP_FILE_PATH"
        for file in `ls .`; do
           cp "${file}" "${1}/${file}"
        done
    fi
    if [ -d "$SDCARD_BT_SNOOP_FILE_PATH" ]; then
        cd "$SDCARD_BT_SNOOP_FILE_PATH"
        for file in `ls .`; do
            cp "${file}" "${1}/${file}"
        done
    fi
    my_print `ls ${1}`
}

function cl_bt_logs {
    # sleep several seconds to make things ready
    my_print "sleep ${SLEEP_DURATION} seconds to make things ready"
    sleep ${SLEEP_DURATION}
    # main starts here
    if [ ! -d "$MODULE_LOCATION" ]; then
        mkdir $MODULE_LOCATION -m 777
    fi
    if [ ! -d "$BASE_DIR" ]; then
        mkdir $BASE_DIR -m 777
    fi
    cd $BASE_DIR
    # clear to get place for the coming log
    rm *
    get_logcat_and_snoop_file $BASE_DIR
    tar_file="$BASE_DIR$POST_FIX"
    rm "$tar_file"
    my_print "current path ls "`ls .`
    my_print "target compress file is $tar_file"
    tar -czf "$tar_file" $BASE_DIR*
    if [ $? -eq 0 ]; then
        # Remove unzipped log files
        my_print `ls .`
    else
        my_print "Failed to tar and zip log files"
        rm "$tar_file"
        exit -1
    fi
    my_print `ls $BASE_DIR`
    # Rename log file as cloud diag required:
    # extype_subtype_filecontenthash@TIME.info
    # split file name and get the first token as trigger reason
    reason=`getprop ${bt_trigger_reason_prop}`
    my_print "Last trigger reason is ${reason}"
    err_desc=`getprop ${bt_trigger_err_desc_prop}`
    my_print "Last trigger reason err_desc is ${err_desc}"
    detail_desc=`getprop ${bt_trigger_detail_desc_prop}`
    my_print "Last trigger reason detail_desc is ${detail_desc}"

    # Start to get the file name as cloud diag required:
    # extype_subtype_filecontenthash@TIME.info
    os_version=`getprop ro.build.version.bbk`
    timestamp=`date +%s%3N`
    imei=`getprop persist.sys.vtouch.imei`

    # depends on the config to choose a hash calc method
    specific_watch_bt=`getprop sys.vivo.specific_watch_bt`
    my_print "specific_watch_bt: ${specific_watch_bt}"
    if [ ${specific_watch_bt} == "true" ];then
        my_print "use imei and timestamp to generate hash"
        hash=`echo "${imei}_${timestamp}" | md5sum -b`
    else
        my_print "use reason err_desc and os_version to generate hash"
        hash=`echo "${reason}_${err_desc}_${os_version}" | md5sum -b`
    fi

    full_name="${reason}_${err_desc}_${hash}@${timestamp}.info"
    my_print "full name: ${full_name}"
    mv "$tar_file" "$full_name"
    if [ $? -eq 0 ]; then
        my_print "Formated log files: ${full_name}"
    fi

    # TODO: move to cloud and notify
    # Always make sure dest dir exists
    if [ ! -d "$MODULE_LOCATION" ]; then
        mkdir $MODULE_LOCATION -m 777
    fi
    if [ ! -d "$DEST_LOCATION" ]; then
        mkdir $DEST_LOCATION -m 777
    fi

    mv $full_name $DEST_LOCATION
    my_print "after mv, go to ${DEST_LOCATION} to see "`ls $DEST_LOCATION`
    if [ $? != 0 ]; then
        my_print "Failed to move logs to cloud diag modules"
        rm $full_name
        exit -1
    fi
    full_name=$DEST_LOCATION$full_name

    chmod 777 $full_name
    if [ $? != 0 ]; then
        my_print "Failed to make log files accessible"
        exit -1
    fi

    #Notify cloud app to upload logs
    os_version=`getprop ro.build.version.bbk`
    #cur_date=`date "+%Y-%m-%d %H:%M:%S"`
    cur_date=`date +%s%N`
    #my_print $os_version
    #my_print $cur_date
    #my_print $full_name
    my_print "data" "{\"moduleid\":\"4000\",\"eventId\":\"00070|012\",\"dt\":{\"exptype\":${reason},\"osysversion\":\"${os_version}\",\"otime\":\"${cur_date}\"},\"fullhash\":\"${hash}\",\"logpath\":\"${full_name}\"}"
    am broadcast -a "com.vivo.intent.action.CLOUD_DIAGNOSIS" --ei "attr" 1 --ei "module" 4000 --es "data" "{\"moduleid\":\"4000\",\"eventId\":\"00070|012\",\"dt\":{\"exptype\":${reason},\"err_desc\":\"${err_desc}\",\"detail_desc\":\"${detail_desc}\",\"osysversion\":\"${os_version}\",\"otime\":\"${cur_date}\"},\"fullhash\":\"${hash}\",\"logpath\":\"${full_name}\"}" com.bbk.iqoo.logsystem
    if [ $? -eq 0 ]; then
        my_print "Send broadcast to cloud diag successfully!!"
    fi
}

my_print "Begin cl bt logs"
cl_bt_logs

