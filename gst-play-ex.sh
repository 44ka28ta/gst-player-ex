#!/bin/bash

# multimedia player for youtube uri by using gstreamer
#
# default directory of caching : /tmp
#
# necessary components: gst-play-1.0 (gstreamer-plugin-vaapi), curl, tail, grep, sed, xargs
#
# TODO List
# * Buffering and Caching videos (Currently only caching).
#
# Reference
# * [Reverse-Engineering YouTube: Revisited • Oleksii Holub](https://tyrrrz.me/blog/reverse-engineering-youtube-revisited)

#set -eu
set -- `getopt v:a $*`

function opt_help {
    echo "Usage: $0 [-v volume] [-a] youtube_video_url" 1>&2
    echo "multimedia player for youtube uri by using gstreamer." 1>&2
    echo "" 1>&2
    echo "Options:" 1>&2
    echo "a: sound only mode." 1>&2
    echo "v: volume of the video sound." 1>&2
    exit 1
}

if [ $? != 0 ]; then
    opt_help
fi


GST_OPT=''

TMP_DIR='/tmp/'



for OPT in $*
do
	case $OPT in
		-v)
            GST_OPT=$GST_OPT"--volume="$2" "
		    shift
		    ;;
		-i)
            GST_OPT=${GST_OPT}"--videosink=fakesink "
		    shift
		    ;;
		--)
            shift
		    break
		    ;;
	esac
done

#echo $@

if [[ -z "$@" ]]; then
    opt_help
fi

_info_msg () {
	echo "[info] : $1"
}

_err_msg() {
	echo "[error] : $1" >&2
}

YOUTUBE_DOMAIN='www.youtube.com'

decode_uri () {
	echo $(echo $1 | sed 's/%20/ /g; s/%21/!/g; s/%22/"/g; s/%23/#/g; s/%24/$/g; s/%25/%/g; s/%26/\&/g; '"s/%27/'/g;"' s/%28/\(/g; s/%29/\)/g; s/%2A/\*/g; s/%2B/\+/g; s/%2C/,/g; s/%2F/\//g; s/%3A/:/g; s/%3B/;/g; s/%3C/</g; s/%3D/=/g; s/%3E/>/g; s/%3F/\?/g; s/%40/@/g; s/%5B/\[/g; s/%5C/\\/g; s/%5D/\]/g; s/%7C/|/g')
}

extract_base_js_uri () {
	BASE_JS_KEY="jsUrl"
	BASE_JS_SUB_URI=$(curl -L $1 | grep ${BASE_JS_KEY} | head -n 1 | sed -r 's/^.*"'${BASE_JS_KEY}'"\s*\:\s*"([^"]+)".*$/\1/')

	echo 'https://'${YOUTUBE_DOMAIN}${BASE_JS_SUB_URI}
}

extract_cipher_series() {
	local SIGNATURE_CIPHER=$2
	# extract randomizing series from base.js such as:
	#	...
	# 	Vsa=function(a){a=a.split("");nI.UF(a,53);nI.pS(a,1);nI.UF(a,28);nI.pS(a,3);nI.UF(a,37);nI.UF(a,21);return a.join("")};
	# 	...
	#
	#cat $1 | sed -r 's/.*function\(.+\)\s*\{(\s*.\s*=\s*.\.split\([\'"][\'"]\).+)\}.*/\1/'
	#sed -rn '{N; /.*function\(.\)\s*\{\s*.\s*\=\s*.\.split\(['\''"]{2}/{=;p} ; D}' $1
	# because of suppressing automatic output by -n option, explicitly should indicate p sub command. {}(curly brace) sub command [address]
	local SERIES=`sed -rn '/.*function\(.\)\s*\{\s*.\s*\=\s*.\.split\(['\''"]{2}\).+\}/{s/^.*\{\s*.\s*\=\s*.\.split\(['\''"]{2}\);(.+);return\s.\.join\(['\''"]{2}\).*\}.*$/\1/;p}' $1`

	# nI.UF(a,53) nI.pS(a,1) nI.UF(a,28) nI.pS(a,3) nI.UF(a,37) nI.UF(a,21)
	SERIES=($(echo ${SERIES} | tr -d ' ' | tr -s ';' ' '))
	# echo ${#SERIES[@]} # Length of Series

	#echo "Sig: ${SIGNATURE_CIPHER}, Ciphering Seq: ${SERIES[@]}$" >&2

	local RANDOBJ=$(echo ${SERIES[0]} | sed -r 's/^\s*([a-zA-Z0-9]+)\.[^\.]+$/\1/g')

	#var nI={QS:function(a){a.reverse()}, // Reverse all -> rev command
	#UF:function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}, // Swap head and specified numbered elements
	#pS:function(a,b){a.splice(0,b)}}; // Remove specified numbered elements from head

	local MAPPED_FUNCS_RAW=`sed -rn '/var\s+'${RANDOBJ}'\s*=\s*\{/ {:loop; N; /\}\s*\}\s*;/!b loop; s/^.*var\s+'${RANDOBJ}'\s*=\s*\{(.+\})\s*\}\s*;\s*.*$/\1/;p}' $1`

	local MAPPED_FUNCS=($(echo ${MAPPED_FUNCS_RAW} | tr -d ' ' | tr -d ',' | sed -r 's/\}/\}\n/g'))


	declare -A FUNC_MAPS

	for func in "${MAPPED_FUNCS[@]}"; do

		case "${func##*:}" in
			*"splice"*)
				FUNC_MAPS["${func%%:*}"]='echo ${1} | cut -b `expr ${2} + 1`-'
				;;
			*"reverse"*)
				FUNC_MAPS["${func%%:*}"]='echo ${1} | rev'
				;;
			*"length"*) # $1 is original string, $2 is swap index from 0.
				FUNC_MAPS["${func%%:*}"]='[[ `expr ${2} % ${#1}` -eq 0 ]] && echo "${1}" || echo "${1:$((${2} % ${#1})):1}${1:1:`expr $((${2} % ${#1})) - 1`}${1:0:1}${1:`expr $((${2} % ${#1})) + 1`}"'
				;;
			*)
				echo "INVALID MAP" >&2
				;;
		esac
	done

	for e in "${SERIES[@]}"; do

		local OP_AND_VAL="$(echo ${e} | sed -r "s/${RANDOBJ}\.//g; s/\([^,]+,([0-9]+)\)/ \1/g")"

		set -- $(echo ${OP_AND_VAL} | tr -s ' ' '\n')

		local EVALSTR="${FUNC_MAPS["$1"]}"

		set -- $(echo "${SIGNATURE_CIPHER} $2" | tr -s ' ' '\n')

		SIGNATURE_CIPHER=$(echo `eval ${EVALSTR}`)
	done

	echo ${SIGNATURE_CIPHER}
}

get_signature_timestamp() {
	local SIGTSTAMP="signatureTimestamp"
	local TIMESTAMP=`sed -rn "/.*${SIGTSTAMP}\\s*:\\s*[0-9]+,.*/{s/^.*${SIGTSTAMP}\\s*:\\s*([0-9]+),.*$/\\1/;p}" $1`

	echo ${TIMESTAMP}
}

extract_url_from_streaming_block () {

	CIPHER_KEY='signatureCipher'

	STREAMING_QUERY=`echo $1 | jq -r "$2.${CIPHER_KEY}"`

	#echo "${STREAMING_QUERY}" >&2

	declare -A STREAMING_KEYS

	if [ "${STREAMING_QUERY}" != "null" ]; then

		for p in ${STREAMING_QUERY//&/$'\n'}
		do
			kvp=( ${p/=/ } )
			STREAMING_KEYS[${kvp[0]}]=${kvp[1]}
		done

		DECIPHERED_SIGNATURE=`extract_cipher_series "base.js" $(decode_uri ${STREAMING_KEYS['s']})`
		BASE_URI=${STREAMING_KEYS['url']}"&${STREAMING_KEYS['sp']}=${DECIPHERED_SIGNATURE}"
	else
		DECIPHERED_KEY='url'
		BASE_URI=`echo $1 | jq -r "$2.${DECIPHERED_KEY}"`
	fi

	COMPLETE_URI=$(decode_uri ${BASE_URI})

	echo ${COMPLETE_URI}
}


VIDEO_ID=`curl -I -L "$@" | grep 'Location' | tail -n 1 | { read location_str; [ "${location_str}" ] && echo ${location_str} || echo "$@"; } | sed -e 's/^.\+?v=\([_0-9a-zA-Z]\+\).*$/\1/g'`

VIDEO_MD5S=(`echo ${VIDEO_ID} | md5sum`)

if [ ! -e ${TMP_DIR}${VIDEO_MD5S[0]} ]; then


	CLIENT_NAME="TVHTML5_SIMPLY_EMBEDDED_PLAYER"
	CLIENT_VERSION="2.0"


	EMBED_URL="https://${YOUTUBE_DOMAIN}"

	YOUTUBEI_V1_URI="https://www.youtube.com/youtubei/v1/player?key=AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w"
	#YOUTUBEI_V1_URI="https://youtubei.googleapis.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"



	_info_msg "Extract JS Path."

	curl -O `extract_base_js_uri "${EMBED_URL}/watch?v=${VIDEO_ID}"` 

	RESPONSE=$(curl -X POST -H "Content-Type: application/json" -d "{"videoId":\""${VIDEO_ID}"\","context":{"client":{"clientName":\""${CLIENT_NAME}"\","clientVersion":\""${CLIENT_VERSION}"\"},"thirdParty":{"embedUrl":\""${EMBED_URL}"\"}}, "playbackContext":{"contentPlaybackContext":{"signatureTimestamp": $(get_signature_timestamp "base.js")}}}" ${YOUTUBEI_V1_URI})

	#echo "${RESPONSE}"

	STREAMING_URI_QUERY='.streamingData.formats[0]'

	VIDEO_URI=$(extract_url_from_streaming_block "${RESPONSE}" "${STREAMING_URI_QUERY}")

	_info_msg "${VIDEO_URI}"

	SIZE_HEADER="Content-Length"

	CONTENT_SIZE=$(curl -I "${VIDEO_URI}" | grep -i "${SIZE_HEADER}" | sed -r 's/'"${SIZE_HEADER}"':\s+([0-9]+)/\1/' | tr -d "[:space:]　")


	CHUNK_SIZE=10000000 # 10 MBytes


	# Maximum value in SInt64 is 9223372036854775807 (2**63 - 1)
	for ((i = 0; i < CONTENT_SIZE; i += CHUNK_SIZE)); do

		_info_msg "Separatedly Downloading: Phase "$((i / ${CHUNK_SIZE}))
		curl -r $i-$((i + ${CHUNK_SIZE} - 1)) ${VIDEO_URI} >> ${TMP_DIR}${VIDEO_MD5S[0]}
	done

fi

gst-play-1.0 ${GST_OPT} ${TMP_DIR}${VIDEO_MD5S[0]}
