#!/bin/sh
# Android Nightly Podcast Rsync
# By Patrick Simonds (DivinityCycle@gmail.com)
#### SETTINGS ######
# The folder where the mp3s you want to sync are
sourcefiles="/path/to/Podcasts/";
# The folder on your phone's filesystem where the files should go
targetdir="/sdcard/Music/Podcasts/";
# Your phone's IP address
phoneaddress="192.168.1.50";
# The location for your OpenSSH key file
keyfile="/path/to/OpenSSHKey";

#### END SETTINGS ####
echo "$(date +\%m-\%d-\%I:\%M\%p): Begin Android Podcast Sync.";
# If the phone has been sitting a while, it will probably be asleep. Pinging will wake the networking.
ping -c 5 -w 5 "$phoneaddress" >/dev/null;
# Now that it has a shot at being "awake", test to see if phone is "alive"
ping -c 1 -w 5 "$phoneaddress" >/dev/null;
if [ $? -eq 0 ];
then
	echo "$(date +\%m-\%d-\%I:\%M\%p): Phone appears to be responding to ping.";
	if [ ! -f "$keyfile" ];
	then
		echo "$(date +\%m-\%d-\%I:\%M\%p): Keyfile missing. Should be found at $keyfile. Check your settings.";
	else
		sshup=$(ssh -q -o "BatchMode=yes" -o "ConnectTimeout 30" -i "$keyfile" "$phoneaddress" exit);
		if [ "$sshup" != '0' ];
		then
			echo "$(date +\%m-\%d-\%I:\%M\%p): SSH appears to be working.";
			# Find mp3 files modified in the last day and output them into a temp file so we can upload them to the phone
			find "$sourcefiles" -type f -name "*.mp3" -mtime 0 -print0 | xargs -n1 -0 echo>>/tmp/files;
			# Make a folder to hold the symblinks we'll create.
			mkdir /tmp/androidfiles
			# Now we can read that list and process it
			while read file
			do
				# I wanted to have just the file get uploaded without any parent folders
				# First step to that is to get "just" the file name
				justfile=$(basename "$file");
				# Now we build the path where the symlinked copy of the file will go
				justfile="/tmp/androidfiles/$justfile";
				# Now we actually build the symlink
				ln -s "$file" "$justfile";
			done < /tmp/files
			files=$( cat /tmp/files )
			if [ ! -z "$files" ];
			then
				# Now we need to get the networking going. To ensure the phone's WiFi isn't sleeping, we ping it.
				ping -c 5 -w 5 "$phoneaddress" >/dev/null;
				# Now that it has a shot at being "awake", test to see if phone is "alive"
				ping -c 1 -w 5 "$phoneaddress" >/dev/null ;
				# Next we run a find | rm command over ssh to sweep out the old files
				echo "$(date +\%m-\%d-\%I:\%M\%p): Removing old files from phone.";
				ssh -i "$keyfile" root@$phoneaddress find "$targetdir" -name "*.mp3" -type f -mtime +3 | xargs rm -f;
				echo "$(date +\%m-\%d-\%I:\%M\%p): Syncing new files to phone.";
				# Now we should be able to punt the new files over to the phone via rsync
				rsync -avzL -e "ssh -i $keyfile" /tmp/androidfiles/ root@192.168.1.50:/sdcard/Music/Podcasts/
				echo "$(date +\%m-\%d-\%I:\%M\%p): Sync completed.";
				# Set permissions on the uploaded files
				ssh -i "$keyfile" root@$phoneaddress chmod -R 777 "$targetdir";	
				# Transfer complete, its time to get rid of the tmp symlinks we made
				rm -R /tmp/androidfiles;
				# To get the music player to refresh and thus see the new mp3s, reboot the phone
				echo "$(date +\%m-\%d-\%I:\%M\%p): Rebooting phone.";
				ssh -f -i "$keyfile" root@$phoneaddress reboot
				# after issuing the reboot command, sleep for 15 seconds to give the phone enough time to have rebooted, but not enough time to be back online yet.
				sleep 15
				ping -c 1 -w 5 "$phoneaddress" >/dev/null ;
				if [ ! $? -eq 0 ];
				then
					echo "$(date +\%m-\%d-\%I:\%M\%p): Rebooting phone appears to have been successful."
				fi
			else
				echo "$(date +\%m-\%d-\%I:\%M\%p): No files to upload.";
			fi
			# Don't forget to delete files list
			rm /tmp/files;
		fi
	fi
else
	echo "$(date +\%m-\%d-\%I:\%M\%p): Phone not responding to ping.";
fi
