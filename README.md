# nginxtop

A bash script using basic tools to monitor NGINX web server performance, including cache hit rate and top 3 IP addresses per site.

You should see something like this:

```
ngxtop - nginx2    Fri Oct 19 09:19:50 EDT 2018

System -----------
Cpu usage 6.9%
Disk IO 0 read 2 write MB/s
Mem 77 cache 46 free GB
IP Connections 17402/400000 (4.3%)

Nginx ------------
Cache store
/var/cache/nginx/proxy_temp/ 28G
/var/cache/nginx/proxy_combined/ 26G

Total hits 54M since midnight
                     Site   Hits  Cache  Top IP Addresses (last 5K req) 
            your.site.com:   15M   93%       172.16.7.11: 749       10.2.11.77: 146    192.168.0.44: 119
   anothersite.domain.net:   66K   51%     10.102.224.88: 132       10.2.11.77: 111    172.34.239.1:  16
        static.domain.net:   25M   90%   192.168.112.211: 249   172.31.111.123:  45  192.168.124.11:  37
           docs.vhost.com:   12M   64%      10.26.100.72: 570   172.19.191.217: 134   192.168.29.86: 111
```

I couldn't find anything else that didn't require more installation time that just writing this using basic bash tools.


## Getting Started

Clone repo, chmod 700 nginxtop.sh ; ./nginxtop.sh


### Prerequisites

This script was written on Linux systems and does not necessarily work on *BSD or Mac. It relies on the most basic tools that should be available to any minimal Linux install, such as grep, awk, vmstat, sysctl and echo.


### Installing

Place the nginxtop.sh script in /usr/local/bin, chmod 700 nginxtop.sh ; nginxtop.sh


## Contributing

Contributions welcome, just submit a pull request. Please ensure the EPL 2.0 License header is part of new files, and your commit includes a Signed-Off-By footer.


## Authors

* **Denis Roy** - *Initial implementation* - [Eclipse Foundation](https://eclipse.org/)


## License

This project is licensed under the Eclipse Public License 2.0 - see the [LICENSE.md](LICENSE.md) file for details
