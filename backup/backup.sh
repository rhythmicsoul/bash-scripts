#!/usr/bin/env bash

#### Author: rhythmicsoul
#### Email: rhythmicsoul432@gmail.com
#### Purpose: Script for taking automated backups

check_file_exists() {
    local conf_file=$1
    if [ ! -f $conf_file ];then
        (>&2 echo "${conf_file} does not exisits! Exiting backup") && exit 10
    fi
}

check_file_permission() {
    local conf_file=$1
    if [[ $(stat -c "%a" ${conf_file}) != "600" ]];then
       (>&2 echo "The permission of configuration file should be 600") && exit 15
    fi
}

check_bin() {
    local bin_name="${1}"
    if ! which "${bin_name}" &> /dev/null; then
        (>&2 echo "${bin_name} Command not found!") && exit 30
    fi
}


parse_config() {
    local conf_file=$1
    
    BACKUP_SERVER=$(grep "BACKUP_SERVER" ${conf_file} | grep -vE "^#|^$" | awk -F "BACKUP_SERVER=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    BACKUP_USER=$(grep "BACKUP_USER" ${conf_file} | grep -vE "^#|^$" | awk -F "BACKUP_USER=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    BACKUP_PASSWORD=$(grep "BACKUP_PASSWORD" ${conf_file} | grep -vE "^#|^$" | awk -F "BACKUP_PASSWORD=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    BACKUP_DIRS=$(grep "BACKUP_CONTENTS" ${conf_file} | grep -vE "^#|^$" | awk -F "BACKUP_CONTENTS=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    BACKUP_MODULE=$(grep "BACKUP_MODULE" ${conf_file} | grep -vE "^#|^$" | awk -F "BACKUP_MODULE=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    CRONTAB=$(grep "CRONTAB" ${conf_file} | grep -vE "^#|^$" | awk -F "CRONTAB=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    BACKUP_STAGING_AREA=$(grep "BACKUP_STAGING_AREA" ${conf_file} | grep -vE "^#|^$" | awk -F "BACKUP_STAGING_AREA=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    EMAIL_ADDRESS=$(grep "EMAIL_ADDRESS" ${conf_file} | grep -vE "^#|^$" | awk -F "EMAIL_ADDRESS=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    EMAIL_TEMPLATE_LOCATION=$(grep "EMAIL_TEMPLATE_LOCATION" ${conf_file} | grep -vE "^#|^$" | awk -F "EMAIL_TEMPLATE_LOCATION=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    LOG_FILE=$(grep "LOG_FILE" ${conf_file} | grep -vE "^#|^$" | awk -F "LOG_FILE=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    LOG_ERROR_FILE=$(grep "LOG_ERROR_FILE" ${conf_file} | grep -vE "^#|^$" | awk -F "LOG_ERROR_FILE=" '{print $2}' | sed 's/^"//' | sed 's/"$//')

    MYSQLDB=$(grep "MYSQLDB" ${conf_file} | grep -vE "^#|^$" | awk -F "=" '{print $2}' | sed 's/^"//' | sed 's/"$//') 

    if [[ "${MYSQLDB}" == "yes" ]]; then
        DB_NAME=$(grep "DB_NAME" ${conf_file} | grep -vE "^#|^$" | awk -F "DB_NAME=" '{print $2}' | sed 's/^"//' | sed 's/"$//')
        DB_USER=$(grep "DB_USER" ${conf_file} | grep -vE "^#|^$" | awk -F "DB_USER=" '{print $2}' | sed 's/^"//' | sed 's/"$//')
        DB_PASSWORD=$(grep "DB_PASSWORD" ${conf_file} | grep -vE "^#|^$" | awk -F "DB_PASSWORD=" '{print $2}' | sed 's/^"//' | sed 's/"$//')
    fi

    echo $BACKUP_SERVER $BACKUP_USER $BACKUP_PASSWORD $BACKUP_DIRS $BACKUP_MODULE $CRONTAB $BACKUP_STAGING_AREA $EMAIL_TEMPLATE_LOCATION $EMAIL_ADDRESS $LOG_FILE $LOG_ERROR_FILE $MYSQLDB $DB_USER $DB_PASSWORD $DB_NAME
}

initialize_backup_staging() {
    mkdir -p "${BACKUP_STAGING_AREA}"
}

mysql_dump() {
    local db_user=$1
    local db_password=$2
    local db_name=$3

    echo $db_user $db_pasword $db_name

    if [ ! -z "${db_user}" ] && [ ! -z "${db_password}" ] && [ ! -z "${db_name}" ]; then
        check_bin "mysqldump"
        echo tst
        mkdir -p "${BACKUP_STAGING_AREA}/mysql"    


        mysqldump -u "${db_user}" -p${db_password} "${db_name}" > "${BACKUP_STAGING_AREA}/mysql/${db_name}-$(date +%F).mysql"
        
        if [[ $? == 0 ]]; then
            check_bin "gzip"
            gzip -f "${BACKUP_STAGING_AREA}/mysql/"*".mysql"
        else
            (>&2 echo "Mysqldump failed for ${db_name}."); return 10
        fi
    else
        (>&2 echo "Mysql DB parameters missing in config"); return 10
    fi

    #Deletes mysqldump backups older than 2 days
    find "${BACKUP_STAGING_AREA}/mysql" -mtime +2 -exec rm -f {} \;
}

mysql_backup() {
    mysql_dump "${DB_USER}" "${DB_PASSWORD}" "${DB_NAME}" && \
    start_backup "${BACKUP_STAGING_AREA}" || \
    return 10
}

files_directory_backup() {
    local backup_dirs=$1

    start_backup "${backup_dirs}"
}

crontab_backup() {
    local crontab_dirs="/etc/cron* /var/spool/cron"

    start_backup "${crontab_dirs}" || return 40
}

start_backup() {
    local backup_dirs="${1}"
    local dry_run_flag=""
    export RSYNC_PASSWORD="${BACKUP_PASSWORD}"
    echo "start: $1"

    check_bin "rsync"    

    if [[ ${dry_run_flag} != "DRY_RUN" ]]; then
        rsync -avR --partial --delete-after ${backup_dirs} "${BACKUP_USER}@$BACKUP_SERVER::${BACKUP_MODULE}" || return 20
    else
        rsync -anvR --partial --delete-after ${backup_dirs} "${BACKUP_USER}@$BACKUP_SERVER::${BACKUP_MODULE}" || return 20
    fi
}

email_template() {
    local to_address="${1}"
    local success_status="${2}"

    if [[ ${success_status} == "Success" ]]; then
        cat << EOF > "${EMAIL_TEMPLATE_LOCATION}"
From: Backup <backup@mos.com.np>
To: Server MOS <${to_address}>
Subject: Backup of $(hostname) Sucessful
Backup of $(hostname) completed successfully at $(date "+%F %H:%M:%S"). Please check the logs for a detailed description located at "${LOG_FILE}"


EOF

    elif [[ ${success_status} == "Fail" ]]; then
        cat << EOF > "${EMAIL_TEMPLATE_LOCATION}"
From: Backup <backup@mos.com.np>
To: Server MOS <${to_address}>
Subject: Backup of $(hostname) Failed
Backup of $(hostname) failed  at $(date "+%F %H:%M:%S"). Please check the logs for a detailed description located at "${LOG_ERROR_FILE}"


EOF
        cat "${LOG_ERROR_FILE}" >> "${EMAIL_TEMPLATE_LOCATION}"

    fi
}

backup_success_email() {
    local backup_log_file="${1}"

    email_template "${EMAIL_ADDRESS}" "Success"

    send_email "${EMAIL_TEMPLATE_LOCATION}" "${EMAIL_ADDRESS}"
}

backup_fail_email() {
    local backup_log_file="${1}"

    email_template "${EMAIL_ADDRESS}" "Fail"

    send_email "${EMAIL_TEMPLATE_LOCATION}" "${EMAIL_ADDRESS}"
}

send_email() {
    local email_file="${1}"
    local to_address="${2}"

    check_bin "sendmail"

    cat "${email_file}" | sendmail -r "backup@mos.com.np" "${to_address}"
}

main() {
    local error_flag="false"
    while getopts "c:" opt; do
        case $opt in
            c)
                check_file_exists "$OPTARG"
                check_file_permission "$OPTARG"
                parse_config "$OPTARG"
            ;;
        esac
    done

    cat /dev/null > "${LOG_FILE}"
    cat /dev/null > "${LOG_ERROR_FILE}"

    start_backup "${BACKUP_DIRS}" >> "${LOG_FILE}" 2>> "${LOG_ERROR_FILE}" || error_flag="true"

    if [[ "${CRONTAB}" == "yes" ]]; then
        crontab_backup >> "${LOG_FILE}" 2>> "${LOG_ERROR_FILE}" || error_flag="true"
    fi

    if [[ "${MYSQLDB}" == "yes" ]]; then
        mysql_backup >> "${LOG_FILE}" 2>> "${LOG_ERROR_FILE}"  || error_flag="true"
    fi


    if [[ "${error_flag}" != "true" ]]; then
        backup_success_email 
    else
        backup_fail_email
    fi
}

main "${@}"
