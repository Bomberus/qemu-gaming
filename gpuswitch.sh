#!/bin/bash
#BEGIN Variables#
gpu=01:00.0
xsession_stop="systemctl stop lxdm"
xsession_start="systemctl start lxdm"
#END Variables#

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`
echo "  _____ _____  _    _  _______          _______ _______ _____ _    _ "
echo " / ____|  __ \| |  | |/ ____\ \        / /_   _|__   __/ ____| |  | |"
echo "| |  __| |__) | |  | | (___  \ \  /\  / /  | |    | | | |    | |__| |"
echo "| | |_ |  ___/| |  | |\___ \  \ \/  \/ /   | |    | | | |    |  __  |"
echo "| |__| | |    | |__| |____) |  \  /\  /   _| |_   | | | |____| |  | |"
echo " \_____|_|     \____/|_____/    \/  \/   |_____|  |_|  \_____|_|  |_|"
echo ""                                                                     
echo "Pascal Maximilian Bremer"
echo "Easily switch between nvidia and vfio-drivers" 
echo ""                                                                      

if [[ $EUID -ne 0 ]]
then
	echo ${red}"ERROR: This script must be run as root"${reset}
	exit 1
fi

# Only works for vfio-pci <--> nouveau
# Parameter 1 = {vfio-pci | nouveau}
switch(){
	modprobe $1
	echo 0 > /sys/bus/pci/drivers_autoprobe

	# Gather relevant information of the device in BUS
	VENDOR=$(cat /sys/bus/pci/devices/0000\:${gpu}/vendor)
	DEVICE=$(cat /sys/bus/pci/devices/0000\:${gpu}/device)
	if [ -e /sys/bus/pci/devices/0000\:${gpu}/driver ]; then
		echo 0000:${gpu} > /sys/bus/pci/devices/0000\:${gpu}/driver/unbind
	fi
	                
	echo  $VENDOR $DEVICE > /sys/bus/pci/drivers/$1/new_id	       
	echo  $VENDOR $DEVICE > /sys/bus/pci/drivers/$1/remove_id

	echo 1 > /sys/bus/pci/drivers_autoprobe
}

showinfo(){
	echo "Detected following graphic cards"
	lspci -v | perl -ne '/VGA/../^$/ and /VGA|Kern/ and print'
}

read_driver(){
	lspci -v -s ${gpu} | grep "Kernel driver in use:" | awk -F ": " '{print $2}'
}

switch_menu(){
	echo "Select the new driver"
	echo "[1] nvidia"
	echo "[2] vfio-pci"
	echo "[3] nouveau"
	read -s -n 1 key_gpu
}

using_info(){
	echo ${green}"You are currently using the driver : "$(read_driver)${reset}
}

already_using(){
	echo "You are already using the driver"
}

nvidia_to_nouveau(){
	rmmod nvidia
	sleep 1
	modprobe nouveau
	sleep 1
}

nouveau_to_nvidia(){
	rmmod nouveau
	sleep 1
	modprobe nvidia
	sleep 1
}

switch_helper(){
	using_info
	switch_menu
	${xsession_stop}
	case "$(read_driver)" in
		"")
		case "${key_gpu}" in
			1)
			modprobe nvidia
			;;
			2)
			switch vfio-pci
			;;
			3)
			switch nouveau
			;;
		esac
		;;
		nvidia)
		case "${key_gpu}" in
			1)
			already_using
			;;
			2)
			rmmod nvidia_modeset
			nvidia_to_nouveau
			switch vfio-pci
			;;
			3)
			rmmod nvidia_modeset
			nvidia_to_nouveau
			;;
		esac
		;;
		vfio-pci)
		case "${key_gpu}" in
			1)
			switch nouveau
			nouveau_to_nvidia
			;;
			2)
			already_using
			;;
			3)
			switch nouveau
			;;
		esac
		;;
		nouveau)
		case "${key_gpu}" in
			1)
			nouveau_to_nvidia
			;;
			2)
			switch vfio-pci
			;;
			3)
			already_using
			;;
		esac
		;;
	esac
	using_info
	${xsession_start}
}

echo "Menu overview please press key"
echo "[1] Show Systeminfo"
echo "[2] Switch GPU (will restart XServer)"
echo "[3] Exit"

read -s -n 1 key

case "${key}" in
	1)
	showinfo
	;;
	2)
	switch_helper
	;;
	3)
	echo ${green}"Goodbye" ${reset}
	;;
esac
exit 0