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

# Download Log
downloadlog="/var/www/Ichapod/downloaded.log"

# This should be pointed at the xsl file in your Ichapod location.
# You usually do not need to mess with this, just give the location of the included file
processorfile="/var/www/Ichapod/readpodcast.xsl"
# END SETTINGS ###################################

# Begin actual script #############################
# Wrap the entire script in an If fork so that we allow only one instance of the script to run
if [ -e "/var/run/ichapod" ];
then
	echo "Runfile already exists, a previous instance of Ichapod is already running.";
fi
if [ ! -e "/var/run/ichapod" ];
	#since Ichapod is now "running", make the Runfile
	touch "/var/run/ichapod";
	# Next we make sure our destination actually exists
	mkdir -p $destinationfolder
	# if download log doesn't exist, make one.
	if [ ! -e "$downloadlog" ];
	then
		touch "$downloadlog";
	fi
	# Ensure no previous temp log file exists
	rm -f /tmp/ichapodtmp.log
	echo "$(date): Ichapod starting."
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
					echo "$(date): Now working on $label.";
				fi
				if [[ "${piece2:0:7}" != 'http://' ]];
				then
					label=${piece1%---*};
					feedurl=${piece2#*---};
					label2=${piece2%---*};
					echo "$(date): Now working on $label-$label2.";
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
				year=$(date -d "$date" +%Y);
				date=$(date -d "$date" +%m-%d-%H%M); # put the date into the nice 2011-12-03 format
				episodetitle=${episode%---*}; # Next the title
				episodetitle=$(echo ${episodetitle//: /-}); # Replace ": " with "-" in the title.
				episodetitle=$(echo ${episodetitle//\?/}); # Remove question marks.
				episode=${episode#*---};
				downloadurl=${episode%---*}; # the actual wget target
				if grep "$downloadurl" "$downloadlog" > /dev/null; # Look for the download in the log file
				then
					echo "$(date): Skipping $label-$date-$episodetitle.mp3, file exists.";
				fi
				if ! grep "$downloadurl" "$downloadlog" > /dev/null # Look for the download in the log file
				then
					if [ "$label2" == "" ];
					then  # This is the branch for having no special album label
						echo "$(date): Now downloading $label-$date-$episodetitle.mp3."
						mkdir -p "$destinationfolder/$label"; # Need to make sure the destination folder is there or wget won't work
						wget -q -x -t 10 -O "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 "$downloadurl"; # Download the file.
						if [ -e "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 ] # If the downloaded file exists, then we can proceed to deal with it.
						then
							echo "$downloadurl" >> "$downloadlog"; # Log it, and tag it.
							echo "$(date): Applying ID3 tags to file.";
							eyeD3 --to-v2.3 --set-text-frame=TPE2:"$label" --genre=Podcast --year=$year --title="$date-$episodetitle" --artist="$label" "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1;
							if [ -e "$destinationfolder"/"$label"/Folder.jpg ] # Check for cover art file, and if it exists, tag it into the file.
							then
								echo "$(date): Tagging Folder.jpg into file.";
								eyeD3 --to-v2.3 --add-image="$destinationfolder"/"$label"/Folder.jpg:"FRONT_COVER" "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1;
							fi
							echo "$(date): Applying MP3gain to file.";
							mp3gain -T -e -r -c "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1; # Normalize the file
						fi
					fi
					if [ "$label2" != "" ]; # this is the branch for having a seperate label for the album field.
					then
						echo "$(date): Now downloading $label-$label2-$date-$episodetitle.mp3.";
						mkdir -p "$destinationfolder/$label"-"$label2"; # Need to make sure the destination folder is there or wget won't work
						wget -q -x -t 10 -O "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 "$downloadurl"; # Download the file.
						if [ -e "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 ]; # If the downloaded file exists, then we can proceed to deal with it.
						then
							echo "$downloadurl" >> "$downloadlog"; # Log it, and tag it.
							echo "$(date): Applying ID3 tags to file.";
							eyeD3 --to-v2.3 --set-text-frame=TPE2:"$label" --genre=Podcast --year=$year --title="$date-$episodetitle" --artist="$label" --album="$label2" "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1;
							if [ -e "$destinationfolder"/"$label"-"$label2"/Folder.jpg ]; # Check for cover art file, and if it exists, tag it into the file.
							then
								echo "$(date): Tagging Folder.jpg into file.";
								eyeD3 --to-v2.3 --add-image="$destinationfolder"/"$label"-"$label2"/Folder.jpg:"FRONT_COVER" "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1;
							fi
							echo "$(date): Applying MP3gain to file.";
							mp3gain -T -e -r -c "$destinationfolder"/"$label"-"$label2"/"$label"-"$label2"-"$date"-"$episodetitle".mp3 > /dev/null 2>&1; # Normalize the file
						fi
					fi
				fi
			done < "/tmp/ichapodtmp.log"
		done < "$podcastlist"
	echo "$(date): Sorting download log.";
	sort "$downloadlog" | uniq > "$downloadlog";
	echo "$(date): Removing temporary log, processing complete.";
	rm -f /tmp/ichapodtmp.log;
	# Since we are done, take down the Runfile
	rm -f "/var/run/ichapod";
fi