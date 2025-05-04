#!/bin/bash

#===============================================================
#
# Metadata
# Author: Roy Apsel
# Version: 1.0
# Description: Deploy slurm cluster with deepops repository
#
#===============================================================

# Color codes: (white, green, red, yellow, none)
W='\033[1;37m'; G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; N='\033[0m';

# Error handling (trap errors and print message)
error_handler() { echo -e "An error occured at line $1."; exit 1; }
trap 'error_handler $LINENO' ERR && set -e

# Verify running as root (required)
test ! "$UID" == 0 && { echo -e "Must run as root."; exit 1; }

# Variables (initial)
export base_dir="`dirname $(realpath $0)`"
export install_file="install_easybuild_lmod.sh"
export soft_dir='/opt'

# Cluster nodes (set manually)
export controller_name='CHSLM01'
export controller_ip='192.168.76.33'

export worker_name='CHGPU01'
export worker_ip='192.168.76.34'

echo -e "\nConfirm the following configuration:"
echo -e "-----------------------------------------"
echo -e "Controller Hostname      : $controller_name"
echo -e "Controler IP             : $controller_ip  "
echo -e "Worker Hostname          : $worker_name    "
echo -e "Worker IP                : $worker_ip      "
echo -e "Software Install Dir     : $soft_dir       "
echo -e "-----------------------------------------"
read -p "Continue? [y/n]: " confirm  &&  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1


# Cluster ping response test
ping -c 1 $controller_ip >/dev/null 2>&1 || { echo -e "Cannot ping host $controller_ip, check manually."; exit 1; }
ping -c 1 $worker_ip >/dev/null 2>&1 || { echo -e "Cannot ping host $worker_ip, check manually."; exit 1; }

# Cluster root ssh access test
test "$(ssh $controller_ip "echo \$UID")" == "0" || { echo -e "Check ssh connection to root@$controller_ip"; exit 1; }
test "$(ssh $worker_ip "echo \$UID")" == "0" || { echo -e "Check ssh connection to root@$worker_ip"; exit 1; }

# Confirm nodes running on Ubunuu 22.04
#ssh $controller_ip "grep -q 'Ubuntu 22.04' /etc/os-release" || { echo -e "Only 'Ubuntu 22.04' nodes are supported."; exit 1; }
#ssh $worker_ip "grep -q 'Ubuntu 22.04' /etc/os-release" || { echo -e "Only 'Ubuntu 22.04' nodes are supported."; exit 1; }


#===============================================================


# verify necessary packages are installed
echo -e "${Y}Verifying required packages are installed...${N}"
sudo apt install git sshpass python3-passlib python3-pip -y >/dev/null 2>&1 \
	|| { echo -e "${R}Error installing initial packages${N}"; exit 1;}

# install ansible globally with pip
echo -e "${Y}Verifying ansible is installed with pip...${N}"
sudo pip3 install --upgrade ansible >/dev/null 2>&1 || { echo -e "${R}Error: ansible installation failed${N}"; exit 1; }

# cloning nvidia deepops repo
echo -e "${Y}Cloning deepops repository...${N}"
cd $soft_dir
git clone https://github.com/NVIDIA/deepops.git 2>/dev/null || true
cd $soft_dir/deepops
git checkout tags/23.08

# configure hosts inventory    ( 1st vm slurm controller ,  2nd vm slurm gpu node )
mkdir -p $soft_dir/deepops/config
cp $soft_dir/deepops/config.example/inventory $soft_dir/deepops/config/inventory
sed -i "s/^\[slurm-master\]/\[slurm-master\]\n$controller_name ansible_host=$controller_ip/" $soft_dir/deepops/config/inventory
sed -i "s/^\[slurm-node\]/\[slurm-node\]\n$worker_name ansible_host=$worker_ip/" $soft_dir/deepops/config/inventory
#echo -e "ansible_user=root\nansible_ssh_private_key_file=/root/.ssh/id_rsa\nregistry_setup=false" >> $soft_dir/deepops/config/inventory

