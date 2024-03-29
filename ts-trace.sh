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
            echo "Valid options are -i and -o";;
   esac
done

# derived paths
trace_dir="${out_dir}/traces"
snapshots_dir="${out_dir}/snapshots"
log_file="${out_dir}/log"
trace_tsconfig="${out_dir}/tsconfig.json"

# create directories
mkdir -p $out_dir
mkdir -p $trace_dir
mkdir -p $snapshots_dir

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
    elif (is_snapshot $input)
        then take_snapshot $input;
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
- Take a snapshot with \"!\" or \"!snapshot_name\"
- Display this help with \"?\"
- Press <CTRL+C> to exit.
"
}

function prompt_user {
    local prompt="input$([ $init = false ] && echo "(? for help)"): "
    read -ep "$prompt" input
    history -s "$input"
    echo ""
}

function is_help { [ $1 = "?" ]; }
function is_snapshot { [ ${1:0:1} = "!" ]; }
function is_wildcard { [ $1 = "." ]; }
function is_index { [[ $1 =~ ^[0-9]+$ ]]; }
function is_log_empty { [ ${#logs[@]} = "0" ]; }
function is_not_empty { [ "$(ls -A $1)" ]; }

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
    local filename="$@"
    filename="${filename// /_}"
    echo -n "[ ] tracing $@..."
    if (trace $filename); then
        success+="$@"
        echo -e -n "\r[✓] trace written to $trace_dir/$filename"
    else
        echo -e "\n[✗] bad trace written to $trace_dir/$filename"
        error_handling $filename
    fi
}

function write_trace_tsconfig {
    local str="{\n\t\"extends\": \"../$base_tsconfig\",\n"
    str+="\t\"include\": [\n"
    for file in "$@"; do
        if [[ $file == *.ts ]];
            then str+="\t\t\"../$file\",\n"
        else
            str+="\t\t\"../$file/**/*.ts\",\n"
        fi
    done
    str="${str::${#str}-3}\n\t]\n}"
    echo -e $str > $trace_tsconfig
}

function error_handling {
    local exit=false
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
        IFS=$'\n' read -d '' -r -a logs < $log_file
    else logs=()
    fi
}

function show_logs {
    if (!(is_log_empty)); then
        echo "Previously traced paths are:"
        local i=0
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
    local str=""

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

    echo -e ${str::${#str}-2} > $log_file
}

function count_snapshots {
    local count=0
    for dir in $snapshots_dir/*; do
        [[ -d $dir ]] && let count+=1
    done
    echo $count;
}

function take_snapshot {
    if (is_not_empty $trace_dir) then
        local name=$([ "${1:1}" = "" ] && echo $(count_snapshots) || echo ${1:1})
        mkdir -p $snapshots_dir/$name
        rm -rf $(ls $trace_dir | sed -E "s,(.*),$snapshots_dir/$name/\1/*,")
        mv $trace_dir/* $snapshots_dir/$name
        echo -n "[✓] contents of $trace_dir moved to $snapshots_dir/$name"
    else
        echo -n "[✗] no traces to move to $snapshots_dir"
    fi
}

while :; do main; done