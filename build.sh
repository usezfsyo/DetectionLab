#! /bin/bash

# This script is meant to be used with a fresh clone of DetectionLab and
# will fail to run if boxes have already been created or any of the steps
# from the README have already been run followed.
# Only MacOS and Linux are supported.
# If you encounter issues, feel free to open an issue at
# https://github.com/clong/DetectionLab/issues

set -e

print_usage() {
  echo "Usage: ./build.sh <virtualbox|vmware_fusion|vmware_esxi>"
  exit 0
}

check_packer_and_vagrant() {
  # Check for existence of Vagrant in PATH
  if ! which vagrant >/dev/null; then
    (echo >&2 "Vagrant was not found in your PATH.")
    (echo >&2 "Please correct this before continuing. Quitting.")
    exit 1
  fi
  # Ensure Vagrant >= 2.0.0
  if [ "$(vagrant --version | grep -o "[0-9]" | head -1)" -lt 2 ]; then
    (echo >&2 "WARNING: It is highly recommended to use Vagrant 2.0.0 or above before continuing")
  fi
  # Check for existence of Packer in PATH
  if ! which packer >/dev/null; then
    (echo >&2 "Packer was not found in your PATH.")
    (echo >&2 "Please correct this before continuing. Quitting.")
    (echo >&2 "Hint: sudo cp ./packer /usr/local/bin/packer; sudo chmod +x /usr/local/bin/packer")
    exit 1
  fi
}

# Returns 0 if not installed or 1 if installed
check_virtualbox_installed() {
  if which VBoxManage >/dev/null; then
    echo "1"
  else
    echo "0"
  fi
}

# Returns 0 if not installed or 1 if installed
check_vmware_fusion_installed() {
  if [ -e "/Applications/VMware Fusion.app" ]; then
    echo "1"
  else
    echo "0"
  fi
}

# Returns 0 if not installed or 1 if installed
check_vmware_vagrant_plugin_installed() {
  VAGRANT_VMWARE_PLUGIN_PRESENT="$(vagrant plugin list | grep -c 'vagrant-vmware-fusion')"
  if [ "$VAGRANT_VMWARE_PLUGIN_PRESENT" -eq 0 ]; then
    (echo >&2 "VMWare Fusion is installed, but the Vagrant plugin is not.")
    (echo >&2 "Visit https://www.vagrantup.com/vmware/index.html#buy-now for more information on how to purchase and install it")
    (echo >&2 "VMWare Fusion will not be listed as a provider until the Vagrant plugin has been installed.")
    echo "0"
  else
    echo "$VAGRANT_VMWARE_PLUGIN_PRESENT"
  fi
}

# List the available Vagrant providers present on the system
list_providers() {
  VBOX_PRESENT=0
  VMWARE_FUSION_PRESENT=0

  if [ "$(uname)" == "Darwin" ]; then
    # Detect Providers on OSX
    VBOX_PRESENT=$(check_virtualbox_installed)
    VMWARE_FUSION_PRESENT=$(check_vmware_fusion_installed)
    VAGRANT_VMWARE_PLUGIN_PRESENT=$(check_vmware_vagrant_plugin_installed)
  else
    # Assume the only other available providers are either ESXi or Virtualbox.
    VBOX_PRESENT=$(check_virtualbox_installed)
    VMWARE_ESXI_PRESENT=1
  fi

  (echo >&2 "Available Providers:")
  if [ "$VBOX_PRESENT" == "1" ]; then
    (echo >&2 "virtualbox")
  fi
  if [ "$VMWARE_ESXI_PRESENT" == "1" ]; then
    (echo >&2 "vmware_esxi")
  fi
  if [[ $VMWARE_FUSION_PRESENT -eq 1 ]] && [[ $VAGRANT_VMWARE_PLUGIN_PRESENT -eq 1 ]]; then
    (echo >&2 "vmware_fusion")
  fi
  if [[ $VBOX_PRESENT -eq 0 ]] && [[ $VMWARE_FUSION_PRESENT -eq 0 ]] && [[ $VMWARE_ESXI_PRESENT -eq 0 ]]; then
    (echo >&2 "You need to install a provider such as VirtualBox or VMware Fusion to continue.")
    exit 1
  fi
  (echo >&2 -e "\\nWhich provider would you like to use?")
  read -r PROVIDER
  # Sanity check
  if [[ "$PROVIDER" != "virtualbox" ]] && [[ "$PROVIDER" != "vmware_fusion" ]] && [[ "$PROVIDER" != "vmware_esxi" ]]; then
    (echo >&2 "Please choose a valid provider. \"$PROVIDER\" is not a valid option")
    exit 1
  fi
  echo "$PROVIDER"
}

