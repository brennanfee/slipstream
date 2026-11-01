#!/usr/bin/env bash
# Author: Brennan A. Fee
# License: MIT License
#
# This script serves as the core "installer" for the Slipstream Linux installation method. It is an automated version of
# the "Arch Way" of installation for multiple Linux distributions. It is intended that the end user boot to a shell
# prompt on an installation medium, curl or wget this script down, and then execute it. This script with then use the
# parameters passed to download other scripts and perform the installation. The end goal is not a fully configured
# workable system but a minimially configured environment with the things that are difficult to change after a usual
# Linux install takenc are of (disk partitioning, Kernel selection, etc.).
#
# Short URL: TBD
# Github URL: TBD
#
# To use the develop branch version (note that just because you are using the dev branch of the bootstrapper does NOT
# mean that you will automatically use the dev branch of the other scripts, you will need to use the --dev flag for
# that):
#
# Short URL: TBD
# Github URL: TBD
#

### START Bash strict mode for executables
# Check if was sourced
sourced=0
if [[ -n "${ZSH_VERSION:-}" ]]; then
  [[ ${ZSH_EVAL_CONTEXT:-} =~ :file$ ]] && sourced=1 || sourced=0
elif [[ -n "${BASH_VERSION:-}" ]]; then
  (return 0 2> /dev/null) && sourced=1 || sourced=0
