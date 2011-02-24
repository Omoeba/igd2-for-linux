#!/bin/bash

#All are under this directory
WORK_DIR="$HOME/linuxigd2_test"

#Where build softwares
BUILD_DIR="$WORK_DIR/builds"

#Where to clone sources
SRC_DIR="$WORK_DIR/src"

#Where to unpack device protection files
DP_SRC="$WORK_DIR/dp_files"

#log files
LOG_DIR="$WORK_DIR/logs"
DEBUG_LOG="$LOG_DIR/debug.txt"
LINUXIGD2_LOG="$LOG_DIR/linux_igd2.txt"
CP_TEST_LOG="$LOG_DIR/cp_test_log.txt"

#chroot for upnpd
LINUXIGD2_CHROOT="$WORK_DIR/linuxigd2_chroot"

#softwares and libraries
PREFIX="$WORK_DIR/installed_softwares"

#device protection snapshot
DP_SNAP="dp_snapshot_110211.tgz"
BRANCH_NAME="gupnp_with_dp"
PATCHSET_ID="110211001"
#100921001
LIBUPNP_SRC="$DP_SRC/libupnp-patched-1.6.6.tar.bz2"
LINUXIGD2_SRC="$DP_SRC/linuxigd2-0.8.tar.gz"

DISTRIB_ID="None"
#check operating system
if [ -n "`which lsb_release`" ]; then
	DISTRIB_ID=`lsb_release -si`
elif [ -f /etc/meego-release ]; then
	#MeeGo
	DISTRIB_ID="MeeGo"
else
	#other
	DISTRIB_ID="None"
fi

#DEBUG=1
COLORS=1
VERBOSE=1

#Add time at the beginning of the lines in log and redirect it to $1 or $DEBUG_LOG
pretty_log () {
	LOGFILE="$DEBUG_LOG"
	EXTRA=""
	if [ -n "$1" ]; then
		LOGFILE=$1
		if [ -n "$2" ]; then
			EXTRA=$2
		fi
	fi

	while read data
	do
		if [ "$DEBUG" ]; then
			echo "[$(date +'%H:%M:%S')]$EXTRA $data"
		fi
		echo "[$(date +'%H:%M:%S')]$EXTRA $data" >> $LOGFILE
		if [ "$LOGFILE" != "$DEBUG_LOG" ]; then
			echo "[$(date +'%H:%M:%S')]$EXTRA $data" >> $DEBUG_LOG
		fi
	done
}

#TODO: Add notify to debuglog!
#Normal
notify () {
	echo "`basename $0` `date +"%H:%M:%S"`: $1"
	echo -e "\n[`date +"%H:%M:%S"`] -> $1" >> $DEBUG_LOG
}

#Verbose
notifyv () {
	if [ "$VERBOSE" ]; then
		echo -e "`basename $0` `date +"%H:%M:%S"`:\t - $1"
	fi
	echo -e "\n[`date +"%H:%M:%S"`] -> $1" >> $DEBUG_LOG
}

#Warnings
notifyw () {
	if [ "$COLORS" ]; then
		echo "[01;34m`basename $0` `date +"%H:%M:%S"`: $1[0m"
	else
		echo "`basename $0` `date +"%H:%M:%S"`: $1"
	fi
	echo -e "\n[`date +"%H:%M:%S"`] -> $1" >> $DEBUG_LOG
}

#Errors
notifye () {
	if [ "$COLORS" ]; then
		echo "[01;31m`basename $0` `date +"%H:%M:%S"`: $1[0m"
	else
		echo "`basename $0` `date +"%H:%M:%S"`: $1"
	fi
	echo -e "\n[`date +"%H:%M:%S"`] -> $1" >> $DEBUG_LOG
	clean_up
}

test_return_values () {
	VALUES=${PIPESTATUS[*]}
	for i in $VALUES
	do
		#echo $i
		if [ "$i" -ne "0" ]; then
			notifye "Command returned $i, $*"
		fi
	done
}


