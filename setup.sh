#!/usr/bin/env bash
#
# Steps :
# - Checks if rsa keypair exists if not create it
# - Upgrade system packages to latests stables
# - Set Timezone to Europe/Paris
# - Install git, sendmail, swift, htop, vim, sudo, add user to sudo group
# - Install docker and docker compose and do postinstall steps to run it with current user
# - Install Fail2ban copy a basic configuration
# - Change SSH default port to 2742 and disable remote root login
# - Install firewall allow ports : SSH, HTTP, HTTPS
# - Install gitlab-runner running with docker executor
# - Register gitlab runner with provided token
#
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Vars
USER="debian"
WORKDIR="/home/${USER}"
SSH_PORT=2747
# PUBLIC_SSH_KEY_PATH="/home/${USER}/.ssh/id_rsa.pub"
GITLAB_RUNNER_TOKEN="gitlab_runner_register_token"
PROJECTS=("git@github.com:tchartron/awesome-project.git", "git@github.com:tchartron/awesome-project-2.git")

# if [ ! -f "$PUBLIC_SSH_KEY_PATH" ]; then
#     echo -e "${RED}\n$PUBLIC_SSH_KEY_PATH does not exist, creating ssh keypair${NC}\n\n"
#     # ssh-keygen -t rsa -b 2048 -q -N ""
#     ssh-keygen -t rsa -b 2048
#     echo -e "${GREEN}\nKeypair created ${NC}\n\n"
#     exit 0;
# fi

# usermod -aG sudo $USER
#############################
######### DEFAULTS ##########
#############################
echo -e "${GREEN}\n######################## -- DEFAULTS -- ########################${NC}\n\n"
echo -e "${YELLOW}Upgrading packages${NC}\n"
sudo apt-get update && sudo apt-get upgrade -y
echo -e "Set Timezone${NC}\n"
sudo timedatectl set-timezone Europe/Paris

############################
########## UTILS ###########
############################
echo -e "${GREEN}\n######################## -- UTILS -- ########################${NC}\n\n"
echo -e "${YELLOW}Install git, swift, sendmail, htop, vim${NC}\n"
sudo apt-get install -y git \
                    sendmail \
                    python3-swiftclient \
                    htop \
                    vim
sudo systemctl start sendmail
sudo systemctl enable sendmail

############################
######### DOCKER ###########
############################
echo -e "${GREEN}\n######################## -- DOCKER -- ########################${NC}\n\n"
echo -e "${YELLOW}Install Docker${NC}\n"
sudo apt-get remove -y docker docker-engine docker.io containerd runc
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

echo -e "${YELLOW}Install Compose${NC}\n"
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Post install steps
echo -e "${YELLOW}Docker post install steps${NC}\n"
sudo groupadd docker
sudo usermod -aG docker $USER
sudo systemctl enable docker.service
sudo systemctl enable containerd.service

############################
######### SECURITY #########
############################
echo -e "${GREEN}\n######################## -- FAIL2BAN -- ########################${NC}\n\n"
echo -e "${YELLOW}Setup Fail2ban${NC}\n"
sudo apt-get install -y fail2ban
sudo systemctl start fail2ban
sudo systemctl enable fail2ban
sudo cp $(pwd)/fail2ban/custom.conf /etc/fail2ban/jail.d/custom.conf
sudo systemctl restart fail2ban
echo -e "${GREEN}\n######################## -- SSH -- ########################${NC}\n\n"
echo -e "${YELLOW}Change ssh port to ${SSH_PORT}${NC}\n"
sudo sed -i.bck "s/#Port 22/Port ${SSH_PORT}/g" /etc/ssh/sshd_config
echo -e "${YELLOW}Disable remote root login${NC}\n"
sudo sed -i.bck 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
sudo systemctl restart sshd
echo -e "${GREEN}\n######################## -- FIREWALL -- ########################${NC}\n\n"
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ${SSH_PORT}
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable
echo -e "${YELLOW}Current firewall status :${NC}\n"
sudo ufw status

cd $WORKDIR
##############################
######## GITLAB RUNNER #######
##############################
echo -e "${GREEN}\n######################## -- GITLAB RUNNER -- ########################${NC}\n\n"
cd $HOME
mkdir gitlab-runner
echo -e "${YELLOW}\nCreate gitlab runner docker container${NC}\n\n"
docker run -d --name gitlab-runner --restart always \
     -v /home/$USER/gitlab-runner/config:/etc/gitlab-runner \
     -v /var/run/docker.sock:/var/run/docker.sock \
     gitlab/gitlab-runner:latest
echo -e "${YELLOW}\nRegister created gitlab-runner${NC}\n\n"
docker run --rm -v /home/$USER/gitlab-runner/config:/etc/gitlab-runner gitlab/gitlab-runner register \
      --non-interactive \
      --executor "docker" \
      --docker-image alpine:latest \
      --url "https://gitlab.com/" \
      --registration-token "${GITLAB_RUNNER_TOKEN}" \
      --description "docker-gitlab-runner" \
      --tag-list "docker,staging" \
      --run-untagged="true" \
      --locked="false" \
      --access-level="not_protected"

##############################
########## PROJECTS ##########
##############################
echo -e "${GREEN}\n######################## -- CLONE PROJECTS -- ########################${NC}\n\n"
for PROJECT in ${PROJECTS[@]}; do
    echo -e "${YELLOW}\nCloning ${PROJECT}${NC}\n\n"
    git clone $PROJECT
done

##############################
########## PORTAINER #########
##############################
# echo -e "${GREEN}\n######################## -- PORTAINER -- ########################${NC}\n\n"
# docker volume create portainer_data
# docker run -d -p 8000:8000 -p 9443:9443 --name portainer \
#  --restart=always \
#  -v /var/run/docker.sock:/var/run/docker.sock \
#  -v portainer_data:/data \
#  portainer/portainer-ce:latest