else # All other shells: examine $0 for known shell binary filenames.
  # Detects `sh` and `dash`; add additional shell filenames as needed.
  case ${0##*/} in sh | -sh | dash | -dash) sourced=1 ;; *) sourced=0 ;; esac
fi
if [[ "${sourced}" -eq 1 ]]; then
  echo "This script is intended to be executed, not sourced." >&2
  exit 1
fi

set -o errexit  # same as set -e
set -o nounset  # same as set -u
set -o errtrace # same as set -E
set -o pipefail
set -o posix
#set -o xtrace # same as set -x, turn on for debugging

shopt -s extdebug
IFS=$(printf '\n\t')
unset sourced
### END Bash strict mode for executables

SCRIPT_AUTHOR="Brennan Fee"
SCRIPT_LICENSE="MIT License"
SCRIPT_VERSION="0.1"
SCRIPT_DATE="2026-11-01"

############ START: Generic Print Methods

print_line() {
  local T_COLS
  T_COLS=$(tput cols)
  printf "%${T_COLS}s\n" | tr ' ' '-'
}

print_blank_line() {
  echo ""
}

print_msg() {
  local T_COLS
  local RESET
  RESET="$(tput sgr0)"
  T_COLS=$(($(tput cols) - 1))
  echo -e "$1${RESET}" | fold -sw "${T_COLS}"
}

print_debug() {
  print_msg "DEBUG: $1"
}

print_bold() {
  local T_COLS
  local RESET
  local BOLD
  RESET="$(tput sgr0)"
  BOLD="$(tput bold)"
  T_COLS=$(($(tput cols) - 1))
  echo -e "${BOLD}$1${RESET}" | fold -sw "${T_COLS}"
}

print_error() {
  local RED
  local RESET
  local T_COLS
  RESET="$(tput sgr0)"
  RED="$(tput setaf 1)"
  T_COLS=$(($(tput cols) - 1))
  echo -e "${RED}$1${RESET}\n" >&2
}

error_msg() {
  print_error "$1"
  exit 1
}

############ END: Generic Print Methods

#### START: Array Utilities

# Used to call a function or command and rather than fail due to 'set -e' in the
# current shell, grab its exit code.  This is useful\necessary when you want to
# gracefully handle the result of a command that would otherwise stop execution
# of the script due to 'set -e' being turned on.
#
# Usage: Call this function just prior to a bash function or command you wish to
# capture the exit code for.  Inputs for the second function can be passed as
# usual and they will flow through to the execution of the command.
#
# get_exit_code some_function input1 input2
#
# Afterward you can then check the ${EXIT_CODE} variable and handle it however
# you wish.
function get_exit_code() {
  EXIT_CODE=0
  # We first disable errexit in the current shell
  set +e
  (
    # Then we set it again inside a subshell
    set -e
    # ...and run the function
    "$@"
  )
  # shellcheck disable=2034
  EXIT_CODE=$?
  # And finally turn errexit back on in the current shell
  set -e
}

# Check if a string exists in an array of elements\strings
#
# Say you have an array like:  DISTROS=('debian' 'ubuntu' 'arch')
# If you wanted to verify whether the string 'debian' exists in that array, you
# could use the following:
#
# get_exit_code contains_element "debian" "${DISTROS[@]}"
# if [[ ${EXIT_CODE} -eq 0 ]]
# then
#   <string does exist in array, code goes here>
# fi
#
function contains_element() {
  for e in "${@:2}"; do
    [[ ${e} == "$1" ]] && break
  done
}

#### END: Array Utilities

############ START: Help and Output

print_title() {
  clear
  local text="Slipstream Bootstrapper - Author: ${SCRIPT_AUTHOR} - "
  text+="License: ${SCRIPT_LICENSE}"
  print_bold "${text}"
  print_line
}

show_help() {
  local l="Slipstream Bootstrapper Help -- Script version: ${SCRIPT_VERSION} "
  l+="- Script date: ${SCRIPT_DATE}"
  print_msg "$l"
  print_blank_line
  print_msg "Example:  bootstrapper.bash <distro> {edition} {configuration} {flags/options}"
  print_blank_line
  l="Distro is required.  It is the Linux distribution to install, currently Debian, Ubuntu, "
  l+="Arch, CachyOS, and NixOS are supported."
  print_msg "$l"
  print_blank_line
  l="Edition is optional and is distro specific. For distro's where an edition might not make sense"
  l+="'default' can be used. Each distro will select one of their options as the default edition."
  l+="Some distros allow passing in a codename for a release as well, such as 'bookworom'"
  l+="for Debian or 'jammy' for Ubuntu."
  print_msg "$l"
  print_blank_line
  l="Configuration is optional and can be one of 'default', 'vagrant', 'vm', 'homelab', "
  l+="'homelan', 'vmhomelab', 'vmhomelan', and 'external'. The default is, naturally 'default'. "
  l+="These configurations serve as pre-set groups of settings based on a common target type "
  l+="of system to be initialized. For instance, the vagrant configuration assumes vm usage "
  l+="(and so skips disk encryption) and creates a 'vagrant' user as the main user. All of "
  l+="the values initialized with a configuration can be overridden by flags or options that "
  l+="follow. For the 'external' configuration the next parameter must be a URL that points "
  l+="to a script that will set the desired options (using exported environment variables). "
  l+="The script will be downloaded and sourced before the rest of the options are processed. "
  l+="Example: bootstrapper.bash debian stable external https://tinyurl.com/mysettings --auto-mode"
  print_msg "$l"
  print_blank_line
  l="The configurations 'homelab', 'homelan', 'vmhomelab', and 'vmhomelan' are for my own personal "
  l+="use. While they may work for you, the settings may not be what you would desire. All they really "
  l+="are are hard coded mappings of an 'external' to URL setting scripts that I maintain for my use. "
  l+="No magic is being done that couldn't be done with the 'external' value on your own, I (as the "
  l+="author) am just lazy and don't like to type that much so have hard coded my common use cases."
  print_msg "$l"
  print_blank_line
  l="Options are all passed as flags (-{short option}, --{long option}), some are mutually "
  l+="exclusive and in those cases the last one passed in wins. For a list of the options "
  l+="run this script again with 'options' as the first parameter or --options as a flag."
  print_msg "$l"
  print_blank_line
  l="Lastly, all of these settings and flags are simply setting up the environment variable "
  l+="exports that are read by the distro specific installer scripts (all environment variables "
  l+="start with 'SLIP_').  Within this script they are all initialized by default from any pre-existing "
  l+="those values would still be overridden by any values set in selected configurations, and finally "
  l+="before calling this script will 'pass through' as the 'new' defaults. Keep in mind however, that "
  l+="those values would still be overridden by any values set in selected configurations, and finally "
  l+="overridden by any the flags. The last value set wins, always."
  print_msg "$l"
  print_blank_line
  exit 0
}

show_options() {
  local l="Slipstream Bootstrapper Help -- Script version: ${SCRIPT_VERSION} "
  l+="- Script date: ${SCRIPT_DATE}"
  print_msg "$l"
  print_blank_line
  l="Most options allow a 'no' option to turn the option off rather than on. "
  l+="Simply pass --no-{option} or --no{option} instead.  The 'auto', 'single-disk', "
  l+="'dual-disk', 'interactive', and 'script' options are the only ones without the "
  l+="'no' variants.  To use the 'no' option you cannot use the short variant for the option name."
  print_msg "$l"
  print_blank_line
  print_msg "Options:"
  print_blank_line
  print_msg "  --auto: Auto-mode, no confirmations and auto-reboots the machine after initial install."
  print_msg "      Aliases: -a, --automatic, --automode, --auto-mode"
  print_msg "  --confirm: Ask for option confirmation on install. Aliases: -c, --confirmation"
  print_msg "  --reboot: Reboot the machine automatically at end of install. Alias: -r"
  print_msg "  --debug: Debug mode, run the install script in debug mode. Alias: -d"
  print_msg "  --dev: Use the dev branch version of the installer."
  print_msg "  --single-disk: Single disk machine configuration. Alias: --single"
  print_msg "  --dual-disk: Dual disk machine configuration. Alias: --dual, --dual-disks"
  print_msg "  --encrypt: Encrypt the disks. Aliases: -e, --encrypted"
  print_msg "  --enable-root: Enable and configure the root account."
  print_msg "  --data: Configure a data directory (not commonly used)."
  print_msg "      Aliases: --usedata, --use-data"
  print_msg "  --service-acct: Configure a service account (not commonly used)."
  print_msg "      Aliases: --create-service-acct, --svc-acct"
  print_blank_line
  local l="Finally, a --script option is available that is used in advanced and test scenario's "
  l+="to override which distro installer script to use.  It is passed like: --script <path to script>"
  print_msg "$l"
  print_blank_line
  exit 0
}

print_options() {
  print_bold "SLIP_INSTALL_OS='${SLIP_INSTALL_OS}'"
  print_bold "SLIP_INSTALL_EDITION='${SLIP_INSTALL_EDITION}'"
  print_bold "SLIP_KERNEL_VERSION='${SLIP_KERNEL_VERSION}'"

  print_blank_line
  print_bold "CONFIGURATION='${CONFIGURATION}'"
  if [[ "${CONFIGURATION}" == "external" ]]; then
    print_bold "EXTERNAL URL='${CONFIGURATION_URL}'"
  fi

  print_blank_line

  print_bold "SLIP_MAIN_DISK='${SLIP_MAIN_DISK}'"
  print_bold "SLIP_SECOND_DISK='${SLIP_SECOND_DISK}'"
  print_bold "SLIP_ENCRYPT_DISKS='${SLIP_ENCRYPT_DISKS}'"

  print_blank_line

  print_bold "SLIP_HOSTNAME='${SLIP_HOSTNAME}'"
  print_bold "SLIP_DOMAIN='${SLIP_DOMAIN}'"

  print_blank_line

  print_bold "SLIP_ROOT_DISABLED='${SLIP_ROOT_DISABLED}'"
  print_bold "SLIP_ROOT_PWD='${SLIP_ROOT_PWD}'"
  print_bold "SLIP_CREATE_SERVICE_ACCT='${SLIP_CREATE_SERVICE_ACCT}'"
  print_bold "SLIP_SERVICE_ACCT_PWD='${SLIP_SERVICE_ACCT_PWD}'"
  print_bold "SLIP_SERVICE_ACCT_SSH_KEY='${SLIP_SERVICE_ACCT_SSH_KEY}'"
  print_bold "SLIP_CREATE_USER='${SLIP_CREATE_USER}'"
  print_bold "SLIP_USERNAME='${SLIP_USERNAME}'"
  print_bold "SLIP_USER_PWD='${SLIP_USER_PWD}'"
  print_bold "SLIP_USER_SSH_KEY='${SLIP_USER_SSH_KEY}'"
  print_bold "SLIP_USE_DATA_DIR='${SLIP_USE_DATA_DIR}'"

  print_blank_line

  print_bold "SLIP_CONFIRM_SETTINGS='${SLIP_CONFIRM_SETTINGS}'"
  print_bold "SLIP_REBOOT='${SLIP_REBOOT}'"

  print_blank_line

  print_bold "SLIP_IS_DEBUG='${SLIP_IS_DEBUG}'"
}

############ END: Help and Output

DISTRO=""
EDITION=""
CONFIGURATION="default"
CONFIGURATION_URL=""
PARAMETER_SHIFTS=0
INTERACTIVE=0
DEV=0
IS_DRY_RUN=0

check_root() {
  local user_id
  user_id=$(id -u)
  if [[ "${user_id}" != "0" ]]; then
    error_msg "ERROR! You must execute the script as the 'root' user."
  fi
}

load_defaults() {
  export SLIP_INSTALL_EDITION="${SLIP_INSTALL_EDITION:=stable}"
  export SLIP_INSTALL_OS="${SLIP_INSTALL_OS:=debian}"
  export SLIP_KERNEL_VERSION="${SLIP_KERNEL_VERSION:=backports}"

  export SLIP_MAIN_DISK="${SLIP_MAIN_DISK:=smallest}"
  export SLIP_SECOND_DISK="${SLIP_SECOND_DISK:=ignore}"
  export SLIP_ENCRYPT_DISKS="${SLIP_ENCRYPT_DISKS:=0}"

  export SLIP_HOSTNAME="${SLIP_HOSTNAME:=}"
  export SLIP_DOMAIN="${SLIP_DOMAIN:=}"

  export SLIP_ROOT_DISABLED="${SLIP_ROOT_DISABLED:=0}"
  export SLIP_ROOT_PWD="${SLIP_ROOT_PWD:=}"
  export SLIP_CREATE_SERVICE_ACCT="${SLIP_CREATE_SERVICE_ACCT:=0}"
  export SLIP_SERVICE_ACCT_PWD="${SLIP_SERVICE_ACCT_PWD:=}"
  export SLIP_SERVICE_ACCT_SSH_KEY="${SLIP_SERVICE_ACCT_SSH_KEY:=}"
  export SLIP_CREATE_USER="${SLIP_CREATE_USER:=0}"
  export SLIP_USERNAME="${SLIP_USERNAME:=}"
  export SLIP_USER_PWD="${SLIP_USER_PWD:=}"
  export SLIP_USER_SSH_KEY="${SLIP_USER_SSH_KEY:=}"

  export SLIP_USE_DATA_DIR="${SLIP_USE_DATA_DIR:=0}"

  export SLIP_CONFIRM_SETTINGS="${SLIP_CONFIRM_SETTINGS:=1}"
  export SLIP_REBOOT="${SLIP_REBOOT:=0}"

  export SLIP_IS_DEBUG="${SLIP_IS_DEBUG:=0}"
}

read_positional_arguments() {
  if [[ "$1" == "help" || "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
  fi
  if [[ "$1" == "options" || "$1" == "--options" ]]; then
    show_options
  fi

  local l

  ## Distro
  local supported_distros=("debian" "ubuntu")
  if [[ "$1" =~ ^"-" || "$1" == "" ]]; then
    l="You must pass in the distribution you want to install."
    print_error "$l"
    show_help
  fi

  DISTRO="$1"
  PARAMETER_SHIFTS=$((PARAMETER_SHIFTS + 1))

  get_exit_code contains_element "${DISTRO}" "${supported_distros[@]}"
  if [[ ! "${EXIT_CODE}" == "0" ]]; then
    l="Invalid distribution read '${DISTRO}'. Please check documentation for supported list of distributions."
    print_error "$l"
    show_help
  fi

  shift

  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
  fi
  if [[ "$1" == "--options" ]]; then
    show_options
  fi

  if [[ ("$1" =~ ^"-" || "$1" == "") ]]; then
    EDITION="default"
  else
    EDITION="$1"
    PARAMETER_SHIFTS=$((PARAMETER_SHIFTS + 1))
  fi

  shift

  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
  fi
  if [[ "$1" == "--options" ]]; then
    show_options
  fi

  ## Configuration
  if [[ ! ("$1" =~ ^"-" || "$1" == "") ]]; then
    CONFIGURATION="$1"
    PARAMETER_SHIFTS=$((PARAMETER_SHIFTS + 1))

    local supported_configs=("default" "defaults" "vagrant" "vm" "homelab" "homelan" "vmhomelab" "vmhomelan" "external")
    get_exit_code contains_element "${CONFIGURATION}" "${supported_configs[@]}"
    if [[ ! "${EXIT_CODE}" == "0" ]]; then
      local l="Value read as configuration '${CONFIGURATION}' is not valid, try again with "
      l+="a supported value."
      print_error "$l"
      show_help
    fi

    if [[ "${CONFIGURATION}" == "external" ]]; then
      shift
      PARAMETER_SHIFTS=$((PARAMETER_SHIFTS + 1))

      CONFIGURATION_URL="$1"

      if [[ "${CONFIGURATION_URL}" == "" || "${CONFIGURATION_URL}" =~ ^"-" ]]; then
        local l="When using the 'external' setting, you must provide a URL to a script "
        l+="that will be used to set the environment variable defaults."
        print_error "$l"
        show_help
      fi
    fi
  fi
}

process_distro_and_edition() {
  case "${EDITION}" in
    "stable" | "testing" | "sid")
      DISTRO="debian"
      export SLIP_KERNEL_VERSION="default"
      ;;
    "backport" | "backports")
      DISTRO="debian"
      EDITION="stable"
      export SLIP_KERNEL_VERSION="backports"
      ;;
    "lts" | "rolling")
      DISTRO="ubuntu"
      export SLIP_KERNEL_VERSION="default"
      ;;
    "ltshwe")
      DISTRO="ubuntu"
      EDITION="lts"
      export SLIP_KERNEL_VERSION="hwe"
      ;;
    "ltsedge")
      DISTRO="ubuntu"
      EDITION="lts"
      export SLIP_KERNEL_VERSION="hwe-edge"
      ;;
    *)
      export SLIP_KERNEL_VERSION="default"
      ;;
  esac

  export SLIP_INSTALL_OS="${DISTRO}"
  export SLIP_INSTALL_EDITION="${EDITION}"
}

