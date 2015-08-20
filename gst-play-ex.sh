#!/bin/bash

# multimedia player for youtube uri by using gstreamer
#
# default video quality: small
# default directory of caching : /tmp
# default maximum value of itag : 300
#
# necessary components: gst-play-1.0, curl, tail, grep, sed, xargs
#
# TODO List
# * Buffering and Caching videos (Currently only caching).

#set -eu
set -- `getopt v:q:ia $*`

function opt_help {
	echo "Usage: $0 [-v volume] [-i] [-a] [-q small|medium|hd720] youtube_video_url" 1>&2
    echo "multimedia player for youtube uri by using gstreamer." 1>&2
    echo "" 1>&2
    echo "Options:" 1>&2
    echo "i: interactive mode." 1>&2
    echo "a: sound only mode." 1>&2
    echo "q: video quality. (default: small)" 1>&2
    echo "v: volume of the video sound." 1>&2
	exit 1
}

if [ $? != 0 ]; then
    opt_help
fi


GST_OPT=''

TMP_DIR='/tmp/'

QUALITY='small'

ITAG_MAX='300'


for OPT in $*
do
	case $OPT in
		-v)
            GST_OPT=$GST_OPT"--volume="$2" "
		    shift
		    ;;
        -q)
            QUALITY=$2
            shift
            ;;
		-i)
            GST_OPT=${GST_OPT}"--interactive "
		    shift
		    ;;
		-a)
            GST_OPT=${GST_OPT}"--videosink=fakesink "
		    shift
		    ;;
		--)
            shift
		    break
		    ;;
	esac
done

echo $@

if [[ -z "$@" ]]; then
    opt_help
fi

id=`curl -I -L "$@" | grep 'Location' | tail -n 1 | { read location_str; [ "${location_str}" ] && echo ${location_str} || echo "$@"; } | sed -e 's/^.\+?v=\([_0-9a-zA-Z]\+\).*$/\1/g'`
video_md5s=(`echo ${id} | md5sum`)

[ ! -e ${TMP_DIR}${video_md5s[0]} ] && echo https://www.youtube.com/get_video_info?video_id=${id} | xargs curl | sed 's/&/\n/g' | grep url_encoded_fmt_stream_map | sed 's/%26/\n/g' | sed 's/%25/%/g' | nkf -w --url-input | grep -B 4 'quality='$QUALITY | { ti=${ITAG_MAX}; urlstr=''; while read line; do tj=`echo ${line} | sed -e 's/^.*\&itag=\([1-9][0-9]*\).*$/\1/g'`; { [[ ${tj} =~ ^[1-9][0-9]*$ && ${tj} -lt ${ti} ]] && { ti=${tj}; urlstr=${line}; } } done; echo ${urlstr}; } | sed 's/^.*url=//g' | xargs wget --quiet -O ${TMP_DIR}${video_md5s[0]}

gst-play-1.0 ${GST_OPT} ${TMP_DIR}${video_md5s[0]}
