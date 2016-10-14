# qemu-gaming
This is a small project I experimented with alot. With QEMU and KVM and a secound graphics card it is actually possible to play games in a virtual machine with almost the same performance like a native windows system.

Please note this hole project is currently tested by me with some minor issues. If you have further questions about the procedures don't hesitate to contact me.

## Requirements
* A CPU that supports [IOMMU](https://en.wikipedia.org/wiki/List_of_IOMMU-supporting_hardware)
* Linux Kernel 4.4.x
* Edit mkinitcpio (Arch Linux) MODULES="vfio vfio_iommu_type1 vfio_pci vfio_virqfd"
* AUR Package [ovmf-git](https://aur.archlinux.org/packages/ovmf-git/)
* virtio-driver [Download](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/)

## How to install
Pretty simple, all the necessary files are in the repository including their proper save location.
Don't forget the system config files in the folder etc. Some games might not work without these modifications (e.g. Battlefield).
Please edit and configure the scripts to your liking.

### GPU-Switcher
A little tool to switch your graphics card driver. Please be careful because your XServer will be restarted to apply changes

### QEMU-Gaming
Tool that launches the QEMU process with all the necessary parameter. It also initializes the network stack so have a look at it before running it. 

## Architecture
![Architecture](https://raw.githubusercontent.com/Bomberus/qemu-gaming/master/Architecture.png "Architecture")

## Issues
* When you use the vfio-pci driver without running a VM the GPU fans spin up. Try to assign a proper driver (nvidia, nouveau) to stop them
* Software Audio is not working properly after a long gaming session
* Hardware Audio is broken atleast for my GTX 670
* Sometime when you start Windows you see a black screen. This means the graphic card was not correctly initialized and you might need to restart your PC.
