#!/bin/bash
LC_ALL='C'

SCRIPTSDIR=$(dirname "$(readlink -f "$0")")
PROJECTDIR=$(dirname "$SCRIPTSDIR")
CONFIGFILE="$PROJECTDIR/config.yaml"
RESOURCES="$PROJECTDIR/resources"
CUSTOMRULES="$PROJECTDIR/rules"
HOSTRESOURCES="$RESOURCES/hostSources"
RULERESOURCES="$RESOURCES/ruleSources"
HOSTSRESULT="$RESOURCES/hosts"
RULESRESULT="$RESOURCES/rules"
EXCLUDEFILE="$CUSTOMRULES/hosts"
source "$CONFIGFILE"

log() {
	local log_type=$1
	local message=$2
	local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
	case $log_type in
	"info")
		echo -e "[$timestamp] [\e[32mINFO\e[0m] $message"
		;;
	"warning")
		echo -e "[$timestamp] [\e[33mWARNING\e[0m] $message"
		;;
	"error")
		echo -e "[$timestamp] [\e[31mERROR\e[0m] $message"
		;;
	*)
		echo -e "[$timestamp] [\e[31mERROR\e[0m] Unknown log type: $log_type"
		exit 1
		;;
	esac
}

checkPackageManager() {
	local package_managers=("yum" "dnf" "apt" "zypper" "pacman")
	for manager in "${package_managers[@]}"; do
		if [ -n "$(command -v $manager)" ]; then
			echo "$manager"
			return
		fi
	done
}

checkPackages() {
	local packages_to_install=""
	local software_commands=("yq - yq")
	local package_manager=$(checkPackageManager)
	for software_cmd in "${software_commands[@]}"; do
		software_name=$(echo "$software_cmd" | cut -d' ' -f1)
		command_to_check=$(echo "$software_cmd" | cut -d' ' -f3)
		if ! [ -n "$(command -v $command_to_check)" ]; then
			if [ -z "$packages_to_install" ]; then
				packages_to_install="$software_name"
			else
				packages_to_install="$packages_to_install $software_name"
			fi
		fi
	done

	if [ -n "$packages_to_install" ]; then
		log "info" "Some software commands are missing. $packages_to_install installing..."
		case $package_manager in
		"yum")
			yum install -y $packages_to_install >/dev/null
			;;
		"dnf")
			dnf install -y $packages_to_install >/dev/null
			;;
		"apt")
			apt install -y $packages_to_install >/dev/null
			;;
		"zypper")
			zypper install -y $packages_to_install >/dev/null
			;;
		"pacman")
			pacman -S --noconfirm $packages_to_install >/dev/null
			;;
		*)
			log "error" "Unsupported package manager."
			exit 1
			;;
		esac
	fi
	log "info" "All required software commands are already installed."
}

addTitle() {
	local file=$1
	local title=$(
		cat <<END
[Adblock Plus 2.0]
! Title: CODERYJFADBLOCK
! Homepage: https://github.com/coderyjf/AdBlock
! Expires: 3 days
! Version: $VERSION
! Description: Fewer advertisement
END
	)
	echo "$title" >"$file"
	log "info" "Add title to $file."
}

downloadSources() {
	mkdir -p "$HOSTRESOURCES" "$RULERESOURCES"
	log "info" "Downloading sources..."
	for host_source in "${HOSTSOURCESLIST[@]}"; do
		host_source_name=$(echo "$host_source" | cut -d'|' -f1 | sed 's/ *$//')
		host_source_url=$(echo "$host_source" | cut -d'|' -f2 | sed 's/^ *//')
		curl -m 60 --retry-delay 2 --retry 5 --parallel --parallel-immediate -k -L -C - -o "$HOSTRESOURCES/$host_source_name" --connect-timeout 60 -s "$host_source_url" | iconv -t utf-8 &
	done

	for rule_source in "${RULESOURCESLIST[@]}"; do
		rule_source_name=$(echo "$rule_source" | cut -d'|' -f1 | sed 's/ *$//')
		rule_source_url=$(echo "$rule_source" | cut -d'|' -f2 | sed 's/^ *//')
		curl -m 60 --retry-delay 2 --retry 5 --parallel --parallel-immediate -k -L -C - -o "$RULERESOURCES/$rule_source_name" --connect-timeout 60 -s "$rule_source_url" | iconv -t utf-8 &
	done
	log "info" "Downloads complete."
}

filterHost() {
	addTitle "$HOSTSRESULT"
	log "info" "Filter host resources..."
	find "$HOSTRESOURCES" -type f -exec cat {} + | sed 's/^[[:space:]]*//' | grep -v -E '^((#.*)|(\s*))$' | grep -v -E '^[0-9f\.:]+\s+(ip6-)|(localhost|local|loopback|broadcasthost)$' | sed 's/#.*$//' | grep -Ev 'local.*\.local.*$' | sed 's/127.0.0.1/0.0.0.0/g' | sed 's/::/0.0.0.0/g' | grep '0.0.0.0' | grep -Ev '.0.0.0.0' | grep -Ev '#|\$|@|!|/|\\|\*' | sed 's/0.0.0.0//' | sed 's/\r$//' | sed 's/^ *//;s/ *$//' | sort -n | awk '!a[$0]++' | sed '/^$/d' | sed 's/^/||&/g' | sed 's/$/&^/g' >>"$HOSTSRESULT"
}

filterRule() {
	addTitle "$RULESRESULT"
	log "info" "Filter rule resources..."
	find "$RULERESOURCES" "$CUSTOMRULES" -type f -not -path "$EXCLUDEFILE" -exec cat {} + | sed '/^!/d' | sed '/^#[^#]*$/d' | sed '/^\[Adblock Plus.*/d' | sed 's/\r$//' | awk '!a[$0]++' | sed '/^$/d' >>"$RULESRESULT"
}

cleanUp() {
	mv "$HOSTSRESULT" "$CUSTOMRULES/"
	mv "$RULESRESULT" "$CUSTOMRULES/"
	rm -rf "$RESOURCES"
	log "info" "Clean up files..."
}

downloadSources
sleep 3
filterHost &
filterRule &
wait
cleanUp
