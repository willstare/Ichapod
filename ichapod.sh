#!/bin/bash
# Ichapod by Patrick Simonds (divinitycycle@gmail.com)
# This script is inspired by BashPodder, but I wanted much fancier output options
# 
#
#This script has been updated in 2018. Notible changes include using wget to download the RSS to a 'current.rss' file before xsltproc processes the RSS. There seemed to be an issue with using xsltproc to grab the file.
#
#
##############
## SETTINGS ##
##############
# In the default setup, Ichapod is installed to /usr/share/ichapod
# It should be possible to put any of the files associated with it pretty much anywhere.
# This is where you want to finished podcast files to go
destinationfolder="" #Example destinationfolder="/mnt/plex/Podcasts"

# This is where you are storing the ichapod.sh script.
scriptfolder="" # Example scriptfolder="/home/plex/scripts/ichapod"
# This is the file containing your podcasts to be downloaded
podcastlist="" # Example podcastlist="/home/plexadmin/scripts/ichapod/podcasts.txt"

# This is the number of days old an item can be and still be downloaded.
# If you set the agelimit to 12 and Ichapod gets a story that's 2 weeks old, it will skip it.
agelimit="5";

# Download Log
# This file is maintained & used by Ichapod and isn't intended to be human readable.
# It prevents Ichapod from trying to download a file it has already downloaded.
downloadlog="" # Example downloadlog="/home/plexadmin/scripts/ichapod/downloadedpodcasts.log"

# Daily Log File
# If you are running Ichapod via cron and logging the output to a file, you can tell Ichapod where the file is
# to allow it to insert a custom log header into it.
dailylog="-`date +\%Y-\%m-\%d`.log"; # Example dailylog="/home/plexadmin/scripts/ichapod/ichapod-`date +\%Y-\%m-\%d`.log";

# Daily Log Header
# this is the text you want inserted at the top of your daily log file.
dailylogheader=$( echo -e "#################################################\n############# ICHAPOD ## `date +\%m-\%d-\%Y` #############\n#################################################\n \n" );

# This should be pointed at the xsl file in your Ichapod location.
# You usually do not need to mess with this, just give the location of the included file
processorfile="" # Example processorfile="/home/plexadmin/scripts/ichapod/readpodcast.xsl"

# This is a temporary log, used to collect output for debugging purposes.
# Its rebuilt every time Ichapod is run, useful if you're trying to see what happened during the last run.
# You can usually just leave the default.
debuglog=""; # Example debuglog="/home/plexadmin/scripts/ichapod/ichapod-lastrun.log";

# END SETTINGS ###################################

# Begin actual script #############################
# First we check that the daily log variables have been set, but the current log file is empty.
# If so, its the first run of the day, and we should output the header.
downloadDate=`date +\%Y-\%m-\%d`
echo "$downloadDate"

if [ ! -s "$dailylog" ] && [ "$dailylogheader" != "" ] && [ "$dailylog" != "" ]
then
	echo "$dailylogheader">>"$dailylog";
fi
echo "$(date +\%m-\%d-\%I:\%M\%p): Ichapod started.">"$debuglog";
# Wrap up the functional stuff using flock to prevent concurrent runs.
set -e

