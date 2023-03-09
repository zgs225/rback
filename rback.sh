#!/bin/bash

AUTHOR="yuez"
EMAIL="i@yuez.me"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
GRAY='\033[0;37m'
CLEAR='\033[0m'

CONFIG_FILE="config.json"
SYNC_DIR="${HOME}/.rback"
VERBOSE=0
FORCE=0

function l_skip() {
    printf "${GRAY}[SKIP] ${@}${CLEAR}\n"
}

function l_info() {
    echo "[INFO]" $@
}

function l_error() {
    printf "${RED}[ERRO] ${@}${CLEAR}\n"
}

function l_success() {
    printf "${GREEN}[SUCC] ${@}${CLEAR}\n"
}

function l_warn() {
    printf "${YELLOW}[WARN] ${@}${CLEAR}\n"
}

function l_debug() {
    if [ $VERBOSE -eq 1 ]; then
        echo "[DEBU]" $@
    fi
}

function usage() {
    echo "Usage: $0 [options]"
    echo "  -c config_file: specify config file, default is config.json"
    echo "  -F: force to push to remote, default is false"
    echo "  -h: show help"
    echo "  -v: verbose mode"
}

function check_dependencies() {
    l_info "Checking dependencies..."
    if ! command -v jq &> /dev/null; then
        l_error "jq is not installed, please install it first."
        exit 1
    fi
    if ! command -v rclone &> /dev/null; then
        l_error "rclone is not installed, please install it first."
        exit 1
    fi
    l_info "Dependencies check passed."
}

# read config file and generate rclone config by providers of config
function generate_rclone_config() {
    if [ -z "$1" ]; then
        l_error "Rclone config path is empty."
        exit 1
    fi

    rclone_config_path=$1
    l_info "Generating rclone config into ${rclone_config_path}..."
    local providers=$(jq -r '.providers | keys | .[]' $CONFIG_FILE)
    for provider in $providers; do
        local provider_name=$(jq -r ".providers[$provider].name" $CONFIG_FILE)

        if [ -z "${provider_name}" ]; then
            l_error "Provider name is empty, please check your config file."
        fi

        echo "[${provider_name}]" >> $rclone_config_path

        local provider_keys=$(jq -r ".providers[$provider] | keys | .[]" $CONFIG_FILE)
        for key in $provider_keys; do
            if [ "$key" != "name" ]; then
                local value=$(jq -r ".providers[$provider].$key" $CONFIG_FILE)
                echo "$key = $value" >> $rclone_config_path
            fi
        done
    done

    l_info "Rclone config generated."
}

# get sync dir from config file
function get_sync_dir() {
    local sync_dir=$(jq -r '.sync_dir' $CONFIG_FILE)
    if [ -z "${sync_dir}" ] || [ "${sync_dir}" = "null" ]; then
        l_warn "Sync dir is empty, using default sync dir: ${SYNC_DIR}"
    else 
        SYNC_DIR=$(eval "echo ${sync_dir}")
        l_info "Using sync dir: ${SYNC_DIR}"
    fi
    mkdir -p ${SYNC_DIR}
}

