#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

set -e

cur_dir=$(pwd)

[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch3xui() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "arch: $(arch3xui)"

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Please use CentOS 8 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${red} Please use Ubuntu 20 or higher version!${plain}\n" && exit 1
    fi
elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red} Please use Fedora 36 or higher version!${plain}\n" && exit 1
    fi
elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        echo -e "${red} Please use Debian 11 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "almalinux" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Please use AlmaLinux 9 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "rocky" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Please use RockyLinux 9 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "arch" ]]; then
    echo "Your OS is ArchLinux"
elif [[ "${release}" == "manjaro" ]]; then
    echo "Your OS is Manjaro"
elif [[ "${release}" == "armbian" ]]; then
    echo "Your OS is Armbian"
else
    echo -e "${red}Failed to check the OS version, please contact the author!${plain}" && exit 1
fi

install_base() {
    case "${release}" in
    centos | almalinux | rocky)
        yum -y update && yum install -y -q wget curl tar tzdata findutils
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata findutils
        ;;
    arch | manjaro)
        pacman -Syu --noconfirm && pacman -S --noconfirm wget curl tar tzdata findutils
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata findutils
        ;;
    esac
}

config_after_install() {
    echo -e "${yellow}Install/update finished! For security it's recommended to modify panel settings ${plain}"
    read -p "Do you want to continue with the modification [y/n]?": config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        read -p "Please set up your username:" config_account
        echo -e "${yellow}Your username will be:${config_account}${plain}"
        read -p "Please set up your password:" config_password
        echo -e "${yellow}Your password will be:${config_password}${plain}"
        read -p "Please set up the panel port:" config_port
        echo -e "${yellow}Your panel port is:${config_port}${plain}"
        echo -e "${yellow}Initializing, please wait...${plain}"
        /usr/local/x-ui/x-ui setting -username "${config_account}" -password "${config_password}"
        echo -e "${yellow}Account name and password set successfully!${plain}"
        /usr/local/x-ui/x-ui setting -port "${config_port}"
        echo -e "${yellow}Panel port set successfully!${plain}"
    else
        echo -e "${red}cancel...${plain}"
        if [[ ! -f "/etc/x-ui/x-ui.db" ]]; then
            local usernameTemp
            local passwordTemp
            usernameTemp=$(head -c 6 /dev/urandom | base64)
            passwordTemp=$(head -c 6 /dev/urandom | base64)
            /usr/local/x-ui/x-ui setting -username "${usernameTemp}" -password "${passwordTemp}"
            echo -e "this is a fresh installation,will generate random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}username:${usernameTemp}${plain}"
            echo -e "${green}password:${passwordTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}if you forgot your login info,you can type x-ui and then type 8 to check after installation${plain}"
        else
            echo -e "${red} this is your upgrade,will keep old settings,if you forgot your login info,you can type x-ui and then type 8 to check${plain}"
        fi
    fi
    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/

    # ==== НАСТРОЙКИ ФОРКА ====
    VERSION="v2.3.3"
    FORK_OWNER="prooxyyy"
    FORK_REPO="3x-ui-wal"
    # Прямая ссылка, которую ты дал:
    FORK_TARBALL_URL="https://github.com/${FORK_OWNER}/${FORK_REPO}/archive/refs/tags/${VERSION}.tar.gz"

    # ==== ОРИГИНАЛ ДЛЯ ФОЛЛБЭКА ====
    UPSTREAM_OWNER="MHSanaei"
    UPSTREAM_REPO="3x-ui"

    ARCH="$(arch3xui)"
    ASSET_NAME="x-ui-linux-${ARCH}.tar.gz"
    echo -e "${yellow}Target asset: ${ASSET_NAME}${plain}"

    # 1) Пытаемся достать из твоего форка
    TMPDIR="$(mktemp -d -t 3xui-XXXXXX)"
    echo -e "${yellow}Downloading fork tarball: ${FORK_TARBALL_URL}${plain}"
    if wget -q --no-check-certificate -O "${TMPDIR}/fork.tar.gz" "${FORK_TARBALL_URL"; then
        tar -xzf "${TMPDIR}/fork.tar.gz" -C "${TMPDIR}"
        # ищем внутри архива готовый релизный архив под текущую арху
        FOUND_ASSET="$(find "${TMPDIR}" -type f -name "${ASSET_NAME}" | head -n1 || true)"
        if [[ -n "${FOUND_ASSET}" ]]; then
            echo -e "${green}Found ${ASSET_NAME} inside your fork. Using it.${plain}"
            cp -f "${FOUND_ASSET}" "/usr/local/${ASSET_NAME}"
            FROM="fork"
        else
            echo -e "${yellow}Did not find ${ASSET_NAME} inside the fork tarball. Will try upstream asset.${plain}"
            FROM="upstream"
        fi
    else
        echo -e "${yellow}Could not download your fork tarball. Will try upstream asset.${plain}"
        FROM="upstream"
    fi

    # 2) Если не нашли в форке — качаем с оригинального релиза бинарный архив
    if [[ "${FROM}" == "upstream" ]]; then
        UPSTREAM_URL="https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/releases/download/${VERSION}/${ASSET_NAME}"
        echo -e "Downloading upstream asset: ${UPSTREAM_URL}"
        wget -N --no-check-certificate -O "/usr/local/${ASSET_NAME}" "${UPSTREAM_URL}"
    fi

    if [[ ! -s "/usr/local/${ASSET_NAME}" ]]; then
        echo -e "${red}Download failed: ${ASSET_NAME} not present.${plain}"
        exit 1
    fi

    # чистим предыдущий инсталл
    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui || true
        rm -rf /usr/local/x-ui/
    fi

    # распаковываем готовый архив (даёт папку x-ui/)
    tar -xzf "/usr/local/${ASSET_NAME}" -C /usr/local/
    rm -f "/usr/local/${ASSET_NAME}"
    cd /usr/local/x-ui
    chmod +x x-ui
    chmod +x bin/xray-linux-"${ARCH}"

    # ставим сервис
    cp -f x-ui.service /etc/systemd/system/

    # тянем x-ui.sh сначала из твоего форка на тот же тег, если нет — из оригинала
    FORK_SCRIPT_URL="https://raw.githubusercontent.com/${FORK_OWNER}/${FORK_REPO}/${VERSION}/x-ui.sh"
    UPSTREAM_SCRIPT_URL="https://raw.githubusercontent.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/main/x-ui.sh"
    echo -e "${yellow}Downloading x-ui.sh from your fork tag ${VERSION}...${plain}"
    if ! wget -q --no-check-certificate -O /usr/bin/x-ui "${FORK_SCRIPT_URL}"; then
        echo -e "${yellow}Fork x-ui.sh not found on ${VERSION}, trying upstream main...${plain}"
        wget --no-check-certificate -O /usr/bin/x-ui "${UPSTREAM_SCRIPT_URL}"
    fi

    chmod +x /usr/local/x-ui/x-ui.sh || true
    chmod +x /usr/bin/x-ui

    config_after_install

    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui ${VERSION}${plain} installation finished, it is running now..."

    # уборка
    rm -rf "${TMPDIR}"
}

echo -e "${green}Running...${plain}"
install_base
install_x-ui "$1"
