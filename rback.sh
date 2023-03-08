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

function usage() {
    echo "Usage: $0 [options]"
    echo "  -c config_file: specify config file, default is config.json"
    echo "  -h: show help"
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
    l_success "Dependencies check passed."
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

    l_success "Rclone config generated."
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
            l_skip "Backup dir is empty, skip."
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

        if [ ! -z "${include}" ] && [ ! -z "${exclude}" ]; then
            l_error "Include and exclude can not be set at the same time."
            exit 1
        fi

        if [ -z "${include}" ] && [ -z "${exclude}" ]; then
            exclude=".git"
            l_warn "Include and exclude are empty, using default exclude: ${exclude}"
        fi

        if [ -z "${include}" ]; then
            include="."
        fi

        l_info "Local dir: ${dir}"
        l_info "Backup dir: ${backup_dir}"
        l_info "Exclude: ${exclude}"
        l_info "Include: ${include}"
        l_info "Provider: ${provider}"
        l_info "Bucket: ${bucket}"
        l_info "Remote Path: ${path}"
        l_info "Retention: ${retention}"
        l_info "Tar file: ${tar_file}"

        # create .tar.gz file using exclude, include from dir
        # log tar command
        l_info "Executing tar -zcvf ${tar_file} -C ${dir} --exclude ${exclude} ${include}"

        tar -zcf ${tar_file} -C ${dir} --exclude ${exclude} ${include}

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
        rclone sync ${backup_dir} ${provider}:${bucket}/${path} --config ${rclone_config_path}
        l_success "Backup ${dir} to ${provider}:${bucket}/${path} done."
    done
}

show_usage=0

# get config file opt
while getopts ":c:h" opt; do
    case $opt in
        c)
            CONFIG_FILE=$OPTARG
            l_info "Using config file: $CONFIG_FILE"
            ;;
        h)
            show_usage=1
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