process_configuration() {
  case ${CONFIGURATION} in
    default | defaults)
      ## do nothing
      ;;
    vagrant)
      export SLIP_ENCRYPT_DISKS=0

      export SLIP_CREATE_USER=1
      export SLIP_USERNAME="vagrant"
      export SLIP_USER_PWD="vagrant"

      export SLIP_MAIN_DISK="smallest"
      export SLIP_SECOND_DISK="ignore"
      export SLIP_ENCRYPT_DISKS=0
      ;;
    vm)
      export SLIP_MAIN_DISK="smallest"
      export SLIP_SECOND_DISK="ignore"
      export SLIP_ENCRYPT_DISKS=0
      ;;
    homelab)
      process_from_external "https://tinyurl.com/brennan-home-lab-config"
      ;;
    homelan)
      process_from_external "https://tinyurl.com/brennan-home-lan-config"
      ;;
    vmhomelab)
      process_from_external "https://tinyurl.com/brennan-vm-home-lab-config"
      ;;
    vmhomelan)
      process_from_external "https://tinyurl.com/brennan-vm-home-lan-config"
      ;;
    external)
      process_from_external "$CONFIGURATION_URL"
      ;;
    *)
      error_msg "Unknown configuration: '${CONFIGURATION}'"
      ;;
  esac
}

