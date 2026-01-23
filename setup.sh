#!/bin/bash
set -euo pipefail  # Fail on errors and undefined variables

# Configuration 1
ENABLE_PASSWORDLESS_SUDO=true
INSTALL_GUI_TOOLS=false
GENERATE_SSH_KEYS=true
MIN_SPACE_GB=5
BACKUP_DIR="/root/system_setup_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/system_setup.log"
PING_TEST_IP="8.8.8.8"
PING_TEST_DOMAIN="example.com"

# Package Configuration
# System monitoring packages
SYSTEM_MONITORING_PACKAGES=(
    "htop=3.*"
    "atop=2.*"
    "sysstat=12.*"
    "smartmontools=7.*"
    "ncdu=1.*"
)

# Network tools packages
NETWORK_TOOLS_PACKAGES=(
    "net-tools"
    "nmap"
    "mtr"
    "inetutils-ping"
    "rsync"
    "lftp"
    "w3m"
    "lynx"
    "btop"
)

# Text/terminal tools packages
TEXT_TOOLS_PACKAGES=(
    "vim"
    "nano"
    "tmux"
    "tree"
    "less"
)

# Disk/FS tools packages
DISK_TOOLS_PACKAGES=(
    "lvm2"
    "xfsprogs"
    "gparted"
    "hdparm"
)

# Security/network packages
SECURITY_PACKAGES=(
    "wireguard-tools"
    "openssh-server"
)

# Misc utilities packages
MISC_UTILITIES_PACKAGES=(
    "unzip"
    "jq"
    "plocate"
    "neofetch"
    "mc"
    "git"
    "fuse"
    "libfuse2"
    "procps"
    "alpine"
    "curl"
    "mdadm"
    "xclip"
    "wrk"
    "vlc"
    "monit"
)

# GUI tools packages (optional)
GUI_TOOLS_PACKAGES=(
    "flameshot"
)

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Setup logging
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# System compatibility checks
if ! command -v apt >/dev/null 2>&1; then
    echo -e "${RED}This script requires apt package manager (Debian/Ubuntu)${NC}"
    exit 1
fi

# Check internet connectivity
if ! ping -c 1 "$PING_TEST_IP" >/dev/null 2>&1; then
    echo -e "${RED}No internet connectivity detected${NC}"
    exit 1
fi

# Check available disk space
AVAILABLE_SPACE_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE_GB" -lt "$MIN_SPACE_GB" ]; then
    echo -e "${RED}Not enough disk space. Need at least ${MIN_SPACE_GB}GB free.${NC}"
    exit 1
fi

# Create backup directory and backup existing configs
mkdir -p "$BACKUP_DIR"
echo -e "${CYAN}Creating backups in $BACKUP_DIR...${NC}"
for file in ~/.bashrc ~/.ssh/config /etc/sudoers; do
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/$(basename "$file").backup"
        echo -e "${GREEN}Backed up $file${NC}"
    fi
done

# Ensure script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root or with sudo${NC}" 
    exit 1
fi

# System Update & Upgrade
echo -e "${CYAN}Updating package lists...${NC}"
if ! apt update -y; then
    echo -e "${RED}Failed to update package lists. Check your internet connection and try again.${NC}"
    exit 1
fi

echo -e "${CYAN}Checking for upgradable packages...${NC}"
if ! apt list --upgradable 2>/dev/null | grep -q "upgradable"; then
    echo -e "${YELLOW}No packages to upgrade.${NC}"
else
    echo -e "${GREEN}Upgrading packages...${NC}"
    if ! DEBIAN_FRONTEND=noninteractive apt full-upgrade -y; then
        echo -e "${RED}Failed to upgrade packages. Please check the logs at $LOG_FILE${NC}"
        exit 1
    fi
fi

# Install essential packages with error handling and version pinning
echo -e "${CYAN}Installing system utilities...${NC}"
install_packages() {
    local all_packages=(
        "${SYSTEM_MONITORING_PACKAGES[@]}"
        "${NETWORK_TOOLS_PACKAGES[@]}"
        "${TEXT_TOOLS_PACKAGES[@]}"
        "${DISK_TOOLS_PACKAGES[@]}"
        "${SECURITY_PACKAGES[@]}"
        "${MISC_UTILITIES_PACKAGES[@]}"
    )

    local failed_packages=()
    for pkg in "${all_packages[@]}"; do
        pkg_name=$(echo "$pkg" | cut -d'=' -f1)
        if ! dpkg -l | grep -q "^ii  $pkg_name "; then
            echo -e "${BLUE}Installing $pkg...${NC}"
            if ! DEBIAN_FRONTEND=noninteractive apt install -y "$pkg"; then
                failed_packages+=("$pkg")
                echo -e "${RED}Failed to install $pkg${NC}"
            fi
        else
            echo -e "${YELLOW}$pkg_name is already installed, skipping...${NC}"
        fi
    done

    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo -e "${RED}Failed to install the following packages:${NC}"
        printf '%s\n' "${failed_packages[@]}"
        echo -e "${YELLOW}You may want to try installing these packages manually${NC}"
    fi
}
install_packages

