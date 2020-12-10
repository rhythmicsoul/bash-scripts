#!/usr/bin/env bash

#### Author: rhythmicsoul
#### Email: rhythmicsoul432@gmail.com
#### Purpose: Script for taking automated backups

main() {
	while getopts "s:d:t:" options; do
		case $options in
			s) SOURCE="${OPTARG}"
			;;
			d) DESTINATION=$(echo "${OPTARG}" | awk '{print $1}')
			;;
			t) BACKUP_TYPE="${OPTARG}"
			;;
		esac
	done

	if [[ -z "${SOURCE}" || -z "${DESTINATION}" || -z "${BACKUP_TYPE}" ]]; then
		usage
		exit 10
	fi

	if ! check_file_dir_existence "${SOURCE}"; then
		(>&2 echo " source file/dir not found in the system.")
		exit 10
	elif ! check_file_dir_existence "${DESTINATION}"; then
		(>&2 echo " destination file/dir not found in the system.")
		exit 10
	fi

	SOURCE="$(remove_trailing_slash "${SOURCE}")"
	DESTINATION="$(remove_trailing_slash "${DESTINATION}")"

	case "${BACKUP_TYPE}" in
		hourly)
			local hourly_destination="${DESTINATION}/hourly/$(date +%F_%H-%M)"

			if [[ -d "${hourly_destination}" ]]; then
				rm -rf "$hourly_destination"
			fi

			mkdir -p "${hourly_destination}"

			if ! start_copy "${SOURCE}" "${hourly_destination}"; then
				(>&2 echo "Making an hourly backup failed.")
				exit 15
			fi

			if ! remove_backup "${DESTINATION}" "hourly"; then
				exit $?
			fi
		;;
		daily)
			local daily_destination="${DESTINATION}/daily/$(date +%F)"

			mkdir -p "${daily_destination}"

			if ! start_copy "${SOURCE}" "${daily_destination}" ; then
				(>&2 echo "Making Daily backup failed.")
				exit 15

			fi

			if ! remove_backup "${DESTINATION}" "daily"; then
				exit $?
			fi

		;;
		weekly)
			if [[ "$(date +%u)" != 7 ]]; then
				(>&2 echo "Weekly Backup Rotate should be scheduled on Sundays only.")
				exit 25
			fi 

			local weekly_destination="${DESTINATION}/weekly/$(date +%F)"

			mkdir -p "${weekly_destination}"

			if ! start_copy "${SOURCE}" "${weekly_destination}"; then
				(>&2 echo "Making Weekly backup failed.")
				exit 15

			fi

			if ! remove_backup "${DESTINATION}" "weekly"; then
				exit $?
			fi

		;;
		monthly)
			if [[ "$(date +%F)" != "$(date +%Y-%m)-01" ]]; then
				(>&2 echo "Monthly Backup Rotate should be scheduled on the 1st day of the month only.")
				exit 26
			fi

			local monthly_destination="${DESTINATION}/monthly/$(date +%F)"

			mkdir -p "${monthly_destination}"

			if ! start_copy "${SOURCE}" "${monthly_destination}"; then
				(>&2 echo "Making Monthly backup failed.")
                                exit 15
			fi

			if ! remove_backup "${DESTINATION}" "monthly"; then
				exit $?
			fi

		;;
		
	esac
}

remove_trailing_slash() {
	local file_dir="${1}"

	for file in ${file_dir}; do
		local new_file_dir="${new_file_dir} $(echo $file | sed 's/\/$//')"
	done

	echo "${new_file_dir/\ /}"
}

start_copy(){
	local source_dir="${1}"
	local dest_dir="${2}"

	for file_dir in ${source_dir}; do 
		if ! /bin/cp -al  "${file_dir}" "${dest_dir}"; then
			return 20
		fi
	done
}

remove_backup(){
	local dest_dir="${1}"
	local backup_type="${2}"

	case "${backup_type}" in
		hourly)
			local time_threshold="$(date -d '24 hour ago' +%s)"
			if [[ ! -d "${dest_dir}/hourly" ]]; then
				(>&2 echo "Error: Destination dir doesn't contains hourly directory.")
				return 17
			fi
		;;
		daily)
			local time_threshold="$(date -d '7 day ago' +%s)"
			if [[ ! -d "${dest_dir}/daily" ]]; then
				(>&2 echo "Error: Destination dir doesn't contains daily directory.")
				return 17
			fi

		;;
		weekly)
			local time_threshold="$(date -d '5 week ago' +%s)"
			if [[ ! -d "${dest_dir}/weekly" ]]; then
				(>&2 echo "Error: Destination dir doesn't contains weekly directory.")
				return 17
			fi

		;;
		monthly)
			local time_threshold="$(date -d '3 month ago' +%s)"
			if [[ ! -d "${dest_dir}/monthly" ]]; then
				(>&2 echo "Error: Destination dir doesn't contains monthly directory.")
				return 17
			fi

		;;
		*) 
			(>&2 echo "Backup type not defined while removing older backups") && return 16
		;;
	esac
	
	for each_dir in ${dest_dir}/${backup_type}/*; do
		b_dirs="$(echo "$each_dir" | awk -F '/' '{print $NF}' | grep -v "\*")"
		local dir_time="${b_dirs}"

		if [[ "${backup_type}" == "hourly" ]]; then
			local day="$(echo "${b_dirs}" | awk -F '_' '{print $1}')"
			local hourly_time="$(echo "${b_dirs}" | awk -F '_' '{print $2}' | sed 's/-/:/')"

			dir_time="${day} ${hourly_time}"
		fi
		
		dir_time="$(date -d "${dir_time}" +%s)"

		if [[ "${dir_time}" -lt "${time_threshold}" ]]; then
			if ! /bin/rm -rvf "${each_dir}"; then
				return 19
			fi
		fi
	done
}

check_file_dir_existence() {
	local file_dir="${1}"
	
	for file in ${file_dir}; do
		if [[ ! -e "${file}" ]]; then
			(>&2 echo -n "${file}")
			return 20
		fi
	done
}

usage(){
cat << EOF
Usage: 
    $0 -s <source_file/dir> -d <destination_file/dir> -type <hourly|daily|weekly|monthly>
EOF
}

main "${@}"
