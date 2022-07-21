#!/usr/bin/env bash

# base paths
base_tsconfig="./tsconfig.json"
out_dir="./ts-trace"

# override paths
while getopts "i:o:" option; do
   case $option in
      i) # override $base_tsconfig
         base_tsconfig=${OPTARG};;
        o) # overrid $out_dir
         out_dir=${OPTARG};;
     \?) # Invalid option
         echo "Valid options are -extend and -out";;
   esac
done

# derived paths
trace_dir="${out_dir}/traces"
log_file="${out_dir}/log"
trace_tsconfig="${out_dir}/tsconfig.json"

# create directories
mkdir -p $out_dir
mkdir -p $trace_dir

# global mutable
init=true
logs=()
success=()

# program
function main {
    if $init; then show_help; fi
    read_logfile
    show_logs
    prompt_user
    process_request
    sleep 0.3
    echo -e "\n"
    init=false
}

function process_request {
    success=()
    if (is_help $input)
        then show_help; prompt_user; process_request;
    elif (is_wildcard $input)
        then replay_all;
    else
        if (is_index $input) then replay_by_index $input;
        else trace_single $input;
        fi
        write_logfile $input
    fi
}

function show_help {
    echo -e "- Enter a whitespace-separated list of paths to trace
- Replay a trace by entering its index (\".\" to replay all)
- Press <CTRL+C> to exit.
"
}

function prompt_user {
    if $init;
        then echo -n "input: "
        else echo -n "input (? for help): "
    fi
    read input
    echo ""
}

function is_help { [ $1 == "?" ]; }

function is_wildcard { [ $1 == "." ]; }

function is_index { [[ $1 == +([0-9]) ]]; }

function is_log_empty { (( ${#logs[@]} == 0 )); }

function replay_all {
    for file in "${logs[@]}"; do
        trace_single ${file};
        echo ""
    done
    echo -n -e "\nTask complete"
}

function replay_by_index {
    trace_single ${logs[$1-1]}
}

function trace {
    tsc --project $trace_tsconfig --generateTrace $trace_dir/$1
}

function trace_single {
    write_trace_tsconfig $@
    filename="$@"
    filename="${filename// /_}"
    echo -n "[ ] tracing $@..."
    if (trace $filename); then
        success+="$@"
        echo -e -n "\r\e[K[✓] trace written to $trace_dir/$filename"
    else
        echo -e "\n[✗] bad trace written to $trace_dir/$filename"
        error_handling $filename
    fi
}

function write_trace_tsconfig {
    str="{\n\t\"extends\": \"../$base_tsconfig\",\n"
    str+="\t\"include\": [\n"
    for file in "$@"; do
        str+="\t\t\"../$file/**/*.ts\",\n";
    done
    str="${str::-3}\n\t]\n}"
    echo -e $str > $trace_tsconfig
}

function error_handling {
    exit=false
    while [[ $exit = false ]]; do
        echo -n -e "\ndelete it (y/n)? "
        read answer
        if [ $answer = "y" ]; then
            rm -r $trace_dir/$1
            echo -n -e "\n$trace_dir/$1 deleted"
            exit=true
        elif [ $answer = "n" ]; then
            exit=true
        fi
    done
}

function read_logfile {
    if test -f $log_file; then
        readarray -t logs < $log_file;
    else
        logs=();
    fi
}

function show_logs {
    if (!(is_log_empty)); then
        echo "Previously traced paths are:"
        i=0
        for log_item in "${logs[@]}"; do
            let i+=1
            echo "$i) ${log_item}";
        done
        echo ""
    fi
}

function write_logfile {
    if [ ${#success[@]} -eq 0 ]; then
        return 0;
    fi

    read_logfile
    str=""

    for (( i=${#success[@]}-1; i>=0; i-- )); do
        str+="${success[i]}\n"
    done

    for l in "${logs[@]}"; do
        for s in "${success[@]}"; do
            if [[ "$l" != "$s" ]]
                then str+="${l}\n"
                break
            fi
        done
    done

    echo -e ${str::-2} > $log_file
}

while :; do main; done