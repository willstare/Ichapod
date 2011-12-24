#!/bin/bash
# Ichapod by Patrick Simonds (divinitycycle@gmail.com)
# This script is inspired by BashPodder, but I wanted much fancier output options

##############
## SETTINGS ##
##############

# In the default setup, Ichapod is installed to /usr/share/ichapod
# It should be possible to put any of the files associated with it pretty much anywhere.
# This is where you want to finished podcast files to go
destinationfolder="/usr/share/ichapod/downloads"

# This is the file containing your podcasts to be downloaded
podcastlist="/usr/share/ichapod/podcasts.txt"

# This is the number of days old an item can be and still be downloaded.
# If you set the agelimit to 12 and Ichapod gets a story that's 2 weeks old, it will skip it.
agelimit="3";

# Download Log
# This file is maintained & used by Ichapod and isn't intended to be human readable.
# It prevents Ichapod from trying to download a file it has already downloaded.
downloadlog="/usr/share/ichapod/downloadedpodcasts.log"

# Daily Log File
# If you are running Ichapod via cron and logging the output to a file, you can tell Ichapod where the file is
# to allow it to insert a custom log header into it.
dailylog="/usr/share/ichapod/ichapod-runlog-`date +\%Y-\%m-\%d`.log";

# Daily Log Header
# this is the text you want inserted at the top of your daily log file.
dailylogheader=$( echo -e "#################################################\n############# ICHAPOD ## `date +\%m-\%d-\%Y` #############\n#################################################\n \n" );

# This should be pointed at the xsl file in your Ichapod location.
# You usually do not need to mess with this, just give the location of the included file
processorfile="/usr/share/ichapod/readpodcast.xsl"

# This is a temporary log, used to collect output for debugging purposes.
# Its rebuilt every time Ichapod is run, useful if you're trying to see what happened during the last run.
# You can usually just leave the default.
debuglog="/tmp/ichapod-lastrun.log";

# END SETTINGS ###################################

# Begin actual script #############################
# First we check that the daily log variables havbe been set, but the current log file is empty.
# If so, its the first run of the day, and we should output the header.
if [ ! -s "$dailylog" ] && [ "$dailylogheader" != "" ] && [ "$dailylog" != "" ]
then
	echo "$dailylogheader";
