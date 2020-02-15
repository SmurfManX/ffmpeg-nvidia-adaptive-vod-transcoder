#!/bin/bash

cd /home/lab/sportfiles
old=/home/lab/old_pwd.lst
new=/home/lab/new_pwd.lst

while true
do

> $old
> $new

#create VOD list from
for i in `ls`
    do
    find "$(pwd)"/$i | grep .mp4 >> $old
done

sleep 10
#Check if there are any new VOD
for i in `ls`
    do
    find "$(pwd)"/$i | grep .mp4 >> $new
done

# clear log file
> transcoder.log

# declare vod list
new_cnt=$(cat $new | wc -l)
old_cnt=$(cat $old | wc -l)
result=$(diff $old $new | awk '{print $2}')


echo "================================================================"
echo "old/new files count: $new_cnt/$old_cnt"
echo "================================================================"

for i in $result
do
    if [ "$new_cnt" -ne "$old_cnt" ]
         then
# detect resolution an itrate from source
            resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $i)
            bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $i)

# detect resolution widht and height
            widht=$(echo "$resolution" | awk -F "x" '{ print $1}')
            height=$(echo "$resolution" | awk -F "x" '{ print $2}')

# calculate adaptive resolution
            height1=$(($widht/3*2))
            height2=$(($widht/4*2))
            weght1=$(($height/3*2))
            weght2=$(($height/4*2))
# calculate adaptive bitrate
            originalbitrate=$(($bitrate/1024))
            hdbitrate=$(($bitrate/1024/2))
            sdbitrate=$(($bitrate/1024/3))
# Date
            NOW=$(date +"%H:%M:%S %d-%m-%Y")

# Find transcoded files
		    fhd_cnt=$(ls -la ./* | grep "1080.mp4" | wc -l)
            hd_cnt=$(ls -la ./* | grep "720.mp4" | wc -l)
            sd_cnt=$(ls -la ./* | grep "480.mp4" | wc -l)

# Output
echo "================================================================"
echo "Stat: = Total File: $new_cnt | transcoded fhd:$fhd_cnt hd:$hd_cnt sd:$sd_cnt"
echo  "---------------------------------------------------------------"
echo "Source info" 
echo "File: = $i"  
echo "Detected Resolution: $resolution"
echo "Detected Bitrate: "$originalbitrate"/Kbps"  
echo  "---------------------------------------------------------------"
echo "Stream 1"
echo "   Resolution: $resolution" 
echo "   Bitrate: "$originalbitrate"/Kbps"
echo "   Profile: high"
echo "   Preset: slow"
echo "Stream 2"
echo "   Resolution: "$height1"X"$weght1""
echo "   Bitrate: "$hdbitrate"/Kbps"  
echo "   Profile: main"
echo "   Preset: medium"  
echo "Stream 3"
echo "   Resolution: "$height2"X"$weght2""
echo "   Bitrate: "$sdbitrate"/Kbps"  
echo "   Profile: baseline"
echo "   Preset: fast"
echo "================================================================"

echo "================================================================"               >> transcoder.log
echo "Stat: = Total File: $new_cnt | transcoded fhd:$fhd_cnt hd:$hd_cnt sd:$sd_cnt"   >> transcoder.log
echo  "---------------------------------------------------------------"               >> transcoder.log
echo "Source info"                                                                    >> transcoder.log
echo "File: = $i"                                                                     >> transcoder.log
echo "Detected Resolution: $resolution"                                               >> transcoder.log
echo "Detected Bitrate: "$originalbitrate"/Kbps"                                       >> transcoder.log
echo  "---------------------------------------------------------------"               >> transcoder.log
echo "Stream 1"                                                                       >> transcoder.log
echo "   Resolution: $resolution"                                                     >> transcoder.log
echo "   Bitrate: "$originalbitrate"/Kbps"                                            >> transcoder.log
echo "   Profile: high"                                                               >> transcoder.log
echo "   Preset: slow"                                                                >> transcoder.log
echo "Stream 2"                                                                       >> transcoder.log
echo "   Resolution: "$height1"X"$weght1""                                            >> transcoder.log
echo "   Bitrate: "$hdbitrate"/Kbps"                                                  >> transcoder.log
echo "   Profile: main"                                                               >> transcoder.log
echo "   Preset: medium"                                                              >> transcoder.log
echo "Stream 3"                                                                       >> transcoder.log
echo "   Resolution: "$height2"X"$weght2""                                            >> transcoder.log
echo "   Bitrate: "$sdbitrate"/Kbps"                                                  >> transcoder.log
echo "   Profile: baseline"                                                           >> transcoder.log
echo "   Preset: fast"                                                                >> transcoder.log
echo "================================================================"               >> transcoder.log


# Transcoding 
                             ffmpeg -n -threads:v 2 -threads:a 8 -filter_threads 2 -thread_queue_size 512 -vsync 1 -hwaccel cuvid -c:v h264_cuvid -resize $resolution  -i $i \
                            -c:v h264_nvenc -b:v "$originalbitrate"K -g 48 -keyint_min 48 -preset slow -profile:v high -c:a aac -ar 44100 -ac 2 $i-1080p.mp4

                            ffmpeg -n -threads:v 2 -threads:a 8 -filter_threads 2 -thread_queue_size 512 -vsync 1 -hwaccel cuvid -c:v h264_cuvid -resize "$height1"x"$weght1" -i $i \
                            -c:v h264_nvenc -b:v "$hdbitrate"K -g 48 -keyint_min 48 -preset medium -profile:v main -c:a aac -ar 44100 -ac 2 $i-720p.mp4

                            ffmpeg -n -threads:v 2 -threads:a 8 -filter_threads 2 -thread_queue_size 512 -vsync 1 -hwaccel cuvid -c:v h264_cuvid -resize "$height2"x"$weght2" -i $i  \
                            -c:v h264_nvenc -b:v "$sdbitrate"K -g 48 -keyint_min 48 -preset fast -profile:v baseline -c:a aac -ar 44100 -ac 2 $i-480p.mp4

# raname files
                    for f in $i-1080p.mp4; do mv -v "$f" "${f/.mp4-1080p.mp4/_1080.mp4}"; done;
                    for f in $i-720p.mp4; do mv -v "$f" "${f/.mp4-720p.mp4/_720.mp4}"; done;
                    for f in $i-480p.mp4; do mv -v "$f" "${f/.mp4-480p.mp4/_480.mp4}"; done;

# remove transcoded file from list
                    sed -i '1d' new_pwd.lst
        else
                echo "file not found, sleep 10 sec"
fi
    	clear
	done
done
