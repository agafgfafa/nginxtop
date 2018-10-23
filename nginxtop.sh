#! /usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2018 Eclipse Foundation.
# This program and the accompanying materials are made available
# under the terms of the Eclipse Public License 2.0
# which is available at http://www.eclipse.org/legal/epl-v20.html
# SPDX-License-Identifier: EPL-2.0
# Initial implementation: Denis Roy <denis.roy@eclipse-foundation.org>
#*******************************************************************************

# nginx 'top' for monitoring
# please see: https://github.com/agafgfafa/nginxtop/blob/master/README.md

# this script makes the following assumptions:
# 1. Each virtual hosts' log path is formatted as:
#    /var/log/nginx/site1/access.log, /var/log/nginx/site2/access.log, ...   
# 2. Virtual host logs are only readable by the nginx/root user
# 3. For cache hit performance, the $upstream_cache_status is part of your access.log
# 4. You're running nginx on Linux. Haven't tested any other platforms


set -o errexit
set -o nounset
set -o pipefail

[ ${EUID} -eq 0 ] || {
    echo "You must be root to run this script."
    exit 12
}

# tuneable knobs
NGINX_LOG_PATH=/var/log/nginx
BRIEF=

# functions
usage() { echo "Usage: $0 [-b]" 1>&2; echo "  -b  Brief, no hit counts" 1>&2; exit 1; }

get_diskio() {
  read DSK_BI DSK_BO <<<$(vmstat 2 2 | tail -1 | awk '{printf "%d %d", $9/1024, $10/1024}');
}

get_conn() {
  CONN_MAX=$(sysctl net.netfilter.nf_conntrack_max | awk '{print $3}');
  CONN_NOW=$(sysctl net.netfilter.nf_conntrack_count | awk '{print $3}');
  CONN_HR=$(echo "scale=1; $CONN_NOW*100/$CONN_MAX" | bc -l)
}

get_system() {
  # run top twice, as some values are not precise on first pass
  TOP_OUT=$(top -b -n2 | egrep "(KiB|Cpu)" | tail -3);

  CPU_USAGE=$(echo "$TOP_OUT" | egrep "^%Cpu" | awk '{print 100-$8'})
  MEM_CACHE=$(echo "$TOP_OUT" | egrep "KiB Swap" | awk '{printf "%d", $9/100000'})
  MEM_FREE=$(echo "$TOP_OUT"  | egrep "KiB Mem" | awk '{printf "%d", $6/100000'})
}

get_nginx_base() {
  NGINX_TOTAL_HITS=0
  NGINX_CACHE_STATUS_STR=$(for CACHE_PATH in $(grep proxy_cache_path /etc/nginx/nginx.conf | awk '{print $2}'); do du $CACHE_PATH -sh | awk '{print $2 " " $1}'; done);
}

get_nginx_hits() {
  NGINX_SITE_STATUS_STR=$(printf "%25s   %s  %s  %s \n" "Site" "Hits" "Cache" "Top IP Addresses (last 5K req)";
                for SITE in $(find $NGINX_LOG_PATH -mindepth 1 -maxdepth 1 -type d | egrep -o "[A-Za-z0-9\.-]+$" | sort); do  
                        HITS=$(wc -l $NGINX_LOG_PATH/$SITE/access.log | awk '{print $1}'); 
                        HITS_HR=$(numfmt --to=si $HITS);
                        ((NGINX_TOTAL_HITS+=$HITS));
                        CACHE_HITS=$(tail -n 5000 $NGINX_LOG_PATH/$SITE/access.log | grep -c " HIT "); 
                        CACHE_HIT_RATE=$(echo "scale=0; $CACHE_HITS/50" | bc -l);
                        TOP_IP=$(get_nginx_topip_per_site $SITE);
                        printf "%25s: %5s   %2d%%   %s\n" "$SITE" "$HITS_HR" "$CACHE_HIT_RATE" "$TOP_IP"; 
                done; echo "$NGINX_TOTAL_HITS totalhits");
  NGINX_TOTAL_HITS=$(echo $NGINX_SITE_STATUS_STR | egrep -o "[0-9]+ totalhits" | awk '{print $1}')
  NGINX_TOTAL_HITS_HR=$(numfmt --to=si $NGINX_TOTAL_HITS)
}

get_nginx_cacheonly() {
  NGINX_SITE_STATUS_STR=$(printf "%25s  %s  %s \n" "Site" "Cache" "Top IP Addresses (last 5K req)";
                for SITE in $(find $NGINX_LOG_PATH -mindepth 1 -maxdepth 1 -type d | egrep -o "[A-Za-z0-9\.-]+$" | sort); do  
                        CACHE_HITS=$(tail -n 5000 $NGINX_LOG_PATH/$SITE/access.log | grep -c " HIT "); 
                        CACHE_HIT_RATE=$(echo "scale=0; $CACHE_HITS/50" | bc -l);
                        TOP_IP=$(get_nginx_topip_per_site $SITE);
                        printf "%25s:  %2d%%  %s \n" "$SITE" "$CACHE_HIT_RATE" "$TOP_IP"; 
                done;)
}

get_nginx_topip_per_site() {
  SITE=$1
  tail -n 5000 $NGINX_LOG_PATH/$SITE/access.log | awk '{print $1}' | sort | uniq -c | sort -nr | awk 'BEGIN{ORS=" "} FNR<=3 {printf "%15s:%4d ", $2, $1}'
}


display() {
  clear;
  echo "nginxtop - $(hostname)    $(date)"
  echo
  echo "System -----------"
  echo "Cpu usage $CPU_USAGE%"
  echo "Disk IO $DSK_BI read $DSK_BO write MB/s"
  echo "Mem $MEM_CACHE cache $MEM_FREE free GB"
  echo "IP Connections $CONN_NOW/$CONN_MAX ($CONN_HR%)"
  echo
  echo "Nginx ------------"
  echo "Cache store"
  echo "$NGINX_CACHE_STATUS_STR"
  echo
  if [ ! $BRIEF ]; then
    printf "Total hits %s since midnight\n" "$NGINX_TOTAL_HITS_HR"
  fi
  echo "$NGINX_SITE_STATUS_STR" | egrep -v totalhits
}


###
# main

while getopts ":b" opt; do
  case $opt in
    b)
      BRIEF=1;
      ;;
    \?)
      usage
      ;;
  esac
done


echo "Gathering metrics..."
while [ 1 ]; do
  get_diskio
  get_conn
  get_system
  get_nginx_base
  if [ ! $BRIEF ]; then
    get_nginx_hits
  else
    get_nginx_cacheonly
  fi
  display
done