(
	flock -x -w 10 200
	# Next we make sure our destination actually exists
	mkdir -p $destinationfolder;
	# if download log doesn't exist, make one.
	if [ ! -e "$downloadlog" ];
	then
		echo "$(date +\%m-\%d-\%I:\%M\%p): Download Log missing, should be $downloadlog.">>"$debuglog";
		touch "$downloadlog";
	fi
	if [ -e "$downloadlog" ];
	then
		echo "$(date +\%m-\%d-\%I:\%M\%p): Download Log found at $downloadlog.">>"$debuglog";
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
			echo "$(date +\%m-\%d-\%I:\%M\%p): Now working on $label-$label2-$feedurl.">>"$debuglog";
			wget $feedurl -O $scriptfolder/current.rss			
			xsltproc $processorfile $scriptfolder/current.rss>/tmp/ichapodtmp.log;
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
				date=$(date -d "$date" +%Y-%m-%d); # put the date into the nice 2011-12-03 format
								
				episodetitle=${episode%---*}; # Next the title
				episodetitle=$(echo ${episodetitle//: /-}); # Replace ": " with "-" in the title.
				episodetitle=$(echo ${episodetitle//\?/}); # Remove question marks.
				episodetitle=$(echo ${episodetitle//\’/}); # Remove single quote marks.
				episodetitle=$(echo ${episodetitle// \/ /, }); # Replace " / " with ", ".
				episodetitle=$(echo ${episodetitle//\//,}); # Replace "/" with ",".
				episodetitle=$(echo ${episodetitle//\//}); # Remove any remaining "/"s.
				episode=${episode#*---};
				# the actual wget target
				downloadurl=${episode%---*};
				# Now that all the episode-specific variables SHOULD be filled, we can read them out to the debug log.
				echo "$(date +\%m-\%d-\%I:\%M\%p): Now working on $downloadurl.">>"$debuglog";
				echo "$(date +\%m-\%d-\%I:\%M\%p): Episode Title is $episodetitle.">>"$debuglog";
				echo "$(date +\%m-\%d-\%I:\%M\%p): Date is $date, Year is $year.">>"$debuglog";
				# Here's the date processing section. I decided that rather than wrap everything inside another logic fork, I'd just do the date comparison
				# and then fill a Boolean variable with the result. Instantiate that with "false" to avoid any logic problems.
				ageskip=false;
				# On the left side of "greater than" we have the current date in GNU seconds format, minus the episode date in the same format.
				# AKA "how old it is"
				# on the right we simply multiply the age limit by 86,400 (the number of seconds in a day) so that its the same format.
				if [ $(($( date +%s)-$ageseconds)) -gt $(($agelimit*86400)) ]
				then
					ageskip=true;
					echo "$(date +\%m-\%d-\%I:\%M\%p): Skipping $label-$date-$episodetitle.mp3, too old.">>"$debuglog";
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
						echo "$(date +\%m-\%d-\%I:\%M\%p): URL not found in log, but $finishedfilename but file exists anyway.">>"$debuglog";
					fi
					# only download if file doesn't already exist
					if [ ! -e "$finishedfilename" ]
					then
						echo "$(date +\%m-\%d-\%I:\%M\%p): Downloading $label-$date-$episodetitle.mp3.">>"$dailylog";
						wget -q -x -t 10 -O "$finishedfilename" "$downloadurl"; # Download the file.
					fi
					if [ -e "$finishedfilename" ] # If the downloaded file exists, then we can proceed to deal with it.
					then
						echo "$downloadurl" >> "$downloadlog"; # Log it, and tag it.
						echo "$(date +\%m-\%d-\%I:\%M\%p): Now running eyeD3.">>"$debuglog";
						label=$(echo ${label//\'/}); #remove single quote from label
						eyeD3 --to-v2.3 --set-text-frame=TPE2:"$label" --genre=Podcast --year=$year --title="$date-$episodetitle" --album="$album" --artist="$label" "$finishedfilename">>"$debuglog"  2>&1;
						echo " ">>"$debuglog"; # For readability
						if [ -e "$coverartlocation" ] # Check for cover art file, and if it exists, tag it into the file.
						then
							echo "$(date +\%m-\%d-\%I:\%M\%p): Now tagging the artwork in.">>"$debuglog";
							eyeD3 --remove-images "$finishedfilename">>"$debuglog";
							eyeD3 --to-v2.3 --add-image="$coverartlocation":FRONT_COVER "$finishedfilename">>"$debuglog";
							echo " ">>"$debuglog";
						fi
						# Check the mp3 to see if it has already been run through MP3gain and skip it if it has.
						if ! eyeD3 "$finishedfilename" | grep replaygain_reference_loudness>/dev/null;
						then
							echo "$(date +\%m-\%d-\%I:\%M\%p): Applying MP3gain to file.">>"$debuglog";
							mp3gain -T -e -r -s i -c -q "$finishedfilename">>"$debuglog" 2>&1; # Normalize the file
							echo " ">>"$debuglog";
						fi
						echo "$(date +\%m-\%d-\%I:\%M\%p): End post-processing.">>"$debuglog";
					fi # END Post-Processing Branch.
				fi # END Downloader Branch.
			done < "/tmp/ichapodtmp.log"
			echo "$(date +\%m-\%d-\%I:\%M\%p): Finished with this feed.">>"$debuglog";
			echo " ">>"$debuglog";
		done < "$podcastlist"
	echo "$(date +\%m-\%d-\%I:\%M\%p): Removing temporary log, processing complete.">>"$debuglog";
	rm -f /tmp/ichapodtmp.log;
) 200>/var/lock/.inchapod.exclusivelock
