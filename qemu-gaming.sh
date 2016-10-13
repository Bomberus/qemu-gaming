#!/bin/bash
### ===== BEGIN Variables ===== ###
gpu=01:00.0
audio=01:00.1
args=""
sound_args=""
bind_dev=(02:00.0)

# network
gateway=192.168.178.1
ipv4=192.168.178.30/24
ipv6=2a02:8071:2e8c:0:2e7:dcd1:6456:8ff0/64
tap_dev=tap0
bridge_dev=br0
eth_dev=enp0s31f6
user=pmbremer

# CD Roms
cd_imgs=("/mnt/data/vm/virtio-win.iso")

# Harddrives
harddrives=("/mnt/windows/win.qcow2" "/mnt/data/vm/games.qcow2")

# Configuration 0 = no | 1 = yes
use_hw_audio=0
use_hugepages=1
max_cache=1000

### ===== END Variables ===== ###
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`
echo "   ____  ______ __  __ _    _         _____          __  __ _____ _   _  _____ ";
echo "  / __ \|  ____|  \/  | |  | |       / ____|   /\   |  \/  |_   _| \ | |/ ____|";
echo " | |  | | |__  | \  / | |  | |______| |  __   /  \  | \  / | | | |  \| | |  __ ";
echo " | |  | |  __| | |\/| | |  | |______| | |_ | / /\ \ | |\/| | | | |   \ | | |_ |";
echo " | |__| | |____| |  | | |__| |      | |__| |/ ____ \| |  | |_| |_| |\  | |__| |";
echo "  \___\_\______|_|  |_|\____/        \_____/_/    \_\_|  |_|_____|_| \_|\_____|";
echo "                                                                               ";
echo "                                                                               ";

setup_network(){
	ip tuntap add dev ${tap_dev} mode tap user ${user} group kvm

	ip link add name ${bridge_dev} type bridge
	ip link set ${bridge_dev} up
	ip link set ${tap_dev} up
	ip route flush dev ${eth_dev}
	ip route flush dev ${tap_dev}
	ip address flush dev ${eth_dev}
	ip address flush dev ${tap_dev}
	ip link set ${eth_dev} master ${bridge_dev}
	ip link set ${tap_dev} master ${bridge_dev}

	ip address add ${ipv4} dev ${bridge_dev}
	ip address add ${ipv6} dev ${bridge_dev}

	ip route add default via ${gateway} dev ${bridge_dev}
}
reset_network(){
	ip address flush dev ${bridge_dev}

	ip link set ${eth_dev} nomaster
	ip link set ${eth_dev} down
	ip link set ${eth_dev} up
	ip address add ${ipv4} dev ${eth_dev}
	ip address add ${ipv6} dev ${eth_dev}

	ip route add default via ${gateway} dev ${eth_dev}

	ip link delete ${bridge_dev} type bridge	
}

start_samba(){
	systemctl start smbd.service
	systemctl start nmbd.service
}

stop_samba(){
	systemctl stop smbd.service
	systemctl stop nmbd.service
}

usb_bind(){
	modprobe vfio-pci

	for dev in "${bind_dev[@]}"; do
        vendor=$(cat /sys/bus/pci/devices/0000\:$dev/vendor)
        device=$(cat /sys/bus/pci/devices/0000\:$dev/device)
        if [ -e /sys/bus/pci/devices/0000\:$dev/driver ]; then
            echo "0000:$dev" > /sys/bus/pci/devices/0000\:$dev/driver/unbind
        fi
        echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id
        args+=" -device vfio-pci,host=$dev"
	done
}

usb_unbind(){
	for dev in "${bind_dev[@]}"; do
        vendor=$(cat /sys/bus/pci/devices/0000\:$dev/vendor)
        device=$(cat /sys/bus/pci/devices/0000\:$dev/device)
		echo "${vendor} ${device}" > /sys/bus/pci/drivers/vfio-pci/remove_id
		echo 1 > /sys/bus/pci/devices/0000\:$dev/remove
		echo 1 > /sys/bus/pci/rescan
	done
}

add_drives(){
	Counter=0
	for dev in "${harddrives[@]}"; do
		args+=" -drive if=virtio,id=drive${Counter},file=$dev,format=qcow2,cache=none,aio=native"
		(( Counter++ ))
	done
	for dev in "${cd_imgs[@]}"; do
        args+=" -drive file=$dev,media=cdrom"
	done
}

add_software_audio(){
	args+=" -soundhw hda"
	args+=" -device ich9-usb-uhci3,id=uhci"
}

add_hw_audio(){
	args+=" -device vfio-pci,host=01:00.1,addr=09.1"
}

add_hugepages(){
	#If cache consumes more than 1 GB clean it !
	if [ $(free -m | awk 'NR==2{print $6}') -gt ${max_cache} ]; then
		sync && echo 3 > /proc/sys/vm/drop_caches
		echo "Memory cleaned. Remaining Cache size:"
		free -h | awk 'NR==2{print $6}'
	fi
	echo 4200 > /proc/sys/vm/nr_hugepages
	args+=" -mem-path /dev/hugepages"
}

remove_hugepages(){
	echo 0 > /proc/sys/vm/nr_hugepages
}

add_gpu(){
	args+=" -device vfio-pci,host=$gpu,addr=09.0,multifunction=on"
}

add_initial_args(){
	args+=" -serial none"
	args+=" -parallel none"
	args+=" -nodefaults"
	args+=" -nodefconfig"
	args+=" -no-user-config"
	args+=" -enable-kvm"
	args+=" -name Windows"
	args+=" -cpu host,kvm=off,hv_vapic,hv_time,hv_relaxed,hv_spinlocks=0x1fff,hv_vendor_id=sugoidesu "
	args+=" -smp sockets=1,cores=4,threads=2"
	args+=" -m 8096"
	args+=" -mem-prealloc"
	args+=" -device usb-ehci,id=ehci"
	args+=" -device nec-usb-xhci,id=xhci"
	args+=" -machine pc,accel=kvm,kernel_irqchip=on,mem-merge=off"
	args+=" -drive if=pflash,format=raw,file=/usr/share/ovmf/x64/ovmf_x64.bin"
	args+=" -rtc base=localtime,clock=host,driftfix=none"
	args+=" -boot order=c"
	args+=" -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:00"
	args+=" -netdev type=tap,id=net0,ifname=$tap_dev,script=no,downscript=no"
	args+=" -nographic"
}

start(){
	#Initializing
	add_initial_args
	add_gpu
	add_drives
	setup_network
	start_samba
	if [ $use_hugepages -eq 1 ]; then
		add_hugepages
	fi
	if [ $use_hw_audio -eq 0 ]; then
		QEMU_AUDIO_DRV="pa"
		QEMU_PA_SAMPLES="8192"
		QEMU_AUDIO_TIMER_PERIOD="99"
		QEMU_PA_SERVER="/run/user/1000/pulse/native"
		add_software_audio
	else
		add_hw_audio
	fi
	usb_bind
	
	#Start VM
	echo ${green} Starting VM ... ${reset}

	qemu-system-x86_64 ${args}

	echo ${green} Shuting down VM ... ${reset}
	
	#Reset
	if [ $use_hugepages == 1 ]; then
		remove_hugepages
	fi
	usb_unbind
	stop_samba
	reset_network
}

if [[ $EUID -ne 0 ]]
then
	echo ${red}"This script must be run as root"${reset}
	exit 1
fi


start
exit 0