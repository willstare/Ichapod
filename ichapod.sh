#!/bin/bash
# Ichapod by Patrick Simonds (divinitycycle@gmail.com)
# This script is inspired by BashPodder, but I wanted much fancier output options

##############
## SETTINGS ##
##############
# This is where you want to finished podcast files to go
destinationfolder="/mnt/disk3/Music/Incoming/Podcasts"

# This is the file containing your podcasts to be downloaded
podcastlist="/var/www/Ichapod/podcasts.txt"

# This is the number of days old an item can be and still be downloaded.
# If you set the agelimit to 12 and Ichapod gets a store that's 2 weeks old, it will skip it.
agelimit="7";

# Download Log
# This file is maintained & used by Ichapod and isn't intended to be human readable.
# It prevents Ichapod from trying to download a file it has already downloaded.
downloadlog="/var/www/logs/downloadedpodcasts.log"

# Daily Log File
# If you are running Ichapod via cron and logging the output to a file, you can tell Ichapod where the file is
# to allow it to insert a custom log header into it.
dailylog="/var/www/logs/ichapod-runlog-`date +\%Y-\%m-\%d`.log";

# Daily Log Header
# this is the text you want inserted at the top of your daily log file.
dailylogheader=$( echo -e "#################################################\n############# ICHAPOD ## `date +\%m-\%d-\%Y` #############\n#################################################\n \n" );

# This should be pointed at the xsl file in your Ichapod location.
# You usually do not need to mess with this, just give the location of the included file
processorfile="/var/www/Ichapod/readpodcast.xsl"

# END SETTINGS ###################################

# Begin actual script #############################
if [ ! -s "$dailylog" ] && [ "$dailylogheader" != "" ] && [ "$dailylog" != "" ]
then
	echo "$dailylogheader";
fi
# Wrap the entire script in an If fork so that we allow only one instance of the script to run
if [ -e "/var/run/ichapod" ];
then
	echo "$(date +\%m-\%d-\%H\%M): Runfile already exists, a previous instance of Ichapod is already running.";