function do_backup() {
    local rclone_config_path="$1"
    # read backups from config file
    local backup_keys=$(jq -r '.backups | keys | .[]' $CONFIG_FILE)

    for backup_key in $backup_keys; do
        local dir=$(eval "echo $(jq -r ".backups[$backup_key].local_dir" $CONFIG_FILE)")

        if [ -z "${dir}" ]; then
            l_skip "Local dir is empty, skip."
            continue
        fi

        if [ ! -d "${dir}" ]; then
            l_skip "Local dir ${dir} does not exist, skip."
            continue
        fi

        l_info "Backing up ${dir}..."
        local exclude=$(jq -r ".backups[$backup_key].exclude // [] | .[]" $CONFIG_FILE)
        local include=$(jq -r ".backups[$backup_key].include // [] | .[]" $CONFIG_FILE)
        local provider=$(jq -r ".backups[$backup_key].provider // \"\"" $CONFIG_FILE)
        local path=$(jq -r ".backups[$backup_key].remote_path // \"\"" $CONFIG_FILE)
        local retention=$(jq -r ".backups[$backup_key].retention // \"\"" $CONFIG_FILE)
        local bucket=$(jq -r ".backups[$backup_key].bucket // \"\"" $CONFIG_FILE)

        # make backup dir by provider, path
        local backup_dir="${SYNC_DIR}/${provider}/${path}"
        mkdir -p ${backup_dir}

        local tar_file="${backup_dir}/$(date +%Y-%m-%d-%H-%M-%S).tar.gz"

        if [ -z "${bucket}" ]; then
            l_error "Bucket is empty, please check your config file."
            exit 1
        fi

        if [ -z "${provider}" ] || [ -z "${path}" ]; then
            l_error "Provider or path is empty, please check your config file."
            exit 1
        fi

        if [ -z "${retention}" ]; then
            l_warn "Retention is empty, using default retention: 7"
            retention=7
        fi

        if [ -z "${include}" ]; then
            include="."
        fi

        local exclude_str=""
        for e in $exclude; do
            exclude_str="${exclude_str} --exclude ${e}"
        done

        l_debug "Local dir: ${dir}"
        l_debug "Local archived dir: ${backup_dir}"
        l_debug "Exclude: ${exclude}"
        l_debug "Include: ${include}"
        l_debug "Provider: ${provider}"
        l_debug "Bucket: ${bucket}"
        l_debug "Remote Path: ${path}"
        l_debug "Retention: ${retention}"
        l_debug "Tar file: ${tar_file}"

        # create .tar.gz file using exclude, include from dir
        # log tar command
        l_info "Executing tar -zcvf ${tar_file} -C ${dir} ${exclude_str} ${include}"

        tar -zcf ${tar_file} -C ${dir} ${exclude_str} ${include}

        # keep last $retention backups
        local backups=$(ls ${backup_dir} | sort -r)
        local count=0
        for backup in $backups; do
            if [ $count -ge $retention ]; then
                rm -rf ${backup_dir}/${backup}
                l_info "Remove backup: ${backup}"
            fi
            count=$((count+1))
        done

        # sync to remote
        l_info "Syncing ${backup_dir} to ${provider}:${bucket}/${path}..."

        # check delta of count of local and remote, if delta is too large, skip
        local local_count=$(ls ${backup_dir} | wc -l)
        l_debug "Local count: ${local_count}"

        # if local archive dir is empty, skip
        if [ $local_count -eq 0 ]; then
            l_warn "Local archive dir is empty, skip."
            continue
        fi

        local remote_count=$(rclone ls ${provider}:${bucket}/${path} --config ${rclone_config_path} | wc -l)
        l_debug "Remote count: ${remote_count}"

        local delta=$((local_count - remote_count))

        if [ $retention -lt $remote_count ]; then
            l_warn "Remote count is larger than retention, may decrease retention or delete some backups manually."
            delta=$((delta + (remote_count - retention)))
        fi

        l_debug "Delta: ${delta}"

        if [ $delta -lt -2 ] && [ $FORCE -eq 0 ]; then
            l_warn "Delta is too large, please check your config file or use -F to force sync."
            continue
        fi

        if [ $remote_count -gt 0 ]; then
            # check date of newest local and remote, if delta is too large, skip
            local newest_local=$(ls ${backup_dir} | sort -r | head -n 1)
            local newest_remote=$(rclone ls ${provider}:${bucket}/${path} --config ${rclone_config_path} | sort -r | head -n 1 | awk '{print $2}')
            local newest_local_date=$(date -d "$(echo $newest_local | cut -d'.' -f1 | awk -F - '{print $1"-"$2"-"$3" "$4":"$5":"$6}')" +%s)
            local newest_remote_date=$(date -d "$(echo $newest_remote | cut -d'.' -f1 | awk -F - '{print $1"-"$2"-"$3" "$4":"$5":"$6}')" +%s)
            local date_delta=$((newest_local_date - newest_remote_date))

            l_debug "Newest local: ${newest_local}"
            l_debug "Newest remote: ${newest_remote}"
            l_debug "Newest local date: ${newest_local_date}"
            l_debug "Newest remote date: ${newest_remote_date}"
            l_debug "Date delta: ${date_delta}"

            if [ $date_delta -lt 0 ] && [ $FORCE -eq 0 ]; then
                l_warn "Date delta is too large, please check your config file or use -F to force sync."
                continue
            fi
        fi

        rclone sync ${backup_dir} ${provider}:${bucket}/${path} --config ${rclone_config_path}

        l_success "Backup ${dir} to ${provider}:${bucket}/${path} done."
    done
}

show_usage=0

# get config file opt
while getopts "c:hvF" opt; do
    case $opt in
        c)
            CONFIG_FILE=$OPTARG
            l_info "Using config file: $CONFIG_FILE"
            ;;
        h)
            show_usage=1
            ;;
        v)
            VERBOSE=1
            ;;
        F)
            FORCE=1
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

if [ $show_usage -eq 1 ]; then
    usage
    exit 0
fi

rclone_config_path=$(mktemp)

# check dependencies
check_dependencies
get_sync_dir
generate_rclone_config "${rclone_config_path}"
do_backup "${rclone_config_path}"

# clean generated files
rm -f "${rclone_config_path}"