process_from_external() {
  local script_url="$1"
  local script_file="/tmp/external_config"
  local downloaded=0

  if [[ -f "${script_url}" ]]; then
    script_file="${script_url}"
  elif [[ ! -f "${script_file}" ]]; then
    curl -fsSL -o "${script_file}" "${script_url}"
    downloaded=1
  fi

  # Source the script
  # print_debug "Sourcing script"
  # shellcheck source=/dev/null
  source "${script_file}"

  # Remove it
  if [[ "${downloaded}" == "1" ]]; then
    rm "${script_file}"
  fi
}

process_options() {
  for ((i = 0; i < PARAMETER_SHIFTS; i++)); do
    shift
  done

  # Loop the rest of the options, setting the exports as we go
  while [[ "${1:-}" != "" ]]; do
    case $1 in
      -h | --help)
        show_help
        ;;
      --options)
        show_options
        ;;
      -a | --auto | --automatic | --automode | --auto-mode)
        export SLIP_CONFIRM_SETTINGS=0
        export SLIP_REBOOT=1
        ;;
      --single-disk | --single)
        export SLIP_MAIN_DISK="smallest"
        export SLIP_SECOND_DISK="ignore"
        ;;
      --dual-disk | --dual | --dual-disks)
        export SLIP_MAIN_DISK="smallest"
        export SLIP_SECOND_DISK="largest"
        ;;
      -c | --confirm | --confirmation)
        export SLIP_CONFIRM_SETTINGS=1
        ;;
      --noconfirm | --no-confirm | --noconfirmation | --no-confirmation)
        export SLIP_CONFIRM_SETTINGS=0
        ;;
      -r | --reboot)
        export SLIP_REBOOT=1
        ;;
      --noreboot | --no-reboot)
        export SLIP_REBOOT=0
        ;;
      -d | --debug)
        export SLIP_IS_DEBUG=1
        ;;
      --nodebug | --no-debug)
        export SLIP_IS_DEBUG=0
        ;;
      -e | --encrypt | --encrypted)
        export SLIP_ENCRYPT_DISKS=1
        ;;
      --noencrypt | --no-encrypt | --noencryption | --no-encryption)
        export SLIP_ENCRYPT_DISKS=0
        ;;
      --i | --interactive)
        INTERACTIVE=1
        ;;
      --dev)
        DEV=1
        ;;
      --dryrun)
        IS_DRY_RUN=1
        ;;
      --hostname)
        shift
        export AUTO_HOSTNAME="$1"
        ;;
      --source)
        shift
        CONFIG_SCRIPT_SOURCE="$1"
        ;;
      *)
        error_msg "Unknown option: '$1'"
        ;;
    esac

    shift
  done
}