fi
echo "$(date +\%m-\%d-\%H:\%M): Ichapod started.">"$debuglog";
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
		echo "$(date +\%m-\%d-\%H:\%M): Download Log missing, should be $downloadlog.">>"$debuglog";
		touch "$downloadlog";
	fi
	if [ -e "$downloadlog" ];
	then
		# this line is useful for troubleshooting, but is also "good" at filling your logs with extra garbage.
		echo "$(date +\%m-\%d-\%H:\%M): Download Log found at $downloadlog.">>"$debuglog";
	fi
	# Ensure no previous temp log file exists
	rm -f /tmp/ichapodtmp.log;
	# Now we read through the podcast list and handle each one
	while read podcast
		do
			# Avoiding some logic issues by freshly instantiated variables at the start of each podcast
			label="";
			label2="";
			ageskip="";
			ageseconds="";
			# check to see if a custom label has been entered for this feed
			if [[ "$podcast" = *---* ]]; 
			then
				piece1=${podcast%---*}; # Break the podcast text into two chunks to check for labels
				piece2=${podcast#*---};
				# Do some tricky string processing to figure out where the download URL is
				if [[ "${piece2:0:7}" == 'http://' ]];
				then
					label="$piece1";
					feedurl="$piece2";
				fi
				if [[ "${piece2:0:7}" != 'http://' ]];
				then
					label=${piece1%---*};
					feedurl=${piece2#*---};
					label2=${piece2%---*};
				fi
			else
				feedurl=$podcast;
			fi #now we pull & process the feed items from the current podcast feed we are processing.
			echo "$(date +\%m-\%d-\%H:\%M): Now working on $label-$label2-$feedurl.">>"$debuglog";
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
				# the actual wget target
				downloadurl=${episode%---*};
				# Now that all the episode-specific variables SHOULD be filled, we can read them out to the debug log.
				echo "$(date +\%m-\%d-\%H:\%M): Now working on $downloadurl.">>"$debuglog";
				echo "$(date +\%m-\%d-\%H:\%M): Episode Title is $episodetitle.">>"$debuglog";
				echo "$(date +\%m-\%d-\%H:\%M): Date is $date, Year is $year.">>"$debuglog";
				# Here's the date processing section. I decided that rather than wrap everything inside another logic fork, I'd just do the date comparison
				# and then fill a Boolean variable with the result. Instantiate that with "false" to avoid any logic problems.
				ageskip=false;
				# On the left side of "greater than" we have the current date in GNU seconds format, minus the episode date in the same format.
				# AKA "how old it is"
				# on the right we simply multiply the age limit by 86,400 (the number of seconds in a day) so that its the same format.
				if [ $(($( date +%s)-$ageseconds)) -gt $(($agelimit*86400)) ]
				then
					ageskip=true;
					echo "$(date +\%m-\%d-\%H:\%M): Skipping $label-$date-$episodetitle.mp3, too old.">>"$debuglog";
				fi
				# If the file isn't already in the log and isn't too old, then lets go!
				if ! grep "$downloadurl" "$downloadlog">/dev/null && ! $ageskip
				then
					if [ "$label2" == "" ];
					then  # There are some variables that are different if you have only one "label" to work with.
						mkdir -p "$destinationfolder/$label"; # Need to make sure the destination folder is there or wget won't work
						album="$label";
						finishedfilename=$(echo "$destinationfolder"/"$label"/"$label"-"$date"-"$episodetitle".mp3);
						coverartlocation=$destinationfolder/$label/Folder.jpg;
					fi
					if [ "$label2" != "" ]; # Here's the other version, for if you have 2 labels.
					then  
						mkdir -p "$destinationfolder/$label"; # Need to make sure the destination folder is there or wget won't work
						mkdir -p "$destinationfolder/$label/$label-$label2";
						album="$label2";
						finishedfilename=$destinationfolder/$label/$label-$label2/$label-$label2-$date-$episodetitle.mp3;
						coverartlocation=$destinationfolder/$label/$label-$label2/Folder.jpg;
					fi
					# If file DOES exist already, that seems weird.
					if [ -e "$finishedfilename" ]
					then
						echo "$(date +\%m-\%d-\%H:\%M): URL not found in log, but $finishedfilename but file exists anyway.">>"$debuglog";
					fi
					# only download if file doesn't already exist
					if [ ! -e "$finishedfilename" ]
					then
						echo "$(date +\%m-\%d-\%H\%M): Downloading $label-$date-$episodetitle.mp3."
						wget -q -x -t 10 -O "$finishedfilename" "$downloadurl"; # Download the file.
					fi
					if [ -e "$finishedfilename" ] # If the downloaded file exists, then we can proceed to deal with it.
					then
						echo "$downloadurl" >> "$downloadlog"; # Log it, and tag it.
						echo "$(date +\%m-\%d-\%H:\%M): Now running eyeD3.">>"$debuglog";
						eyeD3 --to-v2.3 --set-text-frame=TPE2:"$label" --genre=Podcast --year=$year --title="$episodetitle" --album="$album" --artist="$label" "$finishedfilename">>"$debuglog" 2>&1;
						echo " ">>"$debuglog";
						if [ -e "$coverartlocation" ] # Check for cover art file, and if it exists, tag it into the file.
						then
							echo "$(date +\%m-\%d-\%H:\%M): Now tagging the artwork in.">>"$debuglog";
							eyeD3 --remove-images "$finishedfilename">>"$debuglog";
							eyeD3 --to-v2.3 --add-image="$coverartlocation":FRONT_COVER "$finishedfilename">>"$debuglog";
							echo " ">>"$debuglog";
						fi
						# Check the mp3 to see if it has already been run through MP3gain and skip it if it has.
						if ! eyeD3 "$finishedfilename" | grep replaygain_reference_loudness>/dev/null;
						then
							echo "$(date +\%m-\%d-\%H:\%M): Applying MP3gain to file.">>"$debuglog";
							mp3gain -T -e -r -s i -c -q "$finishedfilename">>"$debuglog" 2>&1; # Normalize the file
							echo " ">>"$debuglog";
						fi
						echo "$(date +\%m-\%d-\%H:\%M): End post-processing.">>"$debuglog";
					fi # END Post-Processing Branch.
				fi # END Downloader Branch.
			done < "/tmp/ichapodtmp.log"
			echo "$(date +\%m-\%d-\%H:\%M): Finished with this feed.">>"$debuglog";
			echo " ">>"$debuglog";
		done < "$podcastlist"
	echo "$(date +\%m-\%d-\%H:\%M): Removing temporary log, processing complete.">>"$debuglog";
	rm -f /tmp/ichapodtmp.log;
	# Since we are done, take down the Runfile
	rm -f "/var/run/ichapod";
	if [ ! -e "/var/run/ichapod" ];
	then
		echo "$(date +\%m-\%d-\%H:\%M): Runfile removed successfully.">>"$debuglog";
	fi
fi