# A series of checks to identify potential issues before starting the build
preflight_checks() {
  DL_DIR="$1"

  # Check to see if curl is in PATH
  if ! which curl >/dev/null; then
    (echo >&2 "Please install curl and make sure it is in your PATH.")
    exit 1
  fi
  # Check to see if boxes exist already
  BOXES_BUILT=$(find "$DL_DIR"/Boxes -name "*.box" | wc -l)
  if [ "$BOXES_BUILT" -gt 0 ]; then
    (echo >&2 "You appear to have already built at least one box using Packer. This script does not support pre-built boxes. Please either delete the existing boxes or follow the build steps in the README to continue.")
    exit 1
  fi
  # Check to see if any Vagrant instances exist already
  cd "$DL_DIR"/Vagrant/
  # Vagrant status has the potential to return a non-zero error code, so we work around it with "|| true"
  VAGRANT_BUILT=$(vagrant status | grep -c 'not created') || true
  if [ "$VAGRANT_BUILT" -ne 4 ]; then
    (echo >&2 "You appear to have already created at least one Vagrant instance. This script does not support pre-created instances. Please either destroy the existing instances or follow the build steps in the README to continue.")
    exit 1
  fi
  # Check available disk space. Recommend 80GB free, warn if less.
  FREE_DISK_SPACE=$(df -m "$HOME" | tr -s ' ' | grep '/' | cut -d ' ' -f 4)
  if [ "$FREE_DISK_SPACE" -lt 80000 ]; then
    (echo >&2 -e "Warning: You appear to have less than 80GB of HDD space free on your primary partition. If you are using a separate parition, you may ignore this warning.\\n")
    (df >&2 -m "$HOME")
    (echo >&2 "")
  fi
  # Check Packer version against known bad
  if [ "$(packer --version)" == '1.1.2' ]; then
    (echo >&2 "Packer 1.1.2 is not supported. Please upgrade to a newer version and see https://github.com/hashicorp/packer/issues/5622 for more information.")
    exit 1
  fi
  # Ensure the vagrant-reload plugin is installed
  VAGRANT_RELOAD_PLUGIN_INSTALLED=$(vagrant plugin list | grep -c 'vagrant-reload')
  if [ "$VAGRANT_RELOAD_PLUGIN_INSTALLED" != "1" ]; then
    (echo >&2 "The vagrant-reload plugin is required and not currently installed. This script will attempt to install it now.")
    if ! $(which vagrant) plugin install "vagrant-reload"; then
      (echo >&2 "Unable to install the vagrant-reload plugin. Please try to do so manually and re-run this script.")
      exit 1
    fi
  fi
}

# Builds a box using Packer
packer_build_box() {
  PROVIDER="$1"
  BOX="$2"
  DL_DIR="$3"
  if [ "$PROVIDER" == "vmware_fusion" ]; then
    PROVIDER="vmware"
  fi
  if [ "$PROVIDER" == "vmware_esxi" ]; then
    PROVIDER="vmware"
  fi  
  cd "$DL_DIR/Packer"
  (echo >&2 "Using Packer to build the $BOX Box. This can take 90-180 minutes depending on bandwidth and hardware.")
  if ! $(which packer) build --only="$PROVIDER-iso" "$BOX".json; then
    (echo >&2 "Something went wrong while attempting to build the $BOX box.")
    (echo >&2 "To file an issue, please visit https://github.com/clong/DetectionLab/issues/")
  fi
}

