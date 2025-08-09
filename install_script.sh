#!/bin/bash

set -e

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error:${plain} Please run this script with root privilege" && exit 1

# --- OS detect ---
if [[ -f /etc/os-release ]]; then
  . /etc/os-release; release=$ID
elif [[ -f /usr/lib/os-release ]]; then
  . /usr/lib/os-release; release=$ID
else
  echo "Failed to check the system OS!" >&2; exit 1
fi
echo "The OS release is: $release"

arch3xui() {
  case "$(uname -m)" in
    x86_64|x64|amd64) echo 'amd64' ;;
    i*86|x86)         echo '386'   ;;
    armv8*|arm64|aarch64) echo 'arm64' ;;
    armv7*|armv7|arm) echo 'armv7' ;;
    armv6*|armv6)     echo 'armv6' ;;
    armv5*|armv5)     echo 'armv5' ;;
    *) echo -e "${red}Unsupported CPU architecture${plain}"; exit 1 ;;
  esac
}
echo "arch: $(arch3xui)"

os_version="$(grep -i version_id /etc/os-release | cut -d\" -f2 | cut -d. -f1)"
case "$release" in
  centos)   [[ $os_version -lt 8  ]] && echo -e "${red}Use CentOS 8+${plain}" && exit 1 ;;
  ubuntu)   [[ $os_version -lt 20 ]] && echo -e "${red}Use Ubuntu 20+${plain}" && exit 1 ;;
  fedora)   [[ $os_version -lt 36 ]] && echo -e "${red}Use Fedora 36+${plain}" && exit 1 ;;
  debian)   [[ $os_version -lt 11 ]] && echo -e "${red}Use Debian 11+${plain}" && exit 1 ;;
  almalinux|rocky) [[ $os_version -lt 9 ]] && echo -e "${red}Use Alma/Rocky 9+${plain}" && exit 1 ;;
  arch|manjaro|armbian) : ;;
  *) echo -e "${red}Unsupported/unknown distro${plain}"; exit 1 ;;
esac

install_base() {
  case "$release" in
    centos|almalinux|rocky) yum -y update && yum install -y -q wget curl tar tzdata findutils ;;
    fedora)                 dnf -y update && dnf install -y -q wget curl tar tzdata findutils ;;
    arch|manjaro)           pacman -Syu --noconfirm && pacman -S --noconfirm wget curl tar tzdata findutils ;;
    *)                      apt-get update && apt-get install -y -q wget curl tar tzdata findutils ;;
  esac
}

config_after_install() {
  echo -e "${yellow}Install/update finished! It's recommended to modify panel settings.${plain}"
  read -p "Do you want to continue with the modification [y/n]? " config_confirm
  if [[ "$config_confirm" =~ ^[yY]$ ]]; then
    read -p "Please set up your username: " config_account
    read -p "Please set up your password: " config_password
    read -p "Please set up the panel port: " config_port
    echo -e "${yellow}Initializing...${plain}"
    /usr/local/x-ui/x-ui setting -username "$config_account" -password "$config_password"
    /usr/local/x-ui/x-ui setting -port "$config_port"
    echo -e "${green}Credentials and port set successfully.${plain}"
  else
    echo -e "${yellow}Skipping manual config...${plain}"
    if [[ ! -f "/etc/x-ui/x-ui.db" ]]; then
      usernameTemp=$(head -c 6 /dev/urandom | base64)
      passwordTemp=$(head -c 6 /dev/urandom | base64)
      /usr/local/x-ui/x-ui setting -username "$usernameTemp" -password "$passwordTemp"
      echo -e "Generated login for fresh install:\n${green}username:${usernameTemp}${plain}\n${green}password:${passwordTemp}${plain}"
      echo -e "${yellow}You can later run 'x-ui' and choose 8 to view creds.${plain}"
    else
      echo -e "${yellow}Upgrade detected: keeping existing settings.${plain}"
    fi
  fi
  /usr/local/x-ui/x-ui migrate
}