# install nvidia drivers on the gpu worker node
ansible-galaxy install -r roles/requirements.yml
ansible-playbook -i config/inventory playbooks/nvidia-software/nvidia-driver.yml

echo -e "\n${Y}Checking NVIDIA driver details on worker node (nvidia-smi)${N}"
ssh $controller_ip type nvidia-smi 2>/dev/null \
	&& ssh $controller_ip nvidia-smi \
	|| echo -e "No GPU on worker node (continuing anyway)"
	
echo "" && sleep 4


#echo -e "exiting before slurm cluster installation"
#exit 1


#===============================================================================================================#
## trouble starts here

echo -e "${Y}Verifying cloud-init is removed... (please wait)${N}"
apt remove --purge cloud-init* -y &>/dev/null  #&&  rm -rf /etc/cloud 2>/dev/null
ssh $controller_ip apt remove --purge cloud-init* -y &>/dev/null  #&&  rm -rf /etc/cloud 2>/dev/null
ssh $worker_ip apt remove --purge cloud-init* -y &>/dev/null  #&&  rm -rf /etc/cloud 2>/dev/null

echo -e "\n${Y}Installing pip3 on cluster nodes... (please wait)${N}"
ssh $controller_ip apt install -y python3-pip #>/dev/null 2>&1
ssh $worker_ip apt install -y python3-pip #>/dev/null 2>&1

#echo -e "${Y}Installing required packages on cluster nodes${N}"
#ssh $controller_ip python3-venv git gcc g++ make tcl lua-posix liblua5.3-dev curl
#ssh $worker_ip python3-venv git gcc g++ make tcl lua-posix liblua5.3-dev curl

echo -e "${Y}Installing easybuild & lmod on cluster nodes... (please wait)${N}"
ssh $controller_ip bash < $base_dir/$install_file
ssh $worker_ip bash < $base_dir/$install_file

echo -e "\n${Y}Installing docker on all cluster nodes... (please wait)${N}"
ssh $controller_ip apt install -y docker.io >/dev/null 2>&1
ssh $worker_ip apt install -y docker.io >/dev/null 2>&1

# fix deprecated syntax in playbooks & roles
echo -e "${Y}\nFixing yaml playbooks and roles...${N}"
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


### set config/config.yml file here (or use -e flags) ###


echo -e "\n${Y}Installing Slurm cluster...${N}"
ansible-playbook playbooks/slurm-cluster.yml \
	-l slurm-cluster \
	-e slurm_enable_nfs_client_nodes=false \
	-e slurm_enable_singularity=false \
	-e slurm_install_enroot=true \
	-e slurm_install_pyxis=true
sleep 4


if ssh $controller_ip type nvidia-smi &>/dev/null; then
	echo -e "${Y}\nTesting:${N} \"srun -N 1 -G 1 nvidia-smi\"\n"
	ssh $controller_ip srun -N 1 -G 1 nvidia-smi
fi

echo -e "\n${Y}Slurm Cluster Settings${N}"
echo "Cluster Name:      $(ssh $controller_ip scontrol show config | grep -i '^clustername' | awk '{print $3}')"
echo "Slurm Version:     $(ssh $controller_ip scontrol show config | grep -i '^slurm_version' | awk '{print $3}')"
echo "Scheduler Type:    $(ssh $controller_ip scontrol show config | grep -i '^schedulertype' | awk '{print $3}')"
echo "Config File:       $(ssh $controller_ip scontrol show config | grep -i '^slurm_conf' | awk '{print $3}')"
echo -e "\nCluster Nodes:"
ssh $controller_ip "sinfo -N -h -o '  - %N (%T, %c cores, %m MB, %G)'"
echo "------------------------------------------"
echo -e "\n${G}Done.${N}"

