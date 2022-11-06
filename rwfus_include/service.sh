: <<LICENSE
      service.sh: Rwfus
    Copyright (C) 2022 ValShaped (val@soft.fish)

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
LICENSE

source rwfus_include/testlog.sh

function check_casefold {
    sudo dumpe2fs `findmnt -oSOURCE -DvenufT $1` 2>&1 | head -n 10 | grep -q casefold
}

function generate_service_script {
    # Add config-parsing to the bootstrapper script
    cat <<EOF
#!/bin/bash
# This file is automatically generated as part of the installation process.
# Changes made to this file will not persist when updating $Name.
echo "$Name v$Version${TESTMODE+ [Test Mode active]}"
echo "$Description"

EOF
    cat rwfus_include/info.sh           # Copy the project's info to the script
    printf "\n# config: Load only\n"
    echo "Config_File=\"$Config_File\"" # Copy the Config  path to the script, so it knows where to load from
    declare -f load_config              # Copy the load_config function to the script
    printf "\n# mount: and unmount\n"
    cat rwfus_include/mount.sh          # Copy the mount and unmount functions to the script
    printf "\n# service-main: argument parsing and function running\n"
    cat rwfus_include/service-main.sh   # Copy arg parser and script body
}

function generate_service_unit {
    local script_path=$1
    # Put the unit in the dependency chain
    local wanted_by=${2:-"multi-user.target"}
    # Ensure the unit never starts when home is not mounted, and is stopped if home is unmounted.
    local requires=${3:-"multi-user.target home.mount"}
    # Start the unit after filesystem, swap, etc. are up
    local after=${4:-"multi-user.target steamos-offload.target home.mount"}

cat <<-EOF
# Generated by $Name v$Version${TESTMODE+ [Test Mode active]}
[Unit]
Description=$Name: $Description
Requires=$requires
After=$after

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutSec=3
ExecStart=$script_path  --start
ExecStop=$script_path   --stop
ExecReload=$script_path --reload

[Install]
WantedBy=$wanted_by
EOF
}

function generate_service {
    local service_name="${Name@L}d"
    local script_path="$Service_Directory/$service_name.sh"
    local unit_path="$Service_Directory/$service_name.service"
    printf "Generating service $service_name\n  script $script_path\n  unit   $unit_path\n"
    generate_service_script > $script_path \
        && chmod +x $script_path
    generate_service_unit $script_path > $unit_path
}

function enable_service {
    # Mask pacman-cleanup.service, which automatically deletes pacman keyring on reboot
    Log Test systemctl mask -- "pacman-cleanup.service"
    # Print command instead of enabling service, in test mode
    Log Test systemctl enable --now -- `list_service`
    if [[ $? != 0 ]]; then Log -p echo "Error when enabling service. See "$logfile" for information."; return -1; fi
}

function disable_service {
    # Print command instead of disabling service, in test mode
    Log Test systemctl disable --now -- `list_service`
    if [[ $? != 0 ]]; then Log -p echo "Error when disabling service. See "$logfile" for information."; return 1; fi
    # Unmask pacman-cleanup.service, which automatically deletes pacman keyring on reboot
    Log Test systemctl unmask -- "pacman-cleanup.service"
}

function delete_service {
    local out=0
    for unit in `list_service`; do
        Log rm -v -- "$Systemd_Directory/$unit";
        if [[ $? != 0 ]]; then Log -p echo "Error when deleting service. See "$logfile" for information."; return -1; fi
        out=$(( $out+$? ))
    done
}

function stat_service {
    if [[ -d $Service_Directory ]]; then
        SYSTEMD_COLORS=1 Test systemctl status --lines 0 --no-pager -- `list_service`
    else
        echo "Rwfus is not installed. Install it with \`rwfus --install\`"
    fi
}

function list_service {
    find $Service_Directory -name "*.service" -printf "%f"
}
