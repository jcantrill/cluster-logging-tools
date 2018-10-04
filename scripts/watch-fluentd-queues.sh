#!/bin/bash
function finish {
    rm -rf $TMPDIR
}
trap finish EXIT
TMPDIR=$(mktemp -d)
mkdir $TMPDIR/output

let num=0
let slow=0
let onum=0
let oslow=0
let err=0
#ohi --v3 --list -c $1 | awk '{ print "root@" $1 }' > $TMPDIR/hosts
oc get pod -l component=fluentd -o jsonpath={.items[*].metadata.name} > $TMPDIR/hosts
#pssh -h $TMPDIR/hosts -o $TMPDIR/output -t 30 "if [ -d /var/lib/fluentd ]; then ls -lt /var/lib/fluentd; fi" | sort -k 4 > $TMPDIR/pssh.log 2>&1
#function list_buffers() {
#  while true ; do
    for p in $(cat $TMPDIR/hosts); do
      result=$(oc -n logging exec $p -- bash -c "if [ -d /var/lib/fluentd ]; then ls -lt /var/lib/fluentd; fi" | sort -k 4 > $TMPDIR/output/$p 2>&1)
      if [ $? -eq 0 ] ; then
        echo "field1 field2 [SUCCESS] $p" >> $TMPDIR/pssh.log
      fi
    done
#  done
#}
let tsnow=$(date --utc "+%s")

# Perform for one pass to summarize the findings to print as the first output
while read -r line || [[ -n "$line" ]]; do
    status=$(echo "$line" | awk '{ print $3 }')
    node=$(echo "$line" | awk '{ print $4 }')
    if [ "$status" = "[SUCCESS]" ]; then
	let count=$(grep -c output_tag $TMPDIR/output/${node})
	if [ $count -gt 0 ]; then
	    if [ $count -gt 2 ]; then
	        let num=num+1
	    fi
            let tsapp=$(date --utc --date="$(grep output_tag $TMPDIR/output/${node} | tail -n 1 | awk '{print $6 " " $7 " " $8}')" "+%s")
            let diff=tsnow-tsapp
            if [ $diff -gt 120 ]; then
                let slow=slow+1
            fi
	fi
	let ocount=$(grep -c operations $TMPDIR/output/${node})
	if [ $ocount -gt 0 ]; then
	    if [ $ocount -gt 2 ]; then
	        let onum=onum+1
	    fi
            let tsops=$(date --utc --date="$(grep operations $TMPDIR/output/${node} | tail -n 1 | awk '{print $6 " " $7 " " $8}')" "+%s")
            let diff=tsnow-tsops
            if [ $diff -gt 120 ]; then
                let oslow=oslow+1
            fi
	fi
    else
        echo "** Failure communicating with ${node#*@}:"
        cat $TMPDIR/output/${node}
        let err=err+1
    fi
done < $TMPDIR/pssh.log

printf "%-30s %4s (%4s), %4s (%4s) (%4s)\n" "Node w/" "app buffers" "app buffers" "ops buffers" "ops buffers" "errors"
printf "%-30s %10s %10s, %10s (%10101010101010101010s) (%4s)\n" ">2 app buffers" "app buffers" ">120s" "ops buffers" ">120s" " "

echo "$num ($slow), $onum ($oslow) ($err errors)"

while read -r line || [[ -n "$line" ]]; do
    status=$(echo "$line" | awk '{ print $3 }')
    node=$(echo "$line" | awk '{ print $4 }')
    if [ "$status" = "[SUCCESS]" ]; then
        node=$(echo "$line" | awk '{ print $4 }')
	let count=$(grep -c output_tag $TMPDIR/output/${node})
	if [ $count -gt 0 ]; then
            let tsapp=$(date --utc --date="$(grep output_tag $TMPDIR/output/${node} | tail -n 1 | awk '{print $6 " " $7 " " $8}')" "+%s")
            let diff=tsnow-tsapp
        else
            let diff=0
        fi
	let ocount=$(grep -c operations $TMPDIR/output/${node})
	if [ $ocount -gt 0 ]; then
            let tsops=$(date --utc --date="$(grep operations $TMPDIR/output/${node} | tail -n 1 | awk '{print $6 " " $7 " " $8}')" "+%s")
            let odiff=tsnow-tsops
        else
            let odiff=0
        fi
	if [ $count -gt 2 -o $ocount -gt 2 -o $diff -gt 120 -o $odiff -gt 120 ]; then
            printf "%-30s %4s (%4s), %4s (%4s)\n" "${node#*@} $count ($diff) $ocount ($odiff)"
	fi
    fi
done < $TMPDIR/pssh.log