install_x_ui_from_fork() {
  cd /usr/local/

  VERSION="v2.3.3"
  FORK_OWNER="prooxyyy"
  FORK_REPO="3x-ui-wal"

  ARCH="$(arch3xui)"
  ASSET_NAME="x-ui-linux-${ARCH}.tar.gz"

  REL_ASSET_URL="https://github.com/${FORK_OWNER}/${FORK_REPO}/releases/download/${VERSION}/${ASSET_NAME}"
  TARBALL_URL="https://github.com/${FORK_OWNER}/${FORK_REPO}/archive/refs/tags/${VERSION}.tar.gz"

  echo -e "${yellow}Trying fork release asset: ${REL_ASSET_URL}${plain}"
  if wget -q --no-check-certificate -O "/usr/local/${ASSET_NAME}" "${REL_ASSET_URL}"; then
    echo -e "${green}Downloaded release asset from fork.${plain}"
  else
    echo -e "${yellow}Release asset not found, trying to extract from fork tarball...${plain}"
    TMPDIR="$(mktemp -d -t 3xui-XXXXXX)"
    if wget -q --no-check-certificate -O "${TMPDIR}/src.tar.gz" "${TARBALL_URL}"; then
      tar -xzf "${TMPDIR}/src.tar.gz" -C "${TMPDIR}"
      FOUND_ASSET="$(find "${TMPDIR}" -type f -name "${ASSET_NAME}" | head -n1 || true)"
      if [[ -n "$FOUND_ASSET" ]]; then
        cp -f "$FOUND_ASSET" "/usr/local/${ASSET_NAME}"
        echo -e "${green}Found ${ASSET_NAME} inside fork tarball.${plain}"
      else
        echo -e "${red}ERROR:${plain} ${ASSET_NAME} not found in fork (neither as release asset nor inside the tag tarball)."
        echo -e "Searched URL: ${REL_ASSET_URL}"
        echo -e "Searched tarball: ${TARBALL_URL}"
        exit 1
      fi
      rm -rf "${TMPDIR}"
    else
      echo -e "${red}ERROR:${plain} Unable to download fork tarball: ${TARBALL_URL}"
      exit 1
    fi
  fi

  # Clean previous install
  if [[ -e /usr/local/x-ui/ ]]; then
    systemctl stop x-ui || true
    rm -rf /usr/local/x-ui/
  fi

  # Unpack binary package -> creates /usr/local/x-ui
  tar -xzf "/usr/local/${ASSET_NAME}" -C /usr/local/
  rm -f "/usr/local/${ASSET_NAME}"

  cd /usr/local/x-ui
  chmod +x x-ui
  chmod +x "bin/xray-linux-${ARCH}"
  cp -f x-ui.service /etc/systemd/system/

  # Take x-ui.sh strictly from fork tag
  FORK_SCRIPT_URL="https://raw.githubusercontent.com/${FORK_OWNER}/${FORK_REPO}/${VERSION}/x-ui.sh"
  echo -e "${yellow}Fetching x-ui.sh from fork: ${FORK_SCRIPT_URL}${plain}"
  if wget -q --no-check-certificate -O /usr/bin/x-ui "${FORK_SCRIPT_URL}"; then
    chmod +x /usr/bin/x-ui
    chmod +x /usr/local/x-ui/x-ui.sh || true
  else
    echo -e "${red}ERROR:${plain} Could not download x-ui.sh from your fork tag ${VERSION}."
    echo -e "Expected at: ${FORK_SCRIPT_URL}"
    exit 1
  fi

  config_after_install

  systemctl daemon-reload
  systemctl enable x-ui
  systemctl start x-ui
  echo -e "${green}x-ui ${VERSION}${plain} installation finished, running now."
}

echo -e "${green}Running...${plain}"
install_base
install_x_ui_from_fork