download_installer() {
  local script_file=$1

  local script_url="https://raw.githubusercontent.com/brennanfee/linux-bootstraps/main/scripted-installer/debian/deb-install.bash"
  if [[ "${INTERACTIVE}" == 1 ]]; then
    local script_url="https://raw.githubusercontent.com/brennanfee/linux-bootstraps/main/scripted-installer/debian/deb-install-interactive.bash"
  fi

  if [[ "${DEV}" == 1 ]]; then
    local script_url="https://raw.githubusercontent.com/brennanfee/linux-bootstraps/develop/scripted-installer/debian/deb-install.bash"
    if [[ "${INTERACTIVE}" == 1 ]]; then
      local script_url="https://raw.githubusercontent.com/brennanfee/linux-bootstraps/develop/scripted-installer/debian/deb-install-interactive.bash"
    fi
  fi

  if [[ ! -f "${script_file}" ]]; then
    # To support testing of other versions of the install script (local versions, branches, etc.)
    if [[ "${CONFIG_SCRIPT_SOURCE:=}" != "" ]]; then
      curl -fsSL -o "${script_file}" "${CONFIG_SCRIPT_SOURCE}"
    else
      curl -fsSL -o "${script_file}" "${script_url}"
    fi
  fi
}

main() {
  print_title

  check_root

  load_defaults
  read_positional_arguments "$@"

  process_distro_and_edition
  process_configuration

  process_options "$@"

  print_options

  local script_file
  script_file="/tmp/linux-installer.bash"
  download_installer "${script_file}"

  if [[ "${IS_DRY_RUN}" == 0 ]]; then
    # Now run the script
    bash "${script_file}"
  fi
}

main "$@"