prepare_host() {
	if [ ! -d $WORK_DIR ]; then
		echo  "'$WORK_DIR' is not exist, please create it with following command:"
		echo "mkdir $WORK_DIR"
	fi

	#Create directories and log files
	rm -Rf $LOG_DIR/*
	mkdir -p $LOG_DIR
	mkdir -p $DP_SRC
	mkdir -p $WORK_DIR/data
	mkdir -p $BUILD_DIR
	touch $LINUXIGD2_LOG $DEBUG_LOG $CP_TEST_LOG
	notify "Prepare host"

	#Create directories for chroot
	mkdir -p $LINUXIGD2_CHROOT/{lib,bin,etc,proc,dev,tmp}
	mkdir -p $LINUXIGD2_CHROOT/etc/linuxigd

	#PREFIX=$WORK_DIR/

	##check all required softwares in host
	REQUIRED_SOFTWARES="autoconf sudo libtool make"
	MISSING_SOFTWARES=""
	for i in $REQUIRED_SOFTWARES
	do
		if [ -z "`which $i`" ]; then
			MISSING_SOFTWARES="$MISSING_SOFTWARES $i, "
		fi
	done

	if [ -n "$MISSING_SOFTWARES" ]; then
		echo "$MISSING_SOFTWARES are required but not installed softwares. Install these before continue."
		exit 1
	fi


	# Test sudo
	sudo ls > /dev/null

	if [ -n "`pgrep upnpd`" ]; then
		notifyw "there is already upnpd running with pid `pgrep upnpd`, I will kill it"
		sudo pkill upnpd
		sleep 5
	fi

	#Test required files
	REQUIRED_FILES="$DP_SRC/gupnp_gssdp_patches_${PATCHSET_ID}.tgz $DP_SRC/gupnp_gupnp_patches_${PATCHSET_ID}.tgz $DP_SRC/gupnp_gupnp-tools_patches_${PATCHSET_ID}.tgz $LIBUPNP_SRC $LINUXIGD2_SRC"
	MISSING_FILES=""
	for i in $REQUIRED_FILES
	do
		if [ ! -f "$i" ]; then
			notifyv "No such file '$i'"
			MISSING_FILES="$MISSING_FILES $i, "
		fi
	done

	if [ -n "$MISSING_FILES" ]; then
		if [ -f $DP_SNAP ]; then
			notifyv " . . so, need to npack dp sources"
			tar -xzf $DP_SNAP -C $DP_SRC 2>&1 | pretty_log $DEBUG_LOG
		else
			notifye "No such file '$DP_SRC', please add valid path to \$DP_SRC"
		fi
	fi


	#Check is there is HOST_CONFIGURED file or similar and intall required softwares if not
	if [ ! -f "$WORK_DIR/.HOST_CONFIGURED" ]; then
		notify "Need root access to install required softwares"
		if [ "$DISTRIB_ID" == "Debian" ]; then
			#Debian
			sudo aptitude install libssl-dev git ldtp python-ldtp libgcrypt11 libgcrypt11-dev libgnutls26 libgnutls-dev libgnutls-dev gtk-doc-tools libsoup2.4-1 libsoup2.4-dev libsoup2.4-doc uuid-dev libgtk2.0-dev libglade2-dev
			touch "$WORK_DIR/.HOST_CONFIGURED"
		elif [ "$DISTRIB_ID" == "Ubuntu" ]; then
			#Ubuntu 10
			#Test ubuntu versions
			VER=`lsb_release -sr | cut -d. -f1`
			if [ "$VER" -eq "10" ]; then
				sudo aptitude install libssl-dev git ldtp python-ldpt libgcrypt11 libgcrypt11-dev libgnutls26 libgnutls-dev libgnutls-dev gtk-doc-tools libsoup2.4-1 libsoup2.4-dev libsoup2.4-doc uuid-dev libgtk2.0-dev libglade2-dev
			else
				sudo aptitude install libssl-dev git ldtp python-ldpt libgcrypt11 libgcrypt11-dev libgnutls13 libgnutls-dev libgnutls-dev gtk-doc-tools libsoup2.4-1 libsoup2.4-dev libsoup2.4-doc uuid-dev libgtk2.0-dev libglade2-dev
			fi
			touch "$WORK_DIR/.HOST_CONFIGURED"
		else
			notifyw "Can not configure host"
		fi
	fi
}


clone_hostap(){
	notify "Check sources"
	#Clone hostap
	if [ ! -d "$SRC_DIR/hostap" ]; then
		notifyv "Clone hostapd"
		git clone http://w1.fi/hostap.git $SRC_DIR/hostap 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
	else
		notifyv "hostapd already cloned"
	fi

	#Clone gssdp
	if [ ! -d "$SRC_DIR/gssdp" ]; then
		notifyv "Clone gssdp"
		git clone http://git.gitorious.org/gupnp/gssdp.git $SRC_DIR/gssdp 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
	else
		notifyv "gssdp already cloned"
	fi

	#CLone gupnp
	if [ ! -d "$SRC_DIR/gupnp" ]; then
		notifyv "Clone gupnp"
		git clone http://git.gitorious.org/gupnp/gupnp.git $SRC_DIR/gupnp 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
	else
		notifyv "gupnp already cloned"
	fi

	#Clone gupnp-tools
	if [ ! -d "$SRC_DIR/gupnp-tools" ]; then
		notifyv "Clone gupnp-tools"
		git clone http://git.gitorious.org/gupnp/gupnp-tools.git $SRC_DIR/gupnp-tools 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
	else
		notifyv "gupnp-tools already cloned"
	fi
}

patch_hostap(){
	notify "Prepare hostap sources"
	if [ ! -d "$SRC_DIR/hostap" ]; then
		notifye "No '$SRC_DIR/hostap', clone it first"
	elif [ ! -d "$BUILD_DIR/hostap" ]; then
		PATCH="`ls $DP_SRC/hostap_patches_*.tgz | head -1`"
		P=`pwd`

		notifyv "Copy hostap sources"
		git clone $SRC_DIR/hostap $BUILD_DIR/hostap 2>&1 | pretty_log $DEBUG_LOG
		cp $PATCH $BUILD_DIR/hostap/.
		cd $BUILD_DIR/hostap

		notifyv "Change hostapd branch to ${BRANCH_NAME}"
		git checkout -b ${BRANCH_NAME} 6195adda9b4306cda2b06b930c59c95832d026a9 2>&1 | pretty_log $DEBUG_LOG
		mkdir tmp_patches
		notifyv "Unpack hostapd patches"
		tar xzvf $PATCH -C tmp_patches 2>&1 | pretty_log $DEBUG_LOG
		notifyv "Patch hostap"
		git am tmp_patches/* 2>&1 | pretty_log $DEBUG_LOG
		test_return_values

		##
		#Fix libhostapd.pc
		##
		notifyv "Fix libhostapd.pc"
		sed "s#prefix=\/usr\/local#prefix=$PREFIX#g" hostapd/libhostapd.pc > kissa && mv kissa hostapd/libhostapd.pc
		sed 's/Cflags: -I${includedir}\/hostapd/Cflags: -I${includedir}/g' hostapd/libhostapd.pc > kissa && mv kissa hostapd/libhostapd.pc
		notifyv "Clean hostapd"
		rm -rf tmp_patches  2>&1 | pretty_log $DEBUG_LOG
		cd $P
	else
		notifyv "hostap already patched"
	fi
}

patch_gsources() {
	notify "Prepare gssdp, gupnp, and gupnp-tools sources"
	P=`pwd`
	#gssdp
	if [ ! -d "$SRC_DIR/gssdp" ]; then
		notifye "No '$SRC_DIR/gssdp', clone it first"
	elif [ ! -d "$BUILD_DIR/gssdp" ]; then
		PATCH="$DP_SRC/gupnp_gssdp_patches_${PATCHSET_ID}.tgz"
		if [ -f  "$PATCH" ]; then
			notifyv "Copy gssdp sources"
			git clone $SRC_DIR/gssdp $BUILD_DIR/gssdp  2>&1 | pretty_log $DEBUG_LOG
			cp $PATCH $BUILD_DIR/gssdp/.
			cd $BUILD_DIR/gssdp

			notifyv "Change gssdp branch to $BRANCH_NAME"
			git checkout -b ${BRANCH_NAME} fb8333c67483b5f245ab15bfd42907816d27c6fc  2>&1 | pretty_log $DEBUG_LOG
			mkdir tmp_patches

			notifyv "Unpack gssdp patches"
			tar xvzf gupnp_gssdp_patches_${PATCHSET_ID}.tgz -C tmp_patches  2>&1 | pretty_log $DEBUG_LOG

			notifyv "Patch gssdp"
			git am --whitespace=nowarn tmp_patches/* 2>&1 | pretty_log $DEBUG_LOG
			test_return_values

			notifyv "Clean gssdp"
			rm -rf tmp_patches  2>&1 | pretty_log $DEBUG_LOG
			cd $P
		else
			notifye "No such file '$PATCH'"
		fi
	else
		notifyv "gssdp already patched"
	fi

	#gupnp
	if [ ! -d "$SRC_DIR/gupnp" ]; then
		notifye "No '$SRC_DIR/gupnp', clone it first"
	elif [ ! -d "$BUILD_DIR/gupnp" ]; then
		PATCH="$DP_SRC/gupnp_gupnp_patches_${PATCHSET_ID}.tgz"
		if [ -f  $PATCH ]; then
			notifyv "Copy gupnp sources"
			git clone $SRC_DIR/gupnp $BUILD_DIR/gupnp  2>&1 | pretty_log $DEBUG_LOG
			cp $PATCH $BUILD_DIR/gupnp/.
			cd $BUILD_DIR/gupnp

			notifyv "Change gupnp branch to $BRANCH_NAME"
			git checkout -b ${BRANCH_NAME} 8a67704144db3bd994f23837ff000c65766c3d4d 2>&1 | pretty_log $DEBUG_LOG
			mkdir tmp_patches

			notifyv "Unpack gupnp patches"
			tar xvzf gupnp_gupnp_patches_${PATCHSET_ID}.tgz -C tmp_patches 2>&1 | pretty_log $DEBUG_LOG

			notifyv "Patch gupnp"
			git am --whitespace=nowarn tmp_patches/* 2>&1 | pretty_log $DEBUG_LOG
			test_return_values

			notifyv "Clean gupnp"
			rm -rf tmp_patches  2>&1 | pretty_log $DEBUG_LOG
			cd $P
		else
			notifye "No such file '$PATCH'"
		fi
	else
		notifyv "gupnp already patched"
	fi

	#gupnp-tools
	if [ ! -d "$SRC_DIR/gupnp-tools" ]; then
		notifye "No '$SRC_DIR/gupnp-tools', clone it first"
	elif [ ! -d "$BUILD_DIR/gupnp-tools" ]; then
		PATCH="$DP_SRC/gupnp_gupnp-tools_patches_${PATCHSET_ID}.tgz"
		if [ -f  $PATCH ]; then
			notifyv "Copy gupnp-tools sources"
			git clone $SRC_DIR/gupnp-tools $BUILD_DIR/gupnp-tools 2>&1 | pretty_log $DEBUG_LOG
			cp $PATCH $BUILD_DIR/gupnp-tools/.
			cd $BUILD_DIR/gupnp-tools

			notifyv "Change gupnp-tools branch to $BRANCH_NAME"
			git checkout -b ${BRANCH_NAME} 5bea76c0956ce85fd071bd20e491bd48747964aa 2>&1 | pretty_log $DEBUG_LOG
			mkdir tmp_patches

			notifyv "Unpack gupnp-tools patches"
			tar xvzf gupnp_gupnp-tools_patches_${PATCHSET_ID}.tgz -C tmp_patches 2>&1 | pretty_log $DEBUG_LOG

			notifyv "Patch gupnp-tools"
			git am --whitespace=nowarn tmp_patches/* 2>&1 | pretty_log $DEBUG_LOG
			test_return_values

			notifyv "Clean gupnp-tools"
			rm -rf tmp_patches 2>&1 | pretty_log $DEBUG_LOG
			cd $P
		else
			notifye "No such file '$PATCH'"
		fi
	else
		notifyv "gupnp-tools already patched"
	fi
}

build_and_install_hostapd() {
	notify "Build and install hostapd"
	if [ ! -f $PREFIX/lib/libhostapd.so ]; then
		P=`pwd`
		notifyv "build hostapd"
		cd $BUILD_DIR/hostap/hostapd
		PREFIX=$PREFIX make  2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		PREFIX=$PREFIX make libhostapd.so  2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		notifyv "Install hostapd"
		PREFIX=$PREFIX make install_hostapd  2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		cd $P
	else
		notifyv "libhostapd already installed"
	fi
}

build_and_install_wpa_supplicant() {
	notify "Build and install wpa_supplicant"
	if [ ! -f $PREFIX/lib/libwpa_supplicant.so ]; then
		P=`pwd`

		notifyv "Build wpa_supplicant"
		cd $BUILD_DIR/hostap/wpa_supplicant
		PREFIX=$PREFIX make  2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		PREFIX=$PREFIX make libwpa_supplicant.so  2>&1 | pretty_log $DEBUG_LOG
		test_return_values

		notifyv "Install wpa_supplicant"
		PREFIX=$PREFIX make install_libwpa_supplicant  2>&1 | pretty_log $DEBUG_LOG
		test_return_values

		## Create pc file
		notifyv "Create missing libwpa_supplicant.pc file"
		mkdir -p $PREFIX/lib/pkgconfig/
		echo "prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: libwpa_supplicant
Description: HostAP for WPA
Version: 0.1.0
Libs: -L\${libdir} -lwpa_supplicant
Cflags: -I\${includedir}" > $PREFIX/lib/pkgconfig/libwpa_supplicant.pc

		cd $P
	else
		notifyv "libwpa_supplicant already installed"
	fi
}

build_libupnp () {
	notify "Build and install libupnp"
	if [ ! -f "$PREFIX/lib/libupnp.so.3.0.5" ]; then
		if [ -f $LIBUPNP_SRC ]; then
			P=`pwd`
			tar -xjf $LIBUPNP_SRC -C $BUILD_DIR/
			cd $BUILD_DIR/libupnp-1.6.6

			notifyv "Build libupnp"
			PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig  autoreconf -v --install  2>&1 | pretty_log $DEBUG_LOG
			test_return_values
			PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig ./configure --prefix=$PREFIX 2>&1 | pretty_log $DEBUG_LOG
			test_return_values
			PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig make 2>&1 | pretty_log $DEBUG_LOG
			test_return_values

			notifyv "Install libupnp"
			PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig make install 2>&1 | pretty_log $DEBUG_LOG
			test_return_values

			cd $P
		else
			notifye "No such file '$LIBUPNP_SRC'"
		fi
	else
		notifyv "libupnp already installed"
	fi
}

build_linuxigd2 () {
	notify "Build linuxigd2"
	if [ -f $LINUXIGD2_SRC ]; then
		P=`pwd`
		tar -xzf $LINUXIGD2_SRC -C $BUILD_DIR/ 2> /dev/null
		cd $BUILD_DIR/linuxigd2-0.8

		#Fix Makefile
		notifyv "Change path to LIBUPNP_PREFIX in Makefile"
		sed "s#LIBUPNP_PREFIX=/usr/local#LIBUPNP_PREFIX=$PREFIX#g" Makefile > kissa && mv kissa Makefile

		notifyv "Build linuxigd2"
		make 2>&1 | pretty_log $DEBUG_LOG
		test_return_values

		cd $P
	else
		notifye "No such file or directory '$LINUXIGD2_SRC' "
	fi
}

umount_chroot() {
	CO=0
	while [ -n "`pgrep upnpd`" ];
	do
		CO=`expr $CO + 1`
		if [ "$CO" -gt "10" ]; then
			sudo pkill -9 upnpd
			notifye "Too hard to kill upnpd"
		else
			sudo pkill upnpd
		fi
		sleep 2
	done

	while [ -n "`mount | grep $LINUXIGD2_CHROOT/proc`" ]
	do
		notifyv "Unmount proc from chroot"
		sudo umount "$LINUXIGD2_CHROOT/proc"
	done

	while [ -n "`mount | grep $LINUXIGD2_CHROOT/dev`" ]
	do
		notifyv "Umount dev from chroot"
		sudo umount "$LINUXIGD2_CHROOT/dev"
	done
}

chroot_linuxigd2 () {
	#TODO: this is executed always, add check to avoid id
	notify "Create chroot for linuxigd2"
	if [ -f "$BUILD_DIR/linuxigd2-0.8/bin/upnpd" ]; then
		if [ -n "`pgrep upnpd`" ]; then
			notifyw "there is still upnpd running with pid `pgrep upnpd`, I will kill it"
			sudo pkill upnpd
		fi

		#Copy libs for chroot
		notifyv "Copy libraries to chroot"
		for i in `LD_LIBRARY_PATH=$PREFIX/lib/ ldd $BUILD_DIR/linuxigd2-0.8/bin/upnpd | awk '{print $3}' | grep ^/`; do echo $i;  cp $i $LINUXIGD2_CHROOT/lib/.; done  2>&1 | pretty_log $DEBUG_LOG
		echo /lib/libc.so.6  2>&1 | pretty_log $DEBUG_LOG
		echo /lib/ld-linux.so.2  2>&1 | pretty_log $DEBUG_LOG
		cp  /lib/libc.so.6 /lib/ld-linux.so.2 $LINUXIGD2_CHROOT/lib/.

		#Copy binaries to chroot
		notifyv "Copy binaries to chroot"
		cp $BUILD_DIR/linuxigd2-0.8/bin/upnpd $LINUXIGD2_CHROOT/bin
		cp /bin/sh $LINUXIGD2_CHROOT/bin/.

		notifyv "Copy upnpd settings to chroot"
		#settings
		cp $BUILD_DIR/linuxigd2-0.8/configs/ligd.gif $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/gatedesc.xml $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/ligd.gif $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/gatedesc.xml $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/gateconnSCPD.xml  $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/gateicfgSCPD.xml $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/lanhostconfigSCPD.xml $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/gateEthlcfgSCPD.xml $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/deviceprotectionSCPD.xml $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/dummy.xml $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/accesslevel.xml $LINUXIGD2_CHROOT/etc/linuxigd
		cp $BUILD_DIR/linuxigd2-0.8/configs/upnpd.conf $LINUXIGD2_CHROOT/etc
		cp $BUILD_DIR/linuxigd2-0.8/configs/upnpd_ACL.xml  $LINUXIGD2_CHROOT/etc

	else
		notifye "No such file o directory '$BUILD_DIR/linuxigd2-0.8/bin/upnpd'"
	fi
}

run_linuxigd2 () {
	notify "Run upnpd in chroot"
	if [ -f "$LINUXIGD2_CHROOT/bin/upnpd" ]; then
		sudo ls > /dev/null
		if [ -n "`pgrep upnpd`" ]; then
			notifyw "upnpd already running, try to kill it"
			sudo pkill upnpd
			sleep 5
		fi

		#select configuration
		if [ "$1" == "pin" ]; then
			notifyv "Configure upnpd to PIN method"
			sed "s/wps_config_methods = push_button/#wps_config_methods = push_button/g" $LINUXIGD2_CHROOT/etc/upnpd.conf > kissa && mv kissa $LINUXIGD2_CHROOT/etc/upnpd.conf
		else
			notifyv "Configure upnpd to PBC method"
			sed "s/#wps_config_methods = push_button/wps_config_methods = push_button/g" $LINUXIGD2_CHROOT/etc/upnpd.conf > kissa && mv kissa $LINUXIGD2_CHROOT/etc/upnpd.conf
		fi

		#Remove old mount if any
		umount_chroot

		notifyv "Mount /proc to $LINUXIGD2_CHROOT/proc"
		sudo mount -o bind /proc $LINUXIGD2_CHROOT/proc
		test_return_values

		notifyv "Mount /dev to $LINUXIGD2_CHROOT/dev"
		sudo mount -o bind /dev $LINUXIGD2_CHROOT/dev
		test_return_values

		notifyv "Run upnpd"
		echo "LC_ALL=\"C\" LC_CTYPE=\"C\" LANG=\"C\" chroot $LINUXIGD2_CHROOT upnpd -f eth0 eth0 >> $LINUXIGD2_LOG  2>&1 " | sudo sh &
		test_return_values

		sleep 10

		if [ -n "`pgrep upnpd`" ]; then
			notifyv "Upnpd is up and runnig"
		else
			notifye "Something went wrong, upnpd is not running"
		fi
	else
		notifyw "No upnpd in chroot"
	fi
}

build_gsources () {
	notify "Build gssdp, gupnp and gupnp-tools"
	P=`pwd`
	if [ ! -f "$PREFIX/lib/libgssdp-1.0.so.1.0.0" ]; then
		notifyv "build gssdp"
		cd $BUILD_DIR/gssdp
		PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig ./autogen.sh --prefix=$PREFIX 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		make 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		notifyv "Install gssdp"
		make install 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		cd $P
	else
		notifyv "gssdp already installed"
	fi

	if [ ! -f "$PREFIX/lib/libgupnp-1.0.so.2.0.0" ]; then
		notifyv "build gupnp"
		cd $BUILD_DIR/gupnp
		PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig ./autogen.sh --prefix=$PREFIX 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig make 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		notifyv "Install gupnp"
		make install 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		cd $P
	else
		notifyv "gupnp already installed"
	fi


	if [ ! -f "$PREFIX/bin/gupnp-universal-cp" ]; then
		notifyv "build gupnp-tools"
		cd $BUILD_DIR/gupnp-tools
		PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig ./autogen.sh --prefix=$PREFIX 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig make 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		notifyv "Install gupnp-tools"
		make install 2>&1 | pretty_log $DEBUG_LOG
		test_return_values
		cd $P
	else
		notifyv "gupnp-tools already installed"
	fi
}

pin_test() {
	#with pin method
	notify "Test PIN method"

	#Start upnpd
	notifyv "Start upnpd"
	run_linuxigd2 pin

	#Test gupnp-universal-cp
	if [ -f "$PREFIX/bin/gupnp-universal-cp" ]; then
		EX=1
		python pin_method_test.py $PREFIX/bin/gupnp-universal-cp 2>&1 | pretty_log $CP_TEST_LOG " PIN"
		EX=${PIPESTATUS[0]}
		if [ "$EX" -ne "0" ]; then
			notifyw "PIN test failed with exit value $EX, check $CP_TEST_LOG"
		else
			notifyv "PIN test succeed"
		fi
		notifyv "Kill upnpd"
		sudo pkill upnpd
		sleep 5
		umount_chroot

	else
		notifye "No such file or directory '$PREFIX/bin/gupnp-universal-cp'"
	fi
}

pbc_test() {
	#with pbc method
	notify "Test PBC method"

	#Start upnpd
	notifyv "Start upnpd"
	run_linuxigd2 pbc

	#Test gupnp-universal-cp
	if [ -f "$PREFIX/bin/gupnp-universal-cp" ]; then
		EX=1
		python pbc_method_test.py $PREFIX/bin/gupnp-universal-cp 2>&1 | pretty_log $CP_TEST_LOG " PBC"
		EX=${PIPESTATUS[0]}
		if [ "$EX" -ne "0" ]; then
			notifyw "PBC test failed with exit value $EX, check $CP_TEST_LOG"

		else
			notifyv "PBC test succeed"
		fi
		notifyv "Kill upnpd"
		sudo pkill upnpd
		sleep 5
		umount_chroot
	else
		notifye "No such file or directory '$PREFIX/bin/gupnp-universal-cp'"
	fi
}


clean_up () {
	notify "cleanup"
	sudo pkill upnpd
	sleep 3

	umount_chroot

	echo -e "\nTest took $SECONDS seconds\n"

	echo "Log files are:"
	echo $DEBUG_LOG
	echo $LINUXIGD2_LOG
	echo $CP_TEST_LOG
	exit 0
}

trap "clean_up" SIGHUP SIGINT SIGTERM


case "$1" in
all)

	prepare_host
	clone_hostap
	patch_hostap
	patch_gsources

	build_and_install_wpa_supplicant
	build_libupnp
	build_linuxigd2
	chroot_linuxigd2

	build_and_install_hostapd
	build_gsources

	sleep 5
	pin_test
	sleep 5
	pbc_test

	clean_up
	;;

upnpd_test)
	#Send ramdomly USR1 and USR2 to upnpd and sleep random time (0-5 sconds) between kills
	rm $LINUXIGD2_LOG
	touch $LINUXIGD2_LOG
	run_linuxigd2 pbc

	COUNT=0
	MAX=100
	while [ -n "`pgrep upnpd`" ]
	do
		sleep $((RANDOM%6))
		R=$((RANDOM%2))
		RAN=`expr $R + 1`
		sudo pkill -USR${RAN} upnpd
		echo "Run test $COUNT"
		if [ $MAX -gt $COUNT ]; then
			COUNT=`expr $COUNT + 1`
		else
			sudo pkill upnpd
		fi
	done

	clean_up
	echo "Log file is $LINUXIGD2_LOG"
	;;
*)
	echo usage:
	echo "./`basename $0` all"
	exit 1
	;;
esac
