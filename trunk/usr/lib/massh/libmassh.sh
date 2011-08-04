# The Massh Function Library File

# Means For Locating and Verifying Non-Builtins
function Validate {
    [ -d "$1" ] && Results="$1" && return 0
    ItsType=$(type -t $1 || return 1)
    [[ "${ItsType}" == +(file) ]] && Results=$( type -P $1 ) && return 0
    [[ "${ItsType}" == +(alias|keyword|function|builtin)  ]] && return 1
}

# Generate $HOME/.massh/hosts/results
function Generate_Results {
    [[ "$SubCommand" = "worked" || "$SubCommand" = "bombed" ]] \
    && echo -e \
        "#\n# Summary - $TimeStamp $MyNameIs $MyHostGroup $SubCommand $@\n#" \
        > $UsrFiles/hosts/results
}

# Logging
function Are_We_Loggin {
    [ "$SyslogMassh" = "yes" ]  || return 1
    ${logger} -i -t $MyNameIs -- "USER=$USER COMMAND=$MyNameIs $@"
}

# Options Listing
function List_Options {
    local AllOptions=$(${grep} ^[A-Z].*\=\".*\"[\ ]*$ $AllConf || echo "NONE")
    local UsrOptions=$(${grep} ^[A-Z].*\=\".*\"[\ ]*$ $UsrConf || echo "NONE")

    echo -e "\nSystem Default Options\n----------------------\n$AllOptions"
    echo -e "\nUser Specified Options\n----------------------\n$UsrOptions\n"

    exit 0
}

# Options Editing
function Edit_Options {
    [ -z "$3" ] && exit 1

    TargetOption=$(${grep} -h ^$3.*\=\".*\"[\ ]*$ $AllConf $UsrConf|${tail} -1)
    OptionValue=$(${sed} -e 's/^.*\"\(.*\)\".*$/\1/g' <(echo "$TargetOption"))

    echo -e    "Updating Option : $3"
    echo       "Current Value   : $OptionValue"
    read -e -p 'Enter New Value : ' UsrOptionValue 2>&1

    [ -z "$UsrOptionValue" ] \
        && ${grep} -v $3 $UsrConf > $UsrConf.new \
        && UsrOption=$(echo "$3=\"\"") \
        && echo "$UsrOption" >> $UsrConf.new \
        && ${mv} $UsrConf{.new,} \
        && echo -e "$UsrOption" \
        && exit 0

    [ -f "$UsrConf" ] \
        && ${grep} -v $3 $UsrConf > $UsrConf.new \
        && UsrOption=$(echo "$3=\"$UsrOptionValue\"") \
        && echo "$UsrOption" >> $UsrConf.new \
        && ${mv} $UsrConf{.new,} \
        && echo -e "$UsrOption" \
        && exit 0

    exit 0
}

# Parallel SSH w/ Full Output
function Parallel_SSH_Output_Verbose {
    ${ssh} ${SSHOPTS[*]} ${List[$Host]} "$@" \
        &>$TmpDir/$Random.${List[$Host]}
}

# Parallel SSH w/ Terse Output
function Parallel_SSH_Output_Terse {
    ${ssh} ${SSHOPTS[*]} ${List[$Host]} "$@" &>/dev/null
    [ $? -eq 0 ] \
        && echo "${List[$Host]} : Command Succeeded" \
        || echo "${List[$Host]} : Command Failed"
}

# Parallel SSH w/ Output of Hosts Where Command Worked
function Parallel_SSH_Output_Worked {
    ${ssh} ${SSHOPTS[*]} ${List[$Host]} "$@" &>/dev/null
    [[ $? -eq 0 && "$SubCommand" = "worked" ]] \
        && echo "${List[$Host]}" \
        | ${tee} -a $UsrFiles/hosts/results
}

# Parallel SSH w/ Output of Hosts Where Command Bombed
function Parallel_SSH_Output_Bombed {
    ${ssh} ${SSHOPTS[*]} ${List[$Host]} "$@" &>/dev/null
    [[ $? -ne 0 && "$SubCommand" = "bombed" ]] \
        && echo "${List[$Host]}" \
        | ${tee} -a $UsrFiles/hosts/results
}

# Parallel SSH File Pushing
function Parallel_SSH_File_Push {
    ${scp} ${SSHOPTS[*]} $FileToPush "$@" ${List[$Host]}: &>/dev/null
    [ $? -eq 0 ] \
        && echo "${List[$Host]} : Push Succeeded" \
        || echo "${List[$Host]} : Push Failed"
}

# Parallel SSH File Pulling
function Parallel_SSH_File_Pull {
    ${mkdir} -p $UsrFiles/pull/${List[$Host]}/$(${dirname} "$@")
    ${scp} -pr ${SSHOPTS[*]} ${List[$Host]}:"$@" \
        $UsrFiles/pull/${List[$Host]}"$@" >/dev/null
    [ $? -eq 0 ] \
        && echo "${List[$Host]} : Pull Succeeded" \
        || echo "${List[$Host]} : Pull Failed"
}

# Parallel SSH Running Local Script On Remote Hosts
function Parallel_SSH_Script_Exec {
    ${ssh} ${SSHOPTS[*]} ${List[$Host]} 'bash -s' < "$@" \
         &>$TmpDir/$Random.${List[$Host]}
}

# Pushing Keys
function Parallel_SSH_Push_Key {
    /usr/bin/sshpass -e ssh ${SSHOPTS[*]} ${List[$Host]} 'bash -s' < "$@" \
         &>$TmpDir/$Random.${List[$Host]}
}

# Massh Flight Loop
function Flight_Loop {

    # This Keeps The Loop Open
    Airbourne="0"

    # Looping List
    for Host in ${!List[*]}
    do
        # Determine Number of In Flight Connections 
        RunningNow=$(jobs -p | ${wc} -l)

        while [ "$RunningNow" -ge "$Parallel" ]
        do
            RunningNow=$(jobs -p | ${wc} -l)
        done

        if [ "$SubCommand" = "push"    ]
        then
            Parallel_SSH_File_Push "$@" &
            continue
        fi
        if [ "$SubCommand" = "pull"    ]
        then
            Parallel_SSH_File_Pull "$@" &
            continue
        fi
        if [ "$SubCommand" = "execute" ]
        then
            Parallel_SSH_Script_Exec "$@" &
            InFlight[$!]=${List[$Host]}
        fi
        if [ "$SubCommand" = "key"     ]
        then
            Parallel_SSH_Push_Key "$@" &
            InFlight[$!]=${List[$Host]}
        fi
        if [ "$SubCommand" = "worked"  ]
        then
            Parallel_SSH_Output_Worked "$@" &
            continue
        fi
        if [ "$SubCommand" = "bombed"  ]
        then
            Parallel_SSH_Output_Bombed "$@" &
            continue
        fi
        if [ "$SubCommand" = "terse"   ]
        then
            Parallel_SSH_Output_Terse "$@" &
            continue
        fi
        if [ "$SubCommand" = "verbose" ]
        then
            Parallel_SSH_Output_Verbose "$@" &
            InFlight[$!]=${List[$Host]}
        fi

        for DepartingAndFlying in ${!InFlight[*]}
        do
            if ! kill -0 $DepartingAndFlying &>/dev/null
            then
                while read line
                do
                    echo "${InFlight[$DepartingAndFlying]} : $line"
                done <$TmpDir/$Random.${InFlight[$DepartingAndFlying]}
                [ "$Separator" = "yes" ] && echo "-"
                ${rm} -f $TmpDir/$Random.${InFlight[$DepartingAndFlying]}
                unset InFlight[$DepartingAndFlying]
            fi
        done
        [ ${#InFlight[*]} -eq 0 ] && let "Airbourne++"
    done
    while [ "$Airbourne" -lt 1 ] 
    do
        for FlyingAndArriving in ${!InFlight[*]}
            do  
                # Check For Timeout Threshold Violation
                [ $SECONDS -gt $TimeOut ] && exit 0

                if ! kill -0 $FlyingAndArriving &> /dev/null
                then
                    while read line
                    do
                        echo "${InFlight[$FlyingAndArriving]} : $line"
                    done <$TmpDir/$Random.${InFlight[$FlyingAndArriving]}
                    [ "$Separator" = "yes" ] && echo "-"
                    ${rm} -f $TmpDir/$Random.${InFlight[$FlyingAndArriving]}
                    unset InFlight[$FlyingAndArriving]
                fi
            done
        [ ${#InFlight[*]} -eq 0 ] && let "Airbourne++"
    done
}

# Bail Gracefully
function Failed {
    MyNameIs=$(echo $MyNameIs | ${sed} -e 's/^[a-z]?/[A-Z]/g')
    ${Logger} -i -t $MyNameIs -- "Error - $@"
    echo "$@"
    exit 2
}
