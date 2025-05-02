#!/bin/bash

#===============================================================
#
# Metadata
# Author: Roy Apsel
# Version: 1.0
# Description: Deploy slurm cluster with deepops repository
#
#===============================================================

# Color codes: (green, red, yellow, none)
G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; N='\033[0m';

# Error handling (trap errors and print message)
error_handler() { echo -e "${N}An error occured at line $1.${N}"; exit 1; }
trap 'error_handler $LINENO' ERR && set -e

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
cd /opt
git clone https://github.com/NVIDIA/deepops.git 2>/dev/null || true
cd /opt/deepops
git checkout tags/23.08

# configure hosts inventory    ( vm1 == slurm controller ,  vm2 == slurm gpu node )
mkdir -p /opt/deepops/config
cp /opt/deepops/config.example/inventory /opt/deepops/config/inventory
sed -i 's/^\[slurm-master\]/\[slurm-master\]\nvm1 ansible_host=192.168.76.33/' /opt/deepops/config/inventory  # controller
sed -i 's/^\[slurm-node\]/\[slurm-node\]\nvm2 ansible_host=192.168.76.34/' /opt/deepops/config/inventory      # worker
#echo -e "ansible_user=root\nansible_ssh_private_key_file=/root/.ssh/id_rsa\nregistry_setup=false" >> /opt/deepops/config/inventory

# install nvidia drivers on the gpu worker node
ansible-galaxy install -r roles/requirements.yml
ansible-playbook -i config/inventory playbooks/nvidia-software/nvidia-driver.yml

echo -e "\n${Y}NVIDIA driver details on GPU worker node (nvidia-smi)${N}\n"
ssh vm2 nvidia-smi && echo "" && sleep 5


#echo -e "exiting before slurm cluster installation"
#exit 1


#===============================================================================================================#
## trouble starts here

# delete cloud-init entirely if installed (cloud-init can make issues with slurm as they share resources)
echo -e "\n${Y}Verifying cloud-init is removed... (please wait)${N}"
apt remove --purge cloud-init* -y &>/dev/null  &&  rm -rf /etc/cloud 2>/dev/null
ssh vm1 apt remove --purge cloud-init* -y &>/dev/null  &&  rm -rf #/etc/cloud 2>/dev/null
ssh vm2 apt remove --purge cloud-init* -y &>/dev/null  &&  rm -rf #/etc/cloud 2>/dev/null

# install docker on the destination vm
echo -e "\n${Y}Verifying docker is installed on all cluster nodes... (please wait)${N}"
ssh vm1 apt install -y docker.io
ssh vm2 apt install -y docker.io

# fix broken playbooks & roles deprecated syntax
echo -e "${Y}\nFixing yaml playbooks and roles...${N}"
sed -i 's/^- include:/- import_playbook:/' playbooks/slurm-cluster.yml
sed -i 's/^- include:/- import_playbook:/' playbooks/container/*.yml
sed -i 's/^- include:/- import_playbook:/' playbooks/slurm-cluster/*.yml
sed -i 's/include:/include_tasks:/' playbooks/container/*.yml
sed -i 's/include:/include_tasks:/' roles/nfs/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/nvidia_dcgm/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/slurm/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/ood-wrapper/tasks/*.yml

# fix broken docker playbook and cluster settings
sed -i '/^[[:space:]]*roles:/,/^[[:space:]]*environment:/ s/^/# /' playbooks/container/docker.yml
sed -i '/[[:space:]]*tasks:/,/^$/ s/^/#/' playbooks/container/docker.yml
sed -i '/container.registry/s/^/#/' playbooks/slurm-cluster.yml

# remove cloud-init checks from cluster settings
sed -i '/disable.*cloud/s/^/#/' playbooks/slurm-cluster.yml


### set config/config.yml file here ###


echo -e "\n${Y}Installing Slurm cluster...${N}"
ansible-playbook playbooks/slurm-cluster.yml \
	-l slurm-cluster \
	-e slurm_enable_nfs_client_nodes=false \
	-e slurm_install_lmod=false \
	-e slurm_install_hpcsdk=false \
	#-e slurm_install_monitoring=false \
	-e slurm_install_enroot=true \
	-e slurm_install_pyxis=true


