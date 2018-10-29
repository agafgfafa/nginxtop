#!/usr/bin/env bash
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

NGINX_LOG_PATH=/var/log/nginx
BRIEF=



usage() { echo "Usage: $0 [-b]" 1>&2; echo "  -b  Brief, no hit counts" 1>&2; exit 1; }

get_diskio() {
  read DSK_BI DSK_BO <<<$(vmstat 2 2 | tail -1 | awk '{printf "%d %d", $9/1024, $10/1024}');
}

# Get system connections
get_conn() {
  CONN_MAX=$(sysctl net.netfilter.nf_conntrack_max | awk '{print $3}');
  CONN_NOW=$(sysctl net.netfilter.nf_conntrack_count | awk '{print $3}');
  CONN_HR=$(echo "scale=1; $CONN_NOW*100/$CONN_MAX" | bc -l)
}

# Get basic system info
get_system() {
  # run top twice, as some values are not precise on first pass
  TOP_OUT=$(top -b -n2 | egrep "(KiB|Cpu)" | tail -3);

  CPU_USAGE=$(echo "$TOP_OUT" | egrep "^%Cpu" | awk '{print 100-$8'})
  read MEM_CACHE MEM_FREE <<<$(free -g | egrep "^Mem:" | awk '{print $7 " " $4'})
}

# Get base nginx info
get_nginx_base() {
  NGINX_TOTAL_HITS=0
  NGINX_CACHE_STATUS_STR=$(for CACHE_PATH in $(grep proxy_cache_path /etc/nginx/nginx.conf | awk '{print $2}'); do du $CACHE_PATH -sh | awk '{print $2 " " $1}'; done);
}

# get nginx hits
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

# Poll one-second interface stats from /proc/net/dev
get_onesecond_interface_data() {
  ONE_SEC_IF_DATA_START=$(cat /proc/net/dev | egrep "\s+[a-zA-Z0-9][^lo]+: [0123456789\s]+")
  sleep 1s
  ONE_SEC_IF_DATA_END=$(cat /proc/net/dev | egrep "\s+[a-zA-Z0-9][^lo]+: [0123456789\s]+")
}

# Calculate interface throughput, given one interface
# return is formatted
get_if_throughput() {
  IF=$1
  if [ -z "$IF" ]; then
    exit 7;
  fi
  read IFB RCVBB RCVPB RCVERRB RCVDROPB RCVFIFOB RCVFRAMEB RCVCOMPB RCVMULTB TXBB TXPB TXERRB TXDROPB TXFIFOB TXFRAMEB TXCOMPB  <<<$(echo "$ONE_SEC_IF_DATA_START" | grep "$IF")
  read IFE RCVBE RCVPE RCVERRE RCVDROPE RCVFIFOE RCVFRAMEE RCVCOMPE RCVMULTE TXBE TXPE TXERRE TXDROPE TXFIFOE TXFRAMEE TXCOMPE  <<<$(echo "$ONE_SEC_IF_DATA_END" | grep "$IF")
  RCVB_HR=$(echo "scale=0; ($RCVBE - $RCVBB) * 8" | bc -l | numfmt --to=si)
  TXB_HR=$(echo "scale=0; ($TXBE  - $TXBB) * 8" | bc -l | numfmt --to=si)
  RCVP_HR=$(echo "scale=0; $RCVPE - $RCVPB" | bc -l | numfmt --to=si)
  TXP_HR=$(echo "scale=0; $TXPE - $TXPB" | bc -l | numfmt --to=si)

  printf "%s        %s     %s       |    %s    %s" "$IFB" "$TXB_HR" "$TXP_HR" "$RCVB_HR" "$RCVP_HR"
}

# the UI
display() {
  clear;
  echo "ngxtop - $(hostname)    $(date)"
  echo
  echo "System -----------"
  echo "Cpu usage $CPU_USAGE%"
  echo "Disk IO $DSK_BI read $DSK_BO write MB/s"
  echo "Mem $MEM_CACHE cache $MEM_FREE free GB"
  echo "IP Connections $CONN_NOW/$CONN_MAX ($CONN_HR%)"

  if [ ! -z "$INTERFACE_STATS" ] ; then
    echo
    echo "Interface   TX bps   pkts/sec   |  RX bps  pkts/sec"
    echo "$INTERFACE_STATS"
  fi 

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


echo "Gathering metrics...."

while [ 1 ]; do
  INTERFACE_STATS=""

  get_diskio
  get_conn
  get_system
  get_nginx_base
  if [ ! $BRIEF ]; then
    get_nginx_hits

    # Get formatted interface data 
    get_onesecond_interface_data
    while read line ; do
      INTERFACE=$(echo $line | awk '{print $1}')
      IF_THRU=$(get_if_throughput $INTERFACE)
      INTERFACE_STATS=$INTERFACE_STATS$IF_THRU
    done < <(echo "$ONE_SEC_IF_DATA_START")
  else
    get_nginx_cacheonly
 fi
  display
done