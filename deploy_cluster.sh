#!/bin/bash

#
# Metadata
# Author: Roy Apsel
# Version: 1.0
# Description: Deploy "Slurm Cluster" on target Ubuntu 22.04 nodes, with NVIDIA Deepops repository.

#===============================================================================================================#

# Color codes: (white, green, red, yellow, none)
W='\033[1;37m'; G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; N='\033[0m';

# Error handling (trap errors and print message)
error_handler() { echo -e "An error occured at line $1."; exit 1; }
trap 'error_handler $LINENO' ERR && set -e

# Verify running as root (required)
test ! "$UID" == 0 && { echo -e "Must run as root."; exit 1; }

# Variables (initial & default)
soft_dir='/opt'
base_dir="`dirname $(realpath $0)`"

install_file="install_easybuild_lmod.sh"
ansible_callback="dense"
ansible_whitelist="timer,timestamp,log_plays"
ansible_log_path="/var/log/ansible.log"

controller_name='CHSLM01'
controller_ip='192.168.100.242'
worker_name='CHGPU01'
worker_ip='192.168.100.188'

if test ! "$1" == "-y"; then
	echo -e "\n${Y}Confirm the following configuration:${N}"
	echo -e "─────────────────────────────────────────"
	echo -e "Controller Hostname:      $controller_name"
	echo -e "Controller IP:            $controller_ip  "
	echo -e "Worker Hostname:          $worker_name    "
	echo -e "Worker IP:                $worker_ip      "
	echo -e "Software Install Dir:     $soft_dir       "
	echo -e "─────────────────────────────────────────"
	read -p "Continue? [y/n]: " confirm  &&  test "$confirm" == "y" || exit 1
fi

# Cluster ping response test
ping -c 1 $controller_ip >/dev/null 2>&1 || { echo -e "Cannot ping host $controller_ip, check manually."; exit 1; }
ping -c 1 $worker_ip >/dev/null 2>&1 || { echo -e "Cannot ping host $worker_ip, check manually."; exit 1; }

# Cluster root ssh access test
test "$(ssh $controller_ip "echo \$UID")" == "0" || { echo -e "Check ssh connection to root@$controller_ip"; exit 1; }
test "$(ssh $worker_ip "echo \$UID")" == "0" || { echo -e "Check ssh connection to root@$worker_ip"; exit 1; }

# Confirm nodes running on Ubunuu 22.04
ssh $controller_ip "grep -q 'Ubuntu 22.04' /etc/os-release" || { echo -e "Only 'Ubuntu 22.04' nodes are supported."; exit 1; }
ssh $worker_ip "grep -q 'Ubuntu 22.04' /etc/os-release" || { echo -e "Only 'Ubuntu 22.04' nodes are supported."; exit 1; }

# refresh local cache on cluster nodes
echo -e "${Y}Refreshing local repository cache...${N}"
ssh $controller_ip apt update -y >/dev/null 2>&1 || { echo -e "Failed to update local apt cache ($controller_name)"; exit 1; }
ssh $worker_ip apt update -y >/dev/null 2>&1 || { echo -e "Failed to update local apt cache ($worker_name)"; exit 1; }

# upgrade pending packages on cluster nodes
#echo -e "${Y}Upgrading system packages...${N}"
#ssh $controller_ip apt full-upgrade -y 2>/dev/null || { echo -e "Failed to upgrade apt packages ($controller_name)"; exit 1; }
#ssh $worker_ip apt full-upgrade -y 2>/dev/null || { echo -e "Failed to upgrade apt packages ($worker_name)"; exit 1; }

#===============================================================================================================#


# verify required packages are installed
echo -e "${Y}Verifying required packages are installed...${N}"
sudo apt install git sshpass python3-passlib python3-pip -y >/dev/null 2>&1 || { echo -e "${R}Error installing initial packages${N}"; exit 1;}

# install ansible globally with pip
echo -e "${Y}Verifying Ansible is installed with pip...${N}"
sudo pip3 install --upgrade ansible >/dev/null 2>&1 || { echo -e "${R}Error: ansible installation failed${N}"; exit 1; }

