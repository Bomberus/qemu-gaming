#!/bin/bash
### ===== BEGIN Variables ===== ###
gpu=01:00.0
audio=01:00.1
args=""
sound_args=""
bind_dev=("02:00.0")

# network
gateway=192.168.178.1
gateway_ipv6=2a02:8071:2e8c:0:ca0e:14ff:feab:7aef
ipv4=192.168.178.30/24
ipv6=2a02:8071:2e8c:0:2e7:dcd1:6456:8ff0/64
tap_dev=tap0
bridge_dev=br0
eth_dev=enp0s31f6
user=pmbremer

# CD Roms
cd_imgs=("/mnt/data/vm/virtio-win.iso") #"/mnt/data/vm/windows7.iso" "/mnt/data/vm/windows10.iso" "/mnt/data/vm/virtio-win.iso"

# Harddrives
harddrives=("/mnt/data/vm/games.qcow2") #"/mnt/data/vm/games.qcow2" "/mnt/windows/win.qcow2"
raw_drives=("/mnt/data/vm/windows.raw") #"/mnt/data/vm/windows7.raw"

# Configuration 0 = no | 1 = yes
use_hw_audio=0
max_cache=1000
use_fallback=0
SPICE_PORT=5555

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
echo " By Pascal Maximilian Bremer "
echo " https://github.com/Bomberus/qemu-gaming"


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
	ip -6 address add ${ipv6} dev ${bridge_dev}

	ip route add default via ${gateway} dev ${bridge_dev}
	ip -6 route add default via ${gateway_ipv6} dev ${bridge_dev}
}
reset_network(){
	ip address flush dev ${bridge_dev}

	ip link set ${eth_dev} nomaster
	ip link set ${eth_dev} down
	ip link set ${eth_dev} up
	ip address add ${ipv4} dev ${eth_dev}
	ip -6 address add ${ipv6} dev ${eth_dev}

	ip route add default via ${gateway} dev ${eth_dev}
	ip -6 route add default via ${gateway_ipv6} dev ${eth_dev}

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
	echo "Binding ROOT USB HUB to VFIO"
	for dev in "${bind_dev[@]}"; do
        vendor=$(cat /sys/bus/pci/devices/0000\:${dev}/vendor)
        device=$(cat /sys/bus/pci/devices/0000\:${dev}/device)
        if [ -e /sys/bus/pci/devices/0000\:${dev}/driver ]; then
                echo 0000\:${dev} > /sys/bus/pci/devices/0000\:${dev}/driver/unbind
        fi
        echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id
        args+=" -device vfio-pci,host=${dev}"
	done

	sleep 1
}

usb_unbind(){
	echo "Binding ROOT USB HUB to XHCI-PCI"
	for dev in "${bind_dev[@]}"; do
        vendor=$(cat /sys/bus/pci/devices/0000\:${dev}/vendor)
        device=$(cat /sys/bus/pci/devices/0000\:${dev}/device)
		echo "${vendor} ${device}" > /sys/bus/pci/drivers/vfio-pci/remove_id
		echo 1 > /sys/bus/pci/devices/0000\:${dev}/remove
		echo 1 > /sys/bus/pci/rescan
		echo 1 > /sys/bus/pci/drivers_autoprobe
	done

}

add_drives(){
	Counter=0
	for dev in "${harddrives[@]}"; do
		args+=" -drive if=virtio,id=drive${Counter},file=$dev,format=qcow2,cache=none,aio=native"
		(( Counter++ ))
	done
	for dev in "${raw_drives[@]}"; do
		args+=" -drive if=virtio,id=drive${Counter},file=$dev,format=raw,cache=none,aio=native"
		(( Counter++ ))
	done
	Counter=0
	for dev in "${cd_imgs[@]}"; do
        args+=" -drive file=$dev,media=cdrom,if=ide,id=cd$Counter,readonly"
        (( Counter++ ))
	done
}

add_software_audio(){
	args+=" -soundhw hda"
	args+=" -device ich9-usb-uhci3,id=uhci"
}

add_hw_audio(){
	args+=" -device vfio-pci,host=$audio,addr=09.1"
}

add_gpu(){
	args+=" -device vfio-pci,host=$gpu,addr=09.0,multifunction=on"
	args+=" -nographic"
}


add_initial_args(){
	#If cache consumes more than 1 GB clean it !
	if [ $(free -m | awk 'NR==2{print $6}') -gt ${max_cache} ]; then
		sync && echo 3 > /proc/sys/vm/drop_caches
		echo "Memory cleaned. Remaining Cache size:"
		free -h | awk 'NR==2{print $6}'
	fi
	echo 4200 > /proc/sys/vm/nr_hugepages

	args+=" -serial none"
	args+=" -parallel none"
	args+=" -nodefaults"
	args+=" -nodefconfig"
	args+=" -no-user-config"
	args+=" -enable-kvm"
	args+=" -name Windows"
	args+=" -cpu host,kvm=off,hv_vapic,hv_time,hv_relaxed,hv_spinlocks=0x1fff,hv_vendor_id=sugoidesu"
	args+=" -smp sockets=1,cores=4,threads=2"
	args+=" -m 8096"
	args+=" -mem-path /dev/hugepages"
	args+=" -mem-prealloc"
	#args+=" -device usb-ehci,id=ehci"
	args+=" -device nec-usb-xhci,id=xhci"
	args+=" -machine pc,accel=kvm,kernel_irqchip=on,mem-merge=off"
	args+=" -drive if=pflash,format=raw,file=/usr/share/ovmf/x64/ovmf_x64.bin"
	args+=" -rtc base=localtime,clock=host,driftfix=none"
	args+=" -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:00"
	args+=" -netdev type=tap,id=net0,ifname=$tap_dev,script=no,downscript=no"
	args+=" -boot order=c"	
}

start(){
	#Initializing
	add_initial_args
	add_drives
	if [ $use_fallback -eq 1 ]; then
		args+=" -vga std -display sdl"
		#args+=" -vga qxl -spice addr=127.0.0.1,port=${SPICE_PORT},disable-ticketing,playback-compression=off"
		#args+=" -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0"
		#args+=" -chardev spicevmc,id=spicechannel0,name=vdagent"
		#exec spicy --title Windows 127.0.0.1 -p ${SPICE_PORT}&
	else
		add_gpu
	fi
	#setup_network
	start_samba
	if [ $use_hw_audio -eq 0 ]; then
		export QEMU_AUDIO_DRV="pa"
		export QEMU_PA_SAMPLES="8192"
		export QEMU_AUDIO_TIMER_PERIOD="99"
		export QEMU_PA_SERVER="/run/user/1000/pulse/native"
		add_software_audio
	else
		add_hw_audio
	fi
	usb_bind
	
	#Start VM
	echo ${green} Starting VM ... ${reset}

	#args+=" &"

	qemu-system-x86_64 $args

	echo $args

	echo ${green} Shuting down VM ... ${reset}
	
	#Reset
	echo 0 > /proc/sys/vm/nr_hugepages
	usb_unbind
	stop_samba
	#reset_network
}

if [[ $EUID -ne 0 ]]; then
	echo ${red} This script must be run as root ${reset}
	exit 1
fi


menu(){
	echo "Menu overview please press key"
	echo "[1] Start VM"
	echo "[2] Setup Network"
	echo "[3] Kill Network"
	echo "[4] Exit"

	read -s -n 1 key

	case "${key}" in
		1)
		start
		;;
		2)
		setup_network
		menu
		;;
		3)
		reset_network
		menu
		;;
		4)
		exit 0
		;;
	esac
}

menu

exit 0