# Moves the boxes from the Packer directory to the Boxes directory
move_boxes() {
  PROVIDER="$1"
  DL_DIR="$2"
  # Hacky workaround for VMware
  if [ "$PROVIDER" == "vmware_fusion" ]; then
    PROVIDER="vmware"
  fi
  if [ "$PROVIDER" == "vmware_esxi" ]; then
    PROVIDER="vmware"
  fi
  mv "$DL_DIR"/Packer/*.box "$DL_DIR"/Boxes
  # Ensure Windows 10 box exists
  if [ ! -f "$DL_DIR"/Boxes/windows_10_"$PROVIDER".box ]; then
    (echo >&2 "Windows 10 box is missing from the Boxes directory. Qutting.")
    exit 1
  fi
  # Ensure Windows 2016 box exists
  if [ ! -f "$DL_DIR"/Boxes/windows_2016_"$PROVIDER".box ]; then
    (echo >&2 "Windows 2016 box is missing from the Boxes directory. Qutting.")
    exit 1
  fi
}

# Brings up a single host using Vagrant
vagrant_up_host() {
  PROVIDER="$1"
  HOST="$2"
  DL_DIR="$3"
  (echo >&2 "Attempting to bring up the $HOST host using Vagrant")
  cd "$DL_DIR"/Vagrant
  $(which vagrant) up "$HOST" --provider="$PROVIDER" 1>&2
  echo "$?"
}

# Attempts to reload and re-provision a host if the intial "vagrant up" fails
vagrant_reload_host() {
  HOST="$1"
  DL_DIR="$2"
  cd "$DL_DIR"/Vagrant
  # Attempt to reload the host if the vagrant up command didn't exit cleanly
  $(which vagrant) reload "$HOST" --provision 1>&2
  echo "$?"
}

# A series of checks to ensure important services are responsive after the build completes.
post_build_checks() {
  # If the curl operation fails, we'll just leave the variable equal to 0
  # This is needed to prevent the script from exiting if the curl operation fails
  CALDERA_CHECK=$(curl -ks -m 2 https://10.0.4.5:8888 | grep -c '302: Found' || echo "")
  SPLUNK_CHECK=$(curl -ks -m 2 https://10.0.4.5:8000/en-US/account/login?return_to=%2Fen-US%2F | grep -c 'This browser is not supported by Splunk' || echo "")
  FLEET_CHECK=$(curl -ks -m 2 https://10.0.4.5:8412 | grep -c 'Kolide Fleet' || echo "")

  BASH_MAJOR_VERSION=$(/bin/bash --version | grep 'GNU bash' | grep -o version\.\.. | cut -d ' ' -f 2 | cut -d '.' -f 1)
  # Associative arrays are only supported in bash 4 and up
  if [ "$BASH_MAJOR_VERSION" -ge 4 ]; then
    declare -A SERVICES
    SERVICES=(["caldera"]="$CALDERA_CHECK" ["splunk"]="$SPLUNK_CHECK" ["fleet"]="$FLEET_CHECK")
    for SERVICE in "${!SERVICES[@]}"; do
      if [ "${SERVICES[$SERVICE]}" -lt 1 ]; then
        (echo >&2 "Warning: $SERVICE failed post-build tests and may not be functioning correctly.")
      fi
    done
  else
    if [ "$CALDERA_CHECK" -lt 1 ]; then
      (echo >&2 "Warning: Caldera failed post-build tests and may not be functioning correctly.")
    fi
    if [ "$SPLUNK_CHECK" -lt 1 ]; then
      (echo >&2 "Warning: Splunk failed post-build tests and may not be functioning correctly.")
    fi
    if [ "$FLEET_CHECK" -lt 1 ]; then
      (echo >&2 "Warning: Fleet failed post-build tests and may not be functioning correctly.")
    fi
  fi
}

main() {
  # Get location of build.sh
  # https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
  DL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROVIDER=""
  LAB_HOSTS=("logger" "dc" "wef" "win10")
  # If no argument was supplied, list available providers
  if [ $# -eq 0 ]; then
    PROVIDER=$(list_providers)
  fi
  # If more than one argument was supplied, print usage message
  if [ $# -gt 1 ]; then
    print_usage
    exit 1
  fi
  if [ $# -eq 1 ]; then
    # If the user specifies the provider as an agument, set the variable
    # TODO: Check to make sure they actually have their provider installed
    case "$1" in
      virtualbox)
        PROVIDER="$1"
        ;;
      vmware_fusion)
        PROVIDER="$1"
        ;;
      vmware_esxi)
        PROVICER="$1"
        ;;
      *)
        echo "\"$1\" is not a valid provider. Listing available providers:"
        PROVIDER=$(list_providers)
        ;;
    esac
  fi

  preflight_checks "$DL_DIR"
  packer_build_box "$PROVIDER" "windows_2016" "$DL_DIR"
  packer_build_box "$PROVIDER" "windows_10" "$DL_DIR"
  move_boxes "$PROVIDER" "$DL_DIR"

  # Change provider back to original selection if using vmware_fusion
  if [ "$PROVIDER" == "vmware" ]; then
    PROVIDER="vmware_fusion"
  fi

  # Vagrant up each box and attempt to reload one time if it fails
  for VAGRANT_HOST in "${LAB_HOSTS[@]}"; do
    RET=$(vagrant_up_host "$PROVIDER" "$VAGRANT_HOST" "$DL_DIR")
    if [ "$RET" -eq 0 ]; then
      (echo >&2 "Good news! $VAGRANT_HOST was built successfully!")
    fi
    # Attempt to recover if the intial "vagrant up" fails
    if [ "$RET" -ne 0 ]; then
      (echo >&2 "Something went wrong while attempting to build the $VAGRANT_HOST box.")
      (echo >&2 "Attempting to reload and reprovision the host...")
      RETRY_STATUS=$(vagrant_reload_host "$VAGRANT_HOST" "$DL_DIR")
      if [ "$RETRY_STATUS" -ne 0 ]; then
        (echo >&2 "Failed to bring up $VAGRANT_HOST after a reload. Exiting.")
        exit 1
      fi
    fi
  done

  post_build_checks
}

main "$@"
exit 0
