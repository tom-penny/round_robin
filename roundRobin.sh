#!/bin/bash

validateInput()
{
    throwError()
    {
        echo "$@" >&2                                                           # Print error message to stderr
        exit 1
    }

    [ -v $1 ] && throwError "No arguments specified"                            # Check arguments exist
    [ ! -f "./$1" ] && throwError "File not found"                              # Check file path exists

    words=$(awk "{n+=NF} END {print n/NR}" $1)                                  # Calculate average args per line
    
    [ ! "$words" == "3" ] && [ ! "$words" == "4" ] && \
    throwError "Data file must contain lines of 3 OR 4 arguments"               # Check average args is 3 OR 4

    quantum=${2:-1}													            # Set quantum value to '1' if $2 is unset

    [[ ! $quantum =~ ^-?[0-9] ]] && throwError "Quantum must be an integer"     # Check quantum arg is integer
    [ $quantum -lt 0 ] && throwError "Negative time quantum not supported"      # Check quantum arg is positive

}; validateInput $@

exec > >(tee output.txt) >&1									                # Copy stdout to output.txt

mapfile -t data < $1;                                                           # Map lines of file input to array
dataRef=("${data[@]%% *}")                                                      # Create record array for process order

bubbleSort()                                                                    # Sort processes by arrival time (ascending)
{
    length=${#data[@]}
    for ((i = 0; i < $length; i++))
    do
        for ((j = 0; j < $length-$i-1; j++))
        do
            line=(${data[j]})
            next=$((j+1))
            nextLine=(${data[$next]})
        
            if [  ${line[1]} -gt ${nextLine[1]} ]                               # If arrival greater than next arrival
            then
                val=${data[j]}
                data[$j]=${data[$next]}                                         # Switch process positions in array
                data[$next]=$val
            fi		
        done	
    done
}; bubbleSort

time=0
count=0
finished=false
queue=()
index=0
switches=0

declare -A processStatus												        # Create assoc array for process statuses
declare -A arrivalTime                                                          # Create assoc array for arrival times
declare -A burstTime                                                            # Create assoc array for burst times
declare -A priorityFlag                                                         # Create assoc array for priority flags
declare -A remainingTime                                                        # Create assoc array for remaining bursts
declare -A turnaroundTime                                                       # Create assoc array for turnaround times
declare -A waitTime                                                             # Create assoc array for wait times
declare -A responseTime

for line in "${data[@]}"                                                        # Initialise associative arrays
do
    args=($line)
    name=${args[0]}
    processStatus[$name]="-"
    arrivalTime[$name]=${args[1]}
    burstTime[$name]=${args[2]}
    remainingTime[$name]=${args[2]}
    priorityFlag[$name]=${args[3]:-"L"}                                         # Set priority to 'L' if flag unset
done

displayStatus()                                                                 # Display status of each process
{
        currentStatus="$time"
        for ref in ${dataRef[@]}
        do
            currentStatus+=" ${processStatus[$ref]}"
        done
        echo $currentStatus
}

echo "T ${dataRef[@]}"

until $finished
do
	while [ ! ${#data[@]} -eq 0 ]                                               # While processes are pending
	do
		name=(${data[0]%% *})
        arrival=${arrivalTime[$name]}

        [ ! $arrival -eq $time ] && break                                       # If process is arriving

        processStatus[$name]="W"                                                # Set process to "waiting"
        queue+=($name)                                                          # Add process to queue
        data=("${data[@]:1}")                                                   # Remove process from array
    done

    if [ -v queue[$index] ]                                                     # If process is queued
    then
        name=${queue[$index]}
        processStatus[$name]="R"                                                # Set process to "running"
        if [ ! -v responseTime[$name] ]                                         # If response time is unset
        then
            arrival=${arrivalTime[$name]}
            responseTime[$name]=$((time-arrival))                               # Update process response time
        fi
        displayStatus                                                           # Display status of each process

        count=$((count+1))                                                      # Increment quantum counter
        burst=${remainingTime[$name]}
        remainingTime[$name]=$((burst-1))                                       # Decrement process burst time

        priority=1                                                              # Set low priority
        [ ${priorityFlag[$name]} == "M" ] && priority=2                         # Set medium priority
        [ ${priorityFlag[$name]} == "H" ] && priority=3                         # Set high priority

        if [ ${remainingTime[$name]} -eq 0 ]                                    # If process burst time == 0
        then
            TT=$((time-arrivalTime[$name]))
            turnaroundTime[$name]=$TT
            WT=$((TT-burstTime[$name]))
            waitTime[$name]=$WT
            
            processStatus[$name]="F"                                            # Set process to "finished"
            index=$((index+1))                                                  # Move queue index pointer +1
            count=0                                                             # Reset quantum counter
            if [ -v queue[$index] ]                                             # If processes in queue
            then
                switches=$((switches+1))                                        # Increment context switches +1
            fi                  
        elif [ $count -eq $((quantum*priority)) ]                               # If quantum counter == quantum
        then
            processStatus[$name]="W"                                            # Set process to "waiting"
            queue+=($name)                                                      # Move process to end of queue
            index=$((index+1))                                                  # Move queue index pointer +1
            count=0                                                             # Reset quantum counter
            switches=$((switches+1))                                            # Increment context switches +1
        fi

    elif [ ${#data[@]} -eq 0 ]                                                  # If no processes are pending
    then
        finished=true                                                           # Algorithm complete
        displayStatus                                                           # Display status of each process
    fi
    if [ ! -v queue[$index] ]                                                   # If queue is empty
    then
        status=$(displayStatus)
        [[ ! $status =~ "F" ]] && echo $status                                  # Display null status
    fi
    time=$((time+1))                                                            # Increment time +1
done

totalTime=0

endTT="TT"
avgTT=0
endWT="WT"
avgWT=0
endRT="RT"
avgRT=0

for ref in ${dataRef[@]}                                                        # Calculate time averages
do
    TT=${turnaroundTime[$ref]}
    WT=${waitTime[$ref]}
    RT=${responseTime[$ref]}
    [ $WT -eq -1 ] && WT=0
    totalTime=$((totalTime+TT-WT))
    avgTT=$((avgTT+TT))
    avgWT=$((avgWT+WT))
    avgRT=$((avgRT+RT))
    endTT+=" $TT"
    endWT+=" $WT"
    endRT+=" $RT"
done

adjTime=$((totalTime+switches))                                                 # Adjust time for context switches

echo
echo $endTT
echo $endWT
echo $endRT
echo
echo "Avg TT = $(awk "BEGIN {printf \"%.2f\",$avgTT/${#dataRef[@]}}")"          # Display average turnaround time
echo "Avg WT = $(awk "BEGIN {printf \"%.2f\",$avgWT/${#dataRef[@]}}")"          # Display average wait time
echo "Avg RT = $(awk "BEGIN {printf \"%.2f\",$avgRT/${#dataRef[@]}}")"          # Display average response time
echo "CS = $switches"                                                           # Display number of context switches
echo
echo "Std TP = $(awk "BEGIN {printf \"%.4f\",${#dataRef[@]}/$totalTime}")"      # Display standard throughput
echo "Adj TP = $(awk "BEGIN {printf \"%.4f\",${#dataRef[@]}/$adjTime}")"        # Display CS-adjusted throughput

exit 0