# Install GUI tools only if X11 is detected and enabled
if [ "$INSTALL_GUI_TOOLS" = true ] && [ -n "${DISPLAY:-}" ]; then
    echo -e "${CYAN}Installing GUI tools...${NC}"
    local failed_gui_packages=()
    for pkg in "${GUI_TOOLS_PACKAGES[@]}"; do
        pkg_name=$(echo "$pkg" | cut -d'=' -f1)
        if ! dpkg -l | grep -q "^ii  $pkg_name "; then
            echo -e "${BLUE}Installing GUI tool: $pkg...${NC}"
            if ! DEBIAN_FRONTEND=noninteractive apt install -y "$pkg"; then
                failed_gui_packages+=("$pkg")
                echo -e "${RED}Failed to install GUI tool: $pkg${NC}"
            fi
        else
            echo -e "${YELLOW}GUI tool $pkg_name is already installed, skipping...${NC}"
        fi
    done
    
    if [ ${#failed_gui_packages[@]} -gt 0 ]; then
        echo -e "${RED}Failed to install the following GUI tools:${NC}"
        printf '%s\n' "${failed_gui_packages[@]}"
    fi
else
    echo -e "${YELLOW}Skipping GUI tools installation${NC}"
fi

# Remove unnecessary packages
echo -e "${CYAN}Cleaning up...${NC}"
DEBIAN_FRONTEND=noninteractive apt autoremove -y --purge

# Google Chrome setup
echo -e "${CYAN}Setting up Google Chrome...${NC}"
if dpkg -l | grep -q "^ii.*google-chrome-stable"; then
    echo -e "${YELLOW}Google Chrome is already installed, skipping...${NC}"
else
    CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
    echo -e "${BLUE}Downloading Google Chrome...${NC}"
    if wget -q --show-progress -O "$CHROME_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; then
        echo -e "${GREEN}Download completed${NC}"
        echo -e "${BLUE}Installing Google Chrome...${NC}"
        if dpkg -i "$CHROME_DEB"; then
            echo -e "${GREEN}Google Chrome installed successfully${NC}"
        else
            echo -e "${YELLOW}Fixing dependencies...${NC}"
            if DEBIAN_FRONTEND=noninteractive apt install -f -y; then
                echo -e "${GREEN}Dependencies fixed and Google Chrome installed${NC}"
            else
                echo -e "${RED}Failed to install Google Chrome dependencies${NC}"
            fi
        fi
        # Clean up downloaded file
        rm -f "$CHROME_DEB"
    else
        echo -e "${RED}Failed to download Google Chrome. Check your internet connection.${NC}"
    fi
fi

# Get actual user info
USER_HOME=$(eval echo ~"$SUDO_USER")
USER_NAME="$SUDO_USER"

# Configure passwordless sudo for the current user only if enabled
echo -e "${CYAN}Checking sudo configuration...${NC}"
if [ "$ENABLE_PASSWORDLESS_SUDO" = true ]; then
    echo -e "${YELLOW}Warning: Enabling passwordless sudo - this is not recommended for production systems${NC}"
    SUDOERS_ENTRY="$USER_NAME ALL=(ALL) NOPASSWD:ALL"
    if ! grep -q "^$SUDOERS_ENTRY$" /etc/sudoers; then
        if [ -d /etc/sudoers.d ]; then
            echo "$SUDOERS_ENTRY" | tee "/etc/sudoers.d/$USER_NAME-nopasswd" > /dev/null
            chmod 440 "/etc/sudoers.d/$USER_NAME-nopasswd"
            echo -e "${GREEN}Added passwordless sudo via /etc/sudoers.d/$USER_NAME-nopasswd${NC}"
        else
            echo "$SUDOERS_ENTRY" | EDITOR='tee -a' visudo >/dev/null
            echo -e "${GREEN}Added passwordless sudo directly to /etc/sudoers${NC}"
        fi
    else
        echo -e "${YELLOW}Passwordless sudo already configured for $USER_NAME${NC}"
    fi
else
    echo -e "${GREEN}Skipping passwordless sudo configuration${NC}"
fi

# SSH Key Generation (ed25519) if enabled
if [ "$GENERATE_SSH_KEYS" = true ]; then
    echo -e "${CYAN}Generating SSH keys for $USER_NAME...${NC}"
    if [ ! -f "$USER_HOME/.ssh/id_ed25519" ]; then
        sudo -u "$USER_NAME" mkdir -p "$USER_HOME/.ssh"
        sudo -u "$USER_NAME" chmod 700 "$USER_HOME/.ssh"
        
        # Generate key with increased security parameters
        sudo -u "$USER_NAME" ssh-keygen -t ed25519 -a 100 -f "$USER_HOME/.ssh/id_ed25519" -N "" -C "$USER_NAME@$(hostname)-$(date +%Y%m%d)" -q
        sudo -u "$USER_NAME" chmod 600 "$USER_HOME/.ssh/id_ed25519" "$USER_HOME/.ssh/id_ed25519.pub"
        
        echo -e "${GREEN}SSH public key (ed25519):${NC}"
        sudo -u "$USER_NAME" cat "$USER_HOME/.ssh/id_ed25519.pub"
    else
        echo -e "${YELLOW}SSH key already exists at $USER_HOME/.ssh/id_ed25519 - skipping generation${NC}"
    fi
else
    echo -e "${GREEN}Skipping SSH key generation${NC}"
fi

# SSH Configuration (secure defaults)
echo -e "${CYAN}Configuring SSH with secure defaults...${NC}"
sudo -u "$USER_NAME" tee "$USER_HOME/.ssh/config" > /dev/null <<EOF
# Global secure defaults
Host *
    StrictHostKeyChecking ask
    UserKnownHostsFile ~/.ssh/known_hosts
    IdentitiesOnly yes
    HashKnownHosts yes
    ForwardAgent no
    ForwardX11 no
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/control-%C
    ControlPersist 10m

# Example of a secure host configuration (commented out)
#Host myserver
#    HostName server.example.com
#    User myuser
#    IdentityFile ~/.ssh/id_ed25519
#    StrictHostKeyChecking yes
EOF

sudo -u "$USER_NAME" chmod 600 "$USER_HOME/.ssh/config"

# Configure custom PS1 prompt and aliases
echo -e "${CYAN}Setting up custom prompt and aliases...${NC}"
BASH_RC_CONTENT='
# Custom prompt
#PS1='"'"'\[\033[01;32m\][\t]\[\033[0m\] \[\033[01;35m\][\u@\h]\[\033[0m\] \[\033[01;33m\]\w\[\033[0m\]\$ '"'"'
#export PS1

PS1='"'"'\n\[\033[01;32m\]╭─[\t] \[\033[0m\][\[\033[01;34m\]\u\[\033[0m\]\[\033[01;35m\]@\h\[\033[0m\]]\n\[\033[01;33m\]╰─\w\[\033[0m\] \$ '"'"'
export PS1

# System aliases
alias alert='"'"'notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '"'"'"'"'"'"'"'"'s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'"'"'"'"'"'"'"'"')"'"'"'
alias egrep='"'"'egrep --color=auto'"'"'
alias fgrep='"'"'fgrep --color=auto'"'"'
alias grep='"'"'grep --color=auto'"'"'
alias k='"'"'kubectl'"'"'
alias ku='"'"'aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)'"'"'
alias l='"'"'ls -la --group-directories-first'"'"'
alias la='"'"'ls -A'"'"'
alias list='"'"'aws ec2 describe-instances --region us-east-1 --query "Reservations[*].Instances[*].{Instance:InstanceId,Name:Tags[?Key=='"'"'"'"'"'"'"'"'Name'"'"'"'"'"'"'"'"']|[0].Value,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,PublicDNS:PublicDnsName,Status:State.Name}" --output table'"'"'
alias list2='"'"'aws ec2 describe-instances --region us-east-1 --query "Reservations[*].Instances[*].{Instance:InstanceId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,Status:State.Name,Name:Tags[?Key==Name]|[0].Value}" --output table'"'"'
alias ll='"'"'ls -alF'"'"'
alias ls='"'"'ls --color=auto -CF'"'"'
alias m='"'"'sudo monit summary'"'"'
alias p='"'"'ping -c 3 77.88.44.242'"'"'  # Limit to 3 pings by default
alias pine='"'"'alpine'"'"'
alias s='"'"'sudo host_info_2.0_linux_amd64.sh --host'"'"'
alias start='"'"'aws ec2 start-instances --instance-ids $(aws ec2 describe-instances --filters Name=instance-state-name,Values=stopped --query "Reservations[*].Instances[*].InstanceId" --output text)'"'"'
alias stop='"'"'aws ec2 stop-instances --instance-ids $(aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text)'"'"'
alias t='"'"'ssh 55ve.l.time4vps.cloud'"'"'
# ====== terraform aliases =============================
alias ta='"'"'terraform apply -auto-approve'"'"'
alias td='"'"'terraform destroy -auto-approve'"'"'
alias ti='"'"'terraform init'"'"'
alias tp='"'"'terraform plan'"'"'
alias tv='"'"'terraform validate'"'"'
#==========================================================
alias u='"'"'sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y'"'"'
alias y='"'"'ssh student@std-ext-010-33.praktikum-services.tech'"'"'
alias pp='"'"'ping -c 3 ya.ru'"'"'

# ========== HISTORY CONFIGURATION ==========

# History file location
export HISTFILE=~/.bash_history

# History size
export HISTSIZE=100000
export HISTFILESIZE=200000

# Control what gets saved
export HISTCONTROL=ignoredups:erasedups:ignorespace

# Ignore specific commands
export HISTIGNORE="&:[ ]*:exit:ls:ll:la:clear"

# Timestamp format
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S - "

# Append to history file
shopt -s histappend

# Save commands immediately
if [ -n "${PROMPT_COMMAND:-}" ]; then
    PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"
else
    PROMPT_COMMAND="history -a; history -c; history -r"
fi

# Log to separate file for auditing
if [ -n "${PROMPT_COMMAND:-}" ]; then
    export PROMPT_COMMAND='"'"'{ date "+%Y-%m-%d %H:%M:%S  $(whoami)  $(history 1 | sed "s/^[ ]*[0-9]*[ ]*//g")"; } >> ~/.bash_eternal_history 2>/dev/null;'"'"'"$PROMPT_COMMAND"
else
    export PROMPT_COMMAND='"'"'{ date "+%Y-%m-%d %H:%M:%S  $(whoami)  $(history 1 | sed "s/^[ ]*[0-9]*[ ]*//g")"; } >> ~/.bash_eternal_history 2>/dev/null;'"'"'
fi

# ========== HISTORY ALIASES ==========

# Search history
alias h='"'"'history'"'"'
alias hg='"'"'history | grep'"'"'
alias hgi='"'"'history | grep -i'"'"'

# Show recent history
alias hr='"'"'history | tail -50'"'"'

# Show most used commands
alias topcmds='"'"'history | awk "{print \$2}" | sort | uniq -c | sort -rn | head -20'"'"'

# Clear history
alias clearhist='"'"'history -c && history -w'"'"'

# Export history to file
alias exphist='"'"'history -w ~/history_export_$(date +%Y%m%d_%H%M%S).txt'"'"'
'

# Check if content already exists
if ! sudo -u "$USER_NAME" grep -q "PS1='\\\[\\033\[01;32m\\\]" "$USER_HOME/.bashrc"; then
    echo "$BASH_RC_CONTENT" | sudo -u "$USER_NAME" tee -a "$USER_HOME/.bashrc" > /dev/null
    echo -e "${GREEN}Custom prompt and aliases added to $USER_HOME/.bashrc${NC}"
else
    echo -e "${YELLOW}Custom prompt already exists in $USER_HOME/.bashrc - skipping${NC}"
fi

# Install host_info_2.0_linux_amd64.sh to /usr/bin
echo -e "${CYAN}Installing host_info_2.0_linux_amd64.sh to /usr/bin...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_INFO_SCRIPT="$SCRIPT_DIR/host_info_2.0_linux_amd64.sh"
if [ -f "$HOST_INFO_SCRIPT" ]; then
    cp "$HOST_INFO_SCRIPT" /usr/bin/host_info_2.0_linux_amd64.sh
    chmod +x /usr/bin/host_info_2.0_linux_amd64.sh
    echo -e "${GREEN}Successfully installed host_info_2.0_linux_amd64.sh to /usr/bin${NC}"
else
    echo -e "${RED}Warning: host_info_2.0_linux_amd64.sh not found in script directory ($SCRIPT_DIR)${NC}"
    echo -e "${YELLOW}Skipping installation of host_info_2.0_linux_amd64.sh${NC}"
fi

# Install monitrc configuration
echo -e "${CYAN}Installing monitrc configuration...${NC}"
MONITRC_SOURCE="$SCRIPT_DIR/monitrc"
MONITRC_TARGET="/etc/monit/monitrc"
if [ -f "$MONITRC_SOURCE" ]; then
    # Create /etc/monit directory if it doesn't exist
    mkdir -p /etc/monit
    # Backup existing monitrc if it exists
    if [ -f "$MONITRC_TARGET" ]; then
        cp "$MONITRC_TARGET" "$MONITRC_TARGET.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}Backed up existing monitrc configuration${NC}"
    fi
    # Copy new monitrc
    cp "$MONITRC_SOURCE" "$MONITRC_TARGET"
    chmod 600 "$MONITRC_TARGET"
    echo -e "${GREEN}Successfully installed monitrc to $MONITRC_TARGET${NC}"
    
    # Validate monitrc configuration
    if command -v monit >/dev/null 2>&1; then
        echo -e "${BLUE}Validating monitrc configuration...${NC}"
        if monit -t; then
            echo -e "${GREEN}Monitrc configuration is valid${NC}"
            # Restart monit service if it's running
            if systemctl is-active --quiet monit; then
                echo -e "${BLUE}Restarting monit service...${NC}"
                if systemctl restart monit; then
                    echo -e "${GREEN}Monit service restarted successfully${NC}"
                else
                    echo -e "${RED}Failed to restart monit service${NC}"
                fi
            else
                echo -e "${YELLOW}Monit service is not running, starting it...${NC}"
                if systemctl start monit && systemctl enable monit; then
                    echo -e "${GREEN}Monit service started and enabled${NC}"
                else
                    echo -e "${YELLOW}Monit service could not be started (may need manual configuration)${NC}"
                fi
            fi
        else
            echo -e "${RED}Monitrc configuration validation failed. Please check the configuration.${NC}"
        fi
    else
        echo -e "${YELLOW}Monit is not installed or not in PATH. Configuration file installed but service not restarted.${NC}"
    fi
else
    echo -e "${RED}Warning: monitrc not found in script directory ($SCRIPT_DIR)${NC}"
    echo -e "${YELLOW}Skipping installation of monitrc${NC}"
fi

# Disable lightdm only if it exists
#if systemctl list-unit-files | grep -q lightdm.service; then
#    echo -e "${CYAN}Disabling lightdm...${NC}"
#    systemctl stop lightdm.service
#    systemctl disable lightdm.service
#else
#    echo -e "${YELLOW}lightdm not found, skipping${NC}"
#fi

# Apply changes to current session if possible
if [ -n "${SUDO_USER:-}" ] && [ "$(whoami)" = "$SUDO_USER" ]; then
    source "$USER_HOME/.bashrc"
    echo -e "${GREEN}Reloaded .bashrc for current session${NC}"
else
    echo -e "${YELLOW}To apply changes immediately, run: source ~/.bashrc${NC}"
fi

# Cleanup
echo -e "${CYAN}Performing final cleanup...${NC}"
apt clean
apt autoremove -y --purge

# Summarize actions taken
echo -e "\n${GREEN}Setup completed successfully${NC}"
echo -e "\n${PURPLE}Summary of actions:${NC}"
echo -e "1. ${CYAN}System updated and upgraded${NC}"
echo -e "2. ${CYAN}Essential packages installed${NC}"
echo -e "3. ${CYAN}Google Chrome installed${NC}"
if [ "$INSTALL_GUI_TOOLS" = true ] && [ -n "${DISPLAY:-}" ]; then
    echo -e "4. ${CYAN}GUI tools installed${NC}"
fi
if [ "$ENABLE_PASSWORDLESS_SUDO" = true ]; then
    echo -e "5. ${CYAN}Passwordless sudo configured (WARNING: not recommended for production)${NC}"
fi
if [ "$GENERATE_SSH_KEYS" = true ]; then
    echo -e "6. ${CYAN}SSH keys generated and secure configuration applied${NC}"
fi
echo -e "7. ${CYAN}host_info_2.0_linux_amd64.sh installed to /usr/bin${NC}"
echo -e "8. ${CYAN}monitrc configuration installed to /etc/monit/${NC}"
echo -e "9. ${CYAN}Backups created in: $BACKUP_DIR${NC}"
echo -e "10. ${CYAN}Logs available at: $LOG_FILE${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Review the logs at $LOG_FILE for any warnings or errors"
echo -e "2. Check the backups at $BACKUP_DIR"
if [ "$GENERATE_SSH_KEYS" = true ]; then
    echo -e "3. Add your public SSH key to remote servers if needed"
fi
echo -e "4. Log out and back in for all changes to take effect"

exit 0
