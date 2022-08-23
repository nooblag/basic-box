.PHONY: image usb
.SILENT: image usb
.ONESHELL: usb
.DEFAULT_GOAL := usb

firmware_iwlwifi_deb = 'firmware-iwlwifi_20210315-3_all.deb'

image:
	bash get_extra_downloads.sh
	build-simple-cdd --conf basic.conf --verbose
	# On Debian 11, simple-cdd 0.6.8 fails to add a symlink to the first
	# firmware package (by alphabetical order), so add this symlink to the iso
	# after simple-cdd has built it.
	xorriso \
		-boot_image isolinux patch \
		-dev images/debian-11-amd64-CD-1.iso \
		-lns \
			../pool/non-free/f/firmware-nonfree/$(firmware_iwlwifi_deb) \
			firmware/$(firmware_iwlwifi_deb)


usb: SHELL := /bin/bash
usb: image
	# find the last inserted USB drive and write ISO to it
	# we need superuser access to deal with `fdisk` so explain that first and obtain permission if need be
	# use `true` as a command to invoke with sudo that will always be 'successful'
	if [[ $$EUID != 0 ]]; then
	  if ! sudo --prompt "This script requires sudo to interact with USB devices. Please enter your password to continue: " true; then
	    >&2 echo "Getting sudo privileges was not successful. Stopping."
	    exit 1
	  fi
	fi

	# fetch last disk by pattern matching `fdisk`
	last_disk="$$(sudo fdisk --list | awk -F '[ :]' '$$0 ~ "^Disk /dev/" {path=$$2} END {print path}')"
	boot_partition="$$(findmnt --noheadings --output source --target /boot)"
	this_partition="$$(findmnt --noheadings --output source --target "$${0}")"
	# use inverted `lsblk` tree to find which disks above partitions are on
	boot_disk="$$(lsblk --noheadings --inverse --output type,path $${boot_partition} 2>/dev/null | awk '$$1 == "disk" {print $$2; exit;}')"
	this_disk="$$(lsblk --noheadings --inverse --output type,path $${this_partition} 2>/dev/null | awk '$$1 == "disk" {print $$2; exit;}')"

	# do some tests to ensure we've got something useful to work with in terms of discerning a last inserted USB device
	if [[ -z "$${last_disk}" ]] || \
	   [[ "$${last_disk}" == "$${this_disk}" ]] || \
	   [[ "$${last_disk}" == "$${boot_disk}" ]] || \
	   ! lsblk --raw --noheadings --output tran,type,rm "$${last_disk}" | grep --basic-regexp --quiet '^usb disk 1'; then
	    >&2 echo "No usable device found. Please insert a USB disk and try again."
	    exit 2
	fi

	target_device="$${last_disk}"
	# print ANSI escape codes to bold and underline the USB device node path
	printf '\n%s \033[1m\033[4m%s\033[0m\n' "Writing ISO file to USB disk at" $${target_device}
	sudo cp images/debian-11-amd64-CD-1.iso $${target_device} && echo "Done!"