# cloning nvidia deepops repo
echo -e "${Y}Cloning Deepops repository...${N}"
cd $soft_dir		&&  git clone -q https://github.com/NVIDIA/deepops.git 2>/dev/null || true
cd $soft_dir/deepops	&&  git checkout -q tags/23.08

# configure hosts inventory    ( 1st vm slurm controller ,  2nd vm slurm gpu node )
mkdir -p $soft_dir/deepops/config
cp $soft_dir/deepops/config.example/inventory $soft_dir/deepops/config/inventory
sed -i "s/^\[slurm-master\]/\[slurm-master\]\n$controller_name ansible_host=$controller_ip/" $soft_dir/deepops/config/inventory
sed -i "s/^\[slurm-node\]/\[slurm-node\]\n$worker_name ansible_host=$worker_ip/" $soft_dir/deepops/config/inventory
#echo -e "ansible_user=root\nansible_ssh_private_key_file=/root/.ssh/id_rsa\nregistry_setup=false" >> $soft_dir/deepops/config/inventory

# install nvidia drivers on the gpu worker node
ansible-galaxy install -r roles/requirements.yml #2>/dev/null
ANSIBLE_STDOUT_CALLBACK=$ansible_callback \
ANSIBLE_CALLBACK_WHITELIST=$ansible_whitelist \
ANSIBLE_LOG_PATH=$ansible_log_path \
ansible-playbook -i config/inventory playbooks/nvidia-software/nvidia-driver.yml 2>/dev/null

echo -e "${Y}Checking NVIDIA driver details on worker node (nvidia-smi)${N}"
ssh $worker_ip type nvidia-smi 2>/dev/null \
	&& ssh $worker_ip nvidia-smi \
	|| echo -e "No GPU on worker node (continuing anyway)"
	
echo "" && sleep 4

#echo -e "exiting before slurm cluster installation && exit 1" 


#===============================================================================================================#
## trouble starts here

echo -e "${Y}Verifying cloud-init is removed... (please wait)${N}"
apt remove --purge cloud-init* -y &>/dev/null  #&&  rm -rf /etc/cloud 2>/dev/null
ssh $controller_ip apt remove --purge cloud-init* -y &>/dev/null  #&&  rm -rf /etc/cloud 2>/dev/null
ssh $worker_ip apt remove --purge cloud-init* -y &>/dev/null  #&&  rm -rf /etc/cloud 2>/dev/null

echo -e "${Y}Installing pip3 on cluster nodes... (please wait)${N}"
ssh $controller_ip apt install -y python3-pip &>/dev/null
ssh $worker_ip apt install -y python3-pip &>/dev/null

echo -e "${Y}Installing EasyBuild and lmod on cluster nodes... (please wait)${N}"
ssh $controller_ip "soft_dir='$soft_dir' bash -s" < $base_dir/$install_file &>/dev/null
ssh $worker_ip "soft_dir='$soft_dir' bash -s" < $base_dir/$install_file &>/dev/null

echo -e "${Y}Installing Docker on cluster nodes... (please wait)${N}"
ssh $controller_ip apt install -y docker.io &>/dev/null
ssh $worker_ip apt install -y docker.io &>/dev/null

