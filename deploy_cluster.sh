#!/bin/bash

# verify necessary packages are installed
echo -e "Verifying required packages are installed..."
sudo apt install git sshpass python3-pip -y >/dev/null 2>&1 || { echo -e "Error installing initial packages"; exit 1;}

# install ansible globally with pip
echo -e "Verifying ansible is installed with pip..."
sudo pip3 install --upgrade ansible >/dev/null 2>&1 || { echo -e "Error: ansible installation failed"; exit 1; }

# cloning nvidia deepops repo
echo -e "Cloning deepops repository..."
cd /opt
git clone https://github.com/NVIDIA/deepops.git 2>/dev/null
cd /opt/deepops
git checkout tags/23.08

# configure hosts inventory    ( vm1 == slurm controller ,  vm2 == slurm gpu node )
mkdir -p /opt/deepops/config
cp /opt/deepops/config.example/inventory /opt/deepops/config/inventory
sed -i 's/^\[slurm-master\]/\[slurm-master\]\nvm1 ansible_host=192.168.76.33/' /opt/deepops/config/inventory
sed -i 's/^\[slurm-node\]/\[slurm-node\]\nvm2 ansible_host=192.168.76.34/' /opt/deepops/config/inventory
echo -e "ansible_user=root\nansible_ssh_private_key_file=/root/.ssh/id_rsa\nregistry_setup=false" >> /opt/deepops/config/inventory

# install nvidia drivers on the gpu node
ansible-galaxy install -r roles/requirements.yml
ansible-playbook -i config/inventory playbooks/nvidia-software/nvidia-driver.yml

echo -e "\nNVIDIA driver details on GPU worker node (nvidia-smi)\n"
ssh vm2 nvidia-smi && echo "" && sleep 5


#echo -e "exiting before slurm cluster installation"
#exit 1

#===========================================================================================================================#
## trouble starts here

# delete cloud-init entirely if installed (cloud-init can make issues with slurm as they share resources)
#echo -e "\nVerifying cloud-init is removed... (on all hosts)"
#apt remove --purge cloud-init* -y &>/dev/null  &&  rm -rf /etc/cloud 2>/dev/null
#ssh vm1 apt remove --purge cloud-init* -y &>/dev/null  &&  rm -rf #/etc/cloud 2>/dev/null
#ssh vm2 apt remove --purge cloud-init* -y &>/dev/null  &&  rm -rf #/etc/cloud 2>/dev/null

# install docker on the vms
#ssh vm1 apt install -y docker.io
#ssh vm2 apt install -y docker.io

# fixing broken playbooks
echo -e "Fixing yaml playbook files..."
sed -i 's/^- include:/- import_playbook:/' playbooks/slurm-cluster.yml
sed -i '/disable.*cloud/s/^/#/' playbooks/slurm-cluster.yml
sed -i '/container.registry/s/^/#/' playbooks/slurm-cluster.yml

sed -i 's/^- include:/- import_playbook:/' playbooks/container/*.yml
sed -i 's/^- include:/- import_playbook:/' playbooks/slurm-cluster/*.yml
sed -i 's/include:/include_tasks:/' playbooks/container/*.yml
sed -i '/^[[:space:]]*roles:/,/^[[:space:]]*environment:/ s/^/# /' playbooks/container/docker.yml
sed -i '/[[:space:]]*tasks:/,/^$/ s/^/#/' playbooks/container/docker.yml

sed -i 's/include:/include_tasks:/' roles/nfs/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/nvidia_dcgm/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/slurm/tasks/*.yml
sed -i 's/include:/include_tasks:/' roles/ood-wrapper/tasks/*.yml

# install missing packages on the vms
echo -e "\nInstalling missing dependencies..."
apt install -y python3-passlib &>/dev/null
#ssh vm1 apt install -y python3-passlib &>/dev/null
#ssh vm2 apt install -y python3-passlib &>/dev/null


### set config/config.yml file here ###


# install slurm-cluster
echo -e "Installing Slurm cluster..."
ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
