#!/bin/bash
set -euo pipefail  # Fail on errors and undefined variables

# Configuration
ENABLE_PASSWORDLESS_SUDO=true
INSTALL_GUI_TOOLS=false
GENERATE_SSH_KEYS=true
MIN_SPACE_GB=5
BACKUP_DIR="/root/system_setup_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/system_setup.log"
PING_TEST_IP="8.8.8.8"
PING_TEST_DOMAIN="example.com"

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
    local packages=(
        # System monitoring
        "htop=3.*" "atop=2.*" "sysstat=12.*" "smartmontools=7.*" "ncdu=1.*"
        # Network tools
        "net-tools" "nmap" "mtr" "inetutils-ping" "rsync" "lftp" "w3m" "lynx"
        # Text/terminal tools
        "vim" "nano" "tmux" "tree" "less"
        # Disk/FS tools
        "lvm2" "xfsprogs"
        # Security/network
        "wireguard-tools" "openssh-server"
        # Misc utilities
        "unzip" "jq" "plocate" "neofetch" "mc" "git" "fuse" "libfuse2" "procps" "alpine" "curl" "mdadm" "xclip"
    )

    local failed_packages=()
    for pkg in "${packages[@]}"; do
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
    if ! DEBIAN_FRONTEND=noninteractive apt install -y flameshot; then
        echo -e "${RED}Failed to install GUI tools${NC}"
    fi
else
    echo -e "${YELLOW}Skipping GUI tools installation${NC}"
fi

# Remove unnecessary packages
echo -e "${CYAN}Cleaning up...${NC}"
DEBIAN_FRONTEND=noninteractive apt autoremove -y --purge

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
PS1='"'"'\[\033[01;32m\][\t]\[\033[0m\] \[\033[01;35m\][\u@\h]\[\033[0m\] \[\033[01;33m\]\w\[\033[0m\]\$ '"'"'
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
alias s='"'"'sudo ./_bin/script_v2.sh --host'"'"'
alias start='"'"'aws ec2 start-instances --instance-ids $(aws ec2 describe-instances --filters Name=instance-state-name,Values=stopped --query "Reservations[*].Instances[*].InstanceId" --output text)'"'"'
alias stop='"'"'aws ec2 stop-instances --instance-ids $(aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text)'"'"'
alias t='"'"'ssh 55ve.l.time4vps.cloud'"'"'
alias ta='"'"'terraform apply -auto-approve'"'"'
alias td='"'"'terraform destroy -auto-approve'"'"'
alias ti='"'"'terraform init'"'"'
alias tp='"'"'terraform plan'"'"'
alias tv='"'"'terraform validate'"'"'
alias u='"'"'sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y'"'"'
alias y='"'"'ssh student@std-ext-010-33.praktikum-services.tech'"'"'
alias z='"'"'ping -c 3 ya.ru'"'"'
'

# Check if content already exists
if ! sudo -u "$USER_NAME" grep -q "PS1='\\\[\\033\[01;32m\\\]" "$USER_HOME/.bashrc"; then
    echo "$BASH_RC_CONTENT" | sudo -u "$USER_NAME" tee -a "$USER_HOME/.bashrc" > /dev/null
    echo -e "${GREEN}Custom prompt and aliases added to $USER_HOME/.bashrc${NC}"
else
    echo -e "${YELLOW}Custom prompt already exists in $USER_HOME/.bashrc - skipping${NC}"
fi

# Disable lightdm only if it exists
if systemctl list-unit-files | grep -q lightdm.service; then
    echo -e "${CYAN}Disabling lightdm...${NC}"
    systemctl stop lightdm.service
    systemctl disable lightdm.service
else
    echo -e "${YELLOW}lightdm not found, skipping${NC}"
fi

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
if [ "$INSTALL_GUI_TOOLS" = true ] && [ -n "${DISPLAY:-}" ]; then
    echo -e "3. ${CYAN}GUI tools installed${NC}"
fi
if [ "$ENABLE_PASSWORDLESS_SUDO" = true ]; then
    echo -e "4. ${CYAN}Passwordless sudo configured (WARNING: not recommended for production)${NC}"
fi
if [ "$GENERATE_SSH_KEYS" = true ]; then
    echo -e "5. ${CYAN}SSH keys generated and secure configuration applied${NC}"
fi
echo -e "6. ${CYAN}Backups created in: $BACKUP_DIR${NC}"
echo -e "7. ${CYAN}Logs available at: $LOG_FILE${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Review the logs at $LOG_FILE for any warnings or errors"
echo -e "2. Check the backups at $BACKUP_DIR"
if [ "$GENERATE_SSH_KEYS" = true ]; then
    echo -e "3. Add your public SSH key to remote servers if needed"
fi
echo -e "4. Log out and back in for all changes to take effect"

exit 0