# fix deprecated syntax in playbooks & roles
echo -e "\n${Y}Fixing Deepops' Playbooks and Roles...${N}"
sed -i 's/^- include:/- import_playbook:/' playbooks/slurm-cluster.yml
sed -i 's/^- include:/- import_playbook:/' playbooks/container/*.yml
sed -i 's/^- include:/- import_playbook:/' playbooks/slurm-cluster/*.yml
sed -i 's/include:/include_tasks:/' playbooks/container/*.yml
sed -i 's/include:/include_tasks:/' roles/nfs/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/nvidia_dcgm/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/slurm/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/ood-wrapper/tasks/*.yml

# fix broken docker playbook settings
sed -i '/^[[:space:]]*roles:/,/^[[:space:]]*environment:/ s/^/# /' playbooks/container/docker.yml
sed -i '/[[:space:]]*tasks:/,/^$/ s/^/#/' playbooks/container/docker.yml
sed -i '/container.registry/s/^/#/' playbooks/slurm-cluster.yml

# remove cloud-init checks from cluster settings
sed -i '/disable.*cloud/s/^/#/' playbooks/slurm-cluster.yml

# remove hpcsdk setup from cluster settings (replacing -e slurm_install_hpcsdk=false)
sed -i '/^-.*nvidia-hpc-sdk.yml/,/slurm_install_hpcsdk/ s/^/#/' playbooks/slurm-cluster.yml

# remove monitoring setup from cluster settings (replacing -e slurm_enable_monitoring=false)
sed -i '/^-.*prometheus/,/slurm_enable_monitoring/ s/^/#/' playbooks/slurm-cluster.yml
sed -i '/^-.*grafana/,/slurm_enable_monitoring/ s/^/#/' playbooks/slurm-cluster.yml
sed -i '/^-.*alertmanager/,/slurm_enable_monitoring/ s/^/#/' playbooks/slurm-cluster.yml
sed -i '/^-.*nvidia-dcgm-exporter/,/slurm_enable_monitoring/ s/^/#/' playbooks/slurm-cluster.yml

# remove open ondemand tool from cluster settings (replacing -e install_open_ondemand=false)
sed -i '/^-.*open-ondemand/,/install_open_ondemand/ s/^/#/' playbooks/slurm-cluster.yml

# remove gpu clocking feature in cluster settings (replacing -e allow_user_set_gpu_clocks=false)
sed -i '/^-.*gpu-clocks/,/allow_user_set_gpu_clocks/ s/^/#/' playbooks/slurm-cluster.yml

# remove lmod feature in cluster settings (replacing -e slurm_install_lmod=false)
sed -i '/^-.*lmod.yml/,/slurm_install_lmod/ s/^/#/' playbooks/slurm-cluster.yml

# remove nfs feature (replacing -e slurm_enable_nfs_client_nodes)
sed -i '/-.*nfs-server.yml/,/slurm_enable_nfs_client_nodes/ s/^/#/' playbooks/slurm-cluster.yml


### set config/config.yml file here (or use -e flags) ###


echo -e "\n${Y}Building Slurm Cluster (can take a while...)${N}"
ANSIBLE_STDOUT_CALLBACK=$ansible_callback \
ANSIBLE_CALLBACK_WHITELIST=$ansible_whitelist \
ANSIBLE_LOG_PATH=$ansible_log_path \
ansible-playbook playbooks/slurm-cluster.yml \
	-l slurm-cluster \
	-e slurm_enable_singularity=false \
	-e slurm_install_enroot=true \
	-e slurm_install_pyxis=true 2>/dev/null
sleep 4


# show gpu driver stats (if gpu exists)
if ssh $worker_ip type nvidia-smi &>/dev/null; then
	echo -e "${Y}\nTesting:${N} \"srun -N 1 -G 1 nvidia-smi\"\n"
	ssh $worker_ip srun -N 1 -G 1 nvidia-smi
fi

# show config summary with scontrol
echo -e "\n${Y}Slurm Cluster Settings${N}"
echo -e "─────────────────────────────────────────"
echo "Cluster Name:      $(ssh $controller_ip scontrol show config | grep -i '^clustername' | awk '{print $3}')"
echo "Slurm Version:     $(ssh $controller_ip scontrol show config | grep -i '^slurm_version' | awk '{print $3}')"
echo "Scheduler Type:    $(ssh $controller_ip scontrol show config | grep -i '^schedulertype' | awk '{print $3}')"
echo "Config File:       $(ssh $controller_ip scontrol show config | grep -i '^slurm_conf' | awk '{print $3}')"
echo -e "\nCompute Nodes:"
ssh $controller_ip "sinfo -N -h -o '  - %N (%T, %c cores, %m MB, %G)'"
echo -e "─────────────────────────────────────────\n"
echo -e "${G}Done.${N}"

