#!/bin/bash


################
## easybuild

setup_easybuild_git() {
	# install required dependencies & remove lmod if installed
	apt install -y python3-venv git gcc g++ make tcl lua-posix liblua5.2-dev curl lmod-

	# set up directory structure
	eb_base_dir='/opt/easybuild'

	rm -rf $eb_base_dir
	mkdir -p $eb_base_dir && cd $eb_base_dir

	# set up virtual env
	python3 -m venv $eb_base_dir/easybuild-venv
	source $eb_base_dir/easybuild-venv/bin/activate

	# clone easybuild repos
	git clone https://github.com/easybuilders/easybuild-framework
	git clone https://github.com/easybuilders/easybuild-easyblocks
	git clone https://github.com/easybuilders/easybuild-easyconfigs

	# install easybuild
	pip3 install ./easybuild-framework ./easybuild-easyblocks ./easybuild-easyconfigs

	# bootstrap easybuild
	eb --prefix="$eb_base_dir"

	## missing env settings...
}


################
## lmod

setup_lmod_git() {
	# install required packages
	apt install -y tcl tcl-dev lua5.2 liblua5.2-0 liblua5.2-dev

	# clone and install lmod (verion 8+)
	git clone https://github.com/TACC/Lmod.git /opt/lmod
	cd /opt/lmod
	./configure --prefix=/opt/lmod
	make install

	# create environment profile
	lmod_profile='/etc/profile.d/z00_lmod.sh'
	echo -e "# lmod env" > $lmod_profile
	echo -e "export LMOD_DIR=/opt/lmod" >> $lmod_profile
	echo -e "export PATH=\$LMOD_DIR/lmod/lmod/libexec:\$PATH" >> $lmod_profile
	#echo -e "export MODULEPATH=/opt/easybuild/modulefiles" >> $lmod_profile
	chmod +x $lmod_profile
}


## Install easybuild
#setup_easybuild_git
pip3 install easybuild

## Install lmod
setup_lmod_git