fi
if [ ! -e "/var/run/ichapod" ];
then
	#since Ichapod is now "running", make the Runfile
	touch "/var/run/ichapod";
	# Next we make sure our destination actually exists
	mkdir -p $destinationfolder;
	# if download log doesn't exist, make one.
	if [ ! -e "$downloadlog" ];
	then
		echo "$(date +\%m-\%d-\%H\%M): Download Log missing, settings say it should be $downloadlog.";
		touch "$downloadlog";
	fi
	if [ -e "$downloadlog" ];
	then
		# this line is useful for troubleshooting, but is also "good" at filling your logs with extra garbage.
		echo "$(date +\%m-\%d-\%H\%M): Download Log found at $downloadlog.">/dev/null;
	fi
	# Ensure no previous temp log file exists
	rm -f /tmp/ichapodtmp.log;
	# echo "$(date +\%m-\%d-\%H\%M): Ready to begin.";
	# Now we read through the podcast list and handle each one
	while read podcast
		do
			label="";
			label2="";
			# check to see if a custom label has been entered for this feed
			if [[ "$podcast" = *---* ]]; 
			then
				# Bash's wonky string processing guide
				# ${variable%---*} = everything to the LEFT of the LAST instance of '---'
				# ${variable#---*} = nothing
				# ${variable#*---} = everything to the RIGHT of the FIRST instance of '---'
				# ${variable%*---} = nothing
				piece1=${podcast%---*}; # Break the podcast text into two chunks to check for labels
				piece2=${podcast#*---};
				if [[ "${piece2:0:7}" == 'http://' ]];
				then
					label="$piece1";
					feedurl="$piece2";
					# I have commented out this output, since I am using an hourly log style and this was making the output unnecessarily long.
					# It may be helpful to uncomment this if you're debugging your setup.
					# echo "$(date +\%m-\%d-\%H\%M): Now working on $label.";
				fi
				if [[ "${piece2:0:7}" != 'http://' ]];
				then
					label=${piece1%---*};
					feedurl=${piece2#*---};
					label2=${piece2%---*};
					# echo "$(date +\%m-\%d-\%H\%M): Now working on $label-$label2.";
				fi
			else
				feedurl=$podcast;
			fi #now we pull & process the feed items from the current podcast feed we are processing.
			xsltproc $processorfile $feedurl>/tmp/ichapodtmp.log;
			while read episode
			do
				# This is the loop that processes each episode within a podcast.
				if [ "$label" != "" ];
				then
					episode=${episode#*---}; # we don't need the label from the feed so chop off the first chunk
				fi
				if [ "$label" == "" ];
				then
					label=${episode%---*}; # Since we didn't get a label from the podcast list, we just use the one from the feed
					label=${label%---*};
					label=${label%---*};
					episode=${episode#*---};
				fi
				date=${episode%---*}; # Next pull in the date for the episode
				date=${date%---*};
				episode=${episode#*---};
				ageseconds=$(date -d "$date" +%s);
				year=$(date -d "$date" +%Y);
				date=$(date -d "$date" +%Y-%m-%d-%H%M); # put the date into the nice 2011-12-03 format
				episodetitle=${episode%---*}; # Next the title
				episodetitle=$(echo ${episodetitle//: /-}); # Replace ": " with "-" in the title.
				episodetitle=$(echo ${episodetitle//\?/}); # Remove question marks.
				episodetitle=$(echo ${episodetitle// \/ /, }); # Replace " / " with ", ".
				episode=${episode#*---};
				downloadurl=${episode%---*};
				# the actual wget target
				# Here's the date processing section. I decided that rather than wrap everything inside another logic fork, I'd just do the date comparison
				# and then fill a Boolean variable with the result. Instantiate that with "false" to avoid any logic problems.
				ageskip="false";
				# On the left side of "greater than" we have the current date in GNU seconds format, minus the episode date in the same format.
				# AKA "how old it is"
				# on the right we simply multiply the age limit by 86,400 (the number of seconds in a day) so that its the same format.
				if [ $(($( date +%s)-$ageseconds)) -gt $(($agelimit*86400)) ]
				then
					ageskip="true";
					# echo "$(date +\%m-\%d-\%H\%M): Skipping $label-$date-$episodetitle.mp3, too old.";
				else
					ageskip="false";
				fi
				if ! grep "$downloadurl" "$downloadlog">/dev/null && "$ageskip" != "true";
				then
					if [ "$label2" == "" ];
					then  # This is the branch for having no special album label
						mkdir -p "$destinationfolder/$label"; # Need to make sure the destination folder is there or wget won't work
						# only download if file doesn't already exist
						if [ -e "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 ]
						then
							echo "$(date +\%m-\%d-\%H\%M):URL not found in log: $downloadurl."
						fi
						if [ ! -e "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 ]
						then
							echo "$(date +\%m-\%d-\%H\%M): Now downloading $label-$date-$episodetitle.mp3."
							wget -q -x -t 10 -O "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 "$downloadurl"; # Download the file.
						fi
						if [ -e "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 ] # If the downloaded file exists, then we can proceed to deal with it.
						then
							echo "$downloadurl" >> "$downloadlog"; # Log it, and tag it.
							# echo "$(date +\%m-\%d-\%H\%M): Applying ID3 tags to file.";
							eyeD3 --to-v2.3 --set-text-frame=TPE2:"$label" --genre=Podcast --year=$year --title="$date-$episodetitle" --artist="$label" "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1;
							if [ -e "$destinationfolder"/"$label"/Folder.jpg ] # Check for cover art file, and if it exists, tag it into the file.
							then
								# echo "$(date +\%m-\%d-\%H\%M): Tagging Folder.jpg into file.";
								eyeD3 --to-v2.3 --add-image="$destinationfolder"/"$label"/Folder.jpg:"FRONT_COVER" "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1;
							fi
							# echo "$(date +\%m-\%d-\%H\%M): Applying MP3gain to file.";
							mp3gain -T -e -r -c "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1; # Normalize the file
						fi
					fi
					if [ "$label2" != "" ]; # this is the branch for having a seperate label for the album field.
					then
						mkdir -p "$destinationfolder/$label"-"$label2"; # Need to make sure the destination folder is there or wget won't work
						if [ -e "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 ]
						then
							echo "$(date +\%m-\%d-\%H\%M): URL not found in log: $downloadurl.";
						fi
						if [ ! -e "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 ]
						then
							echo "$(date +\%m-\%d-\%H\%M): Now downloading $label-$label2-$date-$episodetitle.mp3.";
							wget -q -x -t 10 -O "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 "$downloadurl"; # Download the file.
						fi
						if [ -e "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 ]; # If the downloaded file exists, then we can proceed to deal with it.
						then
							echo "$downloadurl" >> "$downloadlog"; # Log it, and tag it.
							# echo "$(date +\%m-\%d-\%H\%M): Applying ID3 tags to file.";
							eyeD3 --to-v2.3 --set-text-frame=TPE2:"$label" --genre=Podcast --year=$year --title="$date-$episodetitle" --artist="$label" --album="$label2" "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1;
							if [ -e "$destinationfolder"/"$label"-"$label2"/Folder.jpg ]; # Check for cover art file, and if it exists, tag it into the file.
							then
								# echo "$(date +\%m-\%d-\%H\%M): Tagging Folder.jpg into file.";
								eyeD3 --to-v2.3 --add-image="$destinationfolder"/"$label"-"$label2"/Folder.jpg:"FRONT_COVER" "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1;
							fi
							# echo "$(date +\%m-\%d-\%H\%M): Applying MP3gain to file.";
							mp3gain -T -e -r -c "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1; # Normalize the file
						fi
					fi
				fi
			done < "/tmp/ichapodtmp.log"
		done < "$podcastlist"
	# echo "$(date +\%m-\%d-\%H\%M): Removing temporary log, processing complete.";
	rm -f /tmp/ichapodtmp.log;
	# Since we are done, take down the Runfile
	rm -f "/var/run/ichapod";
	if [ ! -e "/var/run/ichapod" ];
	then
		echo "$(date +\%m-\%d-\%H\%M): Runfile removed successfully">/dev/null;
	fi
fi