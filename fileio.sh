#!/usr/bin/env bash

# Author:       Giovanni Giglio
# Email:        giovannimaria.giglio@gmail.com
# Description:  file.io utility for uploading and downloading files
# Usage:        fileio -u [args] | -d [args] | -h

function print_help {
    cat << EOF

Usage: fileio -u [args] | -d [args] | -h
file.io utility for uploading and downloading files.

    -u, --upload     uploads \$1 to https://file.io/
    -d, --download   downloads \$1 and saves it into \$2, or into stdout if not provided
    -e, --expires    set expiration period to \$1 (use only with -u)
    -h, --help       prints this help and exit

Expiration period argument accepts this type of pattern: n[d(ays),w(eeks),m(onths),y(ears)]
where 'n' has to be an integer greater than 0, followed by one letter in [dwmy].
If the expiration period is not provided it will be the default value of 14 days set by https://file.io/.

Please report any bug to https://github.com/GioGiglio/fileio-client/issues/
EOF
}


function error_exit {
    >&2 echo "${progname}: ${1:-"Unknown error"}" 1>&2
	exit 1
}

function error_usage {
    >&2 echo "${1:- }"
    >&2 echo "${progname}: usage: $progname -u [args] | -d [args] | -h"
    >&2 echo "$progname --help for further info"
    exit 1
}


# Perform checks to arguments provided by user
# 
# Globals:   arg_upload, arg_download, arg_expires, file, output, expiration
# Arguments: None
# Returns:   None

function checks {
    # parse args #
    while [[ $# -gt 0 ]]; do
		case $1 in
		-u | --upload )
			arg_upload=1
            file=$2
			shift
            shift
			;;
        -d | --download )
            arg_download=1
            file=$2
            output=${3:-/dev/stdout}
            shift
            shift
            shift
            ;;
        -e | --expires )
            arg_expires=1
            expiration=$2
            shift
            shift
            ;;
        -h | --help )
            print_help
            exit 0
            ;;
        *)
			error_usage "Invalid option $1"
		esac
	done

    # check args validity #
    if ! [ -z ${arg_upload:+$arg_download} ]; then
        # both -u and -d are set
        error_usage "cannot upload and download"
    fi

    if [ -z ${arg_upload:-$arg_download} ]; then
        # both -u and -d are not set
        error_usage
    fi

    # check $file validity #
    # check if $file exists, if $arg_upload is set #
    if [ -z "$file" ] || ( ! [ -z ${arg_upload+x} ]  && ! [ -e "$file" ] ); then
        error_usage "file $file is not valid"
    fi

    # check $file size, if $arg_upload is set #
    if ! [ -z ${arg_upload+x} ] && [ "$(wc -c < "$file" )" -gt "$max_file_size" ]; then
        error_exit "$file does not respect the 5GB limit"
    fi

    # check expiration period #
    if ! [ -z ${arg_expires+x} ]; then
        if [ -z "$expiration" ]; then
            error_exit "please provide an expiration period"
        elif ! [[ "$expiration" =~ ^[1-9][0-9]*[dwmy]$ ]]; then
            error_exit "expiration period not valid"
        fi
    fi

    # check $output file variable, if $arg_download is set #
    if ! [ -z ${arg_download+x} ] && [ -z "$output" ]; then
        error_usage 'provide an output file'
    fi
}


# Parses curl's output for file's upload, and prints info to stdout.
# If xclip is installed, copies the download link to system clipboard
#
# Global:    None
# Arguments: curl_output
# Returns:   None

function parse_response {
    IFS=',' read -a tokens <<< $(echo "$1" | tr -d '"{}')

    # if success:false #
    if [ "${tokens[0]}" == 'success:false' ]; then
        >&2 echo '-- error from https://file.io'
        >&2 echo "${tokens[@]:1}"
        exit 1
    fi

    # print all tokens except first
    for token in "${tokens[@]:1}"; do
        tput 'bold'
        printf '[ %6s ] => ' "$(cut -d ':' -f 1 <<< "$token")"
        tput 'sgr0'
        cut -d ':' -f 2- <<< "$token"
    done

    # if xclip is installed, copy link to clipboard
    if command -v xclip &> /dev/null; then
        grep -E -o 'https://file.io/\w+' <<< "${tokens[@]}" | xclip -selection clipboard
        echo '-- link copied to clipboard'
    fi
}


# Upload file to file.io using curl
#
# Global:    arg_expires, url, expiration, file
# Arguments: None
# Returns:   None

function upload {
    # if expires is set #
    if ! [ -z ${arg_expires+x} ]; then
        # add expiration token to url
        url="${url}/?expires=${expiration}"
    fi

    >&2 echo "-- uploading $file to https://file.io/"
    response=$(curl -F "file=@${file}" "$url" 2> /dev/null)

    if [ $? -gt 0 ]; then
        # error while uploading
        error_exit "error while uploading $file"
    else
        parse_response "$response"
    fi
}


# Download a file from file.io using curl
#
# Global:    url, file
# Arguments: None
# Returns:   None

function download {
    # $file refers to the file to be downloaded #

    # add base url to $file, if it is not already contained #
    if ! [[ "$file" =~ ^http ]]; then
        file="${url}/$file"
    fi
    
    >&2 echo "-- downloading $file"
    curl -f -o "$output" "$file" 2> /dev/null

    if [ $? -gt 0 ]; then
        # error
        error_exit "error while downloading $file"
    else
        >&2 echo "-- $file downloaded"
    fi
}

function main {
    progname=$(basename "$0")
    max_file_size=5000000000 # 5GB
    url='https://file.io'

    checks "$@"

    if ! [ -z ${arg_upload+x} ]; then
        upload
    elif ! [ -z ${arg_download+x} ]; then
        download
    fi
}

main "$@"
