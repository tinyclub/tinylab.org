---
title: 'vnStatSVG: Linux 流量监控'
tagline: '最佳 vnStat Web 前端，专为嵌入式与分布式系统设计'
author: Wu Zhangjin
layout: page
permalink: /vnstatsvg/
update: 2015-10-1
description: 用于监控 Linux 主机、集群甚至嵌入式设备的网络流量
categories:
  - 开源项目
  - 流量监控
  - vnStatSVG
tags:
  - vnStat
---

> by falcon of [TinyLab.org][2]
> 2013/08/03 02:33

## Introduction

vnStatSVG is a lightweight AJAX based web front-end for network traffic monitoring.

To use it, its backend vnStat: <http://humdi.net/vnstat/> must be installed at first.

It only requires a CGI-supported http server but also generates a graphic report with SVG output, Compare to its counterparts, it has such features:

  * Generates graphic output dynamically with SVG and AJAX 
  * Not only works with Apache, Nginx but also works with Busybox httpd and even any other lightweight httpd servers 
  * Only need CGI support, No PHP and other modules needed 
  * Need very little bandwidth consumption for only transfer few data in XML format, the XSL, js and CSS files only need to be transferred once 
  * Supports to monitor multi-interfaces (eth0, eth1&#8230;) of a single host 
  * Supports to monitor multi-hosts (of a cluster) in one window 
  * Supports multi-protocols(http, ftp, file and even ssh) to transfer data between target hosts and the main web service host 
  * Support different web browsers, the latest chromium and firefox have been tested 
  * Support multi XML data dump methods, include a shell script version, a standalone C version and a &#8216;plugin&#8217; to the official vnStat (only 1.6 currently) 

In a word, vnStatSVG is friendly to generic Linux hosts, servers, embedded Linux systems and even Linux clusters.

This project is launched by Falcon in 2008 when I was a student and it has been hosted in <http://sourceforge.net/projects/vnstatsvg/>, the previous latest version is 1.0.7, after that, I moved to other topics and stopped its update.

In the past 2 weeks, I started to reactivate this project and continue its maintaining, now, It is hosted in github.com: <https://github.com/tinyclub> for its friendly git access, see its repository address:

  * Git homepage: <https://github.com/tinyclub/vnstatsvg> 
  * Git repository: https://github.com/tinyclub/vnstatsvg.git 
  * Demo site: <https://tinylab.org/vnstatsvg-demo/>
  * Paper: [A CGI+AJAX+SVG based monitoring method for distributed and embedded system][3] 

The 1st release candidate of version 2.0 is ready, it has fixed up some issues found in the early 1.0.7 and has added some new features. In the coming 2.0 release, no more new functions will be added, but new fixups will be added to make those new features become stable enough.

## Take a look at a demo site

Before getting start to download, install and use vnStatSVG, Let us take a look at the [demo site][1].

<img alt="" src="/wp-content/uploads/file/vnstatsvg-homepage.png" style="width: 580px; height: 478px;" />

Take a look at the left sidebar, a list of hosts and the according network interfaces are present, hit any of them, you will get the hidden menu out:

<img alt="" src="/wp-content/uploads/file/vnstatsvg-sidebar.png" style="width: 580px; height: 478px;" />

Now, 6 different entries come out and the right part tells us the current monitored network host and interface, and allows us to monitor network traffic through click the entries, use &#8216;Hour&#8217; data as an example:

<img alt="" src="/wp-content/uploads/file/vnstatsvg-network-traffic-per-hour.png" style="width: 580px; height: 1015px;" />

The output include two parts, one is in SVG format, another is its original data listed in a table. The output style of the other entries are basically the same but with different data, the &#8216;Second&#8217; entry is a little different, this data is not generated by the vnStat backend, but collected from the Linux network traffic statistic interface: **/proc/net/dev** directly every second, so, it is &#8216;real time&#8217; data.

To monitor the other hosts and their interfaces, we can simply click them on the left sidebar and get the network traffic of &#8216;Summary&#8217;, &#8216;top10 day&#8217;, &#8216;per day&#8217;, &#8216;per month&#8217;, &#8216;per hour&#8217; and &#8216;per second&#8217;.

## Getting start with the lightweight backend: vnStat

Take a look at its offical introduction at first:

> vnStat is a console-based network traffic monitor for Linux and BSD that keeps a log of network traffic for the selected interface(s). It uses the network interface statistics provided by the kernel as information source. This means that vnStat won&#8217;t actually be sniffing any traffic and also ensures light use of system resources. However, in Linux at least a 2.2 series kernel is required.

In Linux, as we mentioned above, the network traffic statistic interface is <strong style="font-size: 13px;">/proc/net/dev/</strong>, its output looks below:

<pre>$ cat /proc/net/dev
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  eth0: 180272431  154277    0    0    0     0          0         0 17004672  153875    0    0    0     0       0          0
    lo: 1020338    8975    0    0    0     0          0         0  1020338    8975    0    0    0     0       0          0
</pre>

As we can see, the ***bytes*** and ***packets*** ***received*** and ***transmitted*** of each network interfaces (eth0, lo&#8230;) have been listed.

But as we know, the files in **/proc** file system is in memory, which will be lost after system reboot, so, vnStat is written to save the data to a persistent file in a disk.

To save the data timely, vnStat should be run periodically, for example, get the data in every 5 seconds and provide data as fresh as possible, but to save cpu and power cost, the period should be not too small, 5 seconds should be enough for daily statistic.

### Install and use vnStat on Ubuntu

Now, Let&#8217;s install vnStat in Ubuntu at first:

<pre>$ sudo apt-get install vnstat
</pre>

Ubuntu will install a daemon to execute vnStat periodically, no need to setup a cron service or write your own daemon again:

<pre>$ ps -ef | grep vnstat
root      1371     1  0 Aug02 ?        00:00:00 /usr/sbin/vnstatd -d
</pre>

Now, let&#8217;s take a look at how to use it, firstly, overview its options:

<pre>$ vnstat --help
 vnStat 1.11 by Teemu Toivola &lt;tst at="" dot="" fi="" iki="">
         -q,  --query          query database
         -h,  --hours          show hours
         -d,  --days           show days
         -m,  --months         show months
         -w,  --weeks          show weeks
         -t,  --top10          show top10
         -s,  --short          use short output
         -u,  --update         update database
         -i,  --iface          select interface (default: eth0)
         -?,  --help           short help
         -v,  --version        show version
         -tr, --traffic        calculate traffic
         -ru, --rateunit       swap configured rate unit
         -l,  --live           show transfer rate in real time
See also '--longhelp' for complete options list and 'man vnstat'.
&lt;/tst></pre>

And show its daily traffic with the **-t** option:

<pre>$ vnstat -t
 eth0  /  top 10
    #      day          rx      |     tx      |    total    |   avg. rate
   -----------------------------+-------------+-------------+---------------
    1   07/27/13       1.09 GiB |    1.28 GiB |    2.38 GiB |  230.62 kbit/s
    2   07/07/13       1.00 GiB |  179.97 MiB |    1.17 GiB |  113.84 kbit/s
    3   06/29/13     636.57 MiB |  246.67 MiB |  883.24 MiB |   83.74 kbit/s
    4   07/16/13     792.17 MiB |   35.14 MiB |  827.31 MiB |   78.44 kbit/s
    5   07/21/13     679.28 MiB |   97.92 MiB |  777.21 MiB |   73.69 kbit/s
    6   07/20/13     421.73 MiB |   87.03 MiB |  508.76 MiB |   48.24 kbit/s
    7   07/06/13     466.12 MiB |   27.79 MiB |  493.91 MiB |   46.83 kbit/s
    8   07/24/13     394.07 MiB |   57.00 MiB |  451.07 MiB |   42.77 kbit/s
    9   07/30/13     386.93 MiB |   38.82 MiB |  425.74 MiB |   40.37 kbit/s
   10   06/30/13     374.99 MiB |   28.08 MiB |  403.07 MiB |   38.22 kbit/s
   -----------------------------+-------------+-------------+---------------
</pre>

Without the **-i** option, the default interface is **eth0**. To update the data and store it to the database immediately, use the **-u** option:

<pre>$ vnstat -u -i eth0
</pre>

To learn more options, please use **&#8211;longhelp** option or access its homepage: <http://humdi.net/vnstat/>

The default database used by vnStat is under **/var/lib/vnstat/**, the database are named with the interface name. the database format is specifically designed by the author of vnStat, it can be parsed by vnStat itself, so, no extra datbase tool required. The default configure file is installed to **/etc/vnstat.conf**, you can configure the default interface and database storing directory there.

### Compile and Install vnStat from source code

To use vnStat for a platform without prebuilt packages, especially for a new created embedded system, we may need to compile and even cross compile vnStat from source code and configure it ourselves, Herein will discuss it.

Download the latest version from its homepage: <http://humdi.net/vnstat/> and decompress it:

<pre>$ wget -c http://humdi.net/vnstat/vnstat-1.11.tar.gz
$ tar zxf vnstat-1.11.tar.gz
</pre>

And now, compile it and install it:

<pre>$ make ; make install
</pre>

Then, let **cron** service update the database periodically with the default cron config file: **examples/vnstat.cron**, copy it to **/etc/cron.d/** or use **crontab -e** command to edit it. Herein, will introduce a simple daemon written in shell script which works like cron but without its dependency, which allows us to update on the embedded system without the installation of a cron service, see below:

<pre>#!/bin/sh
# vnstat-update.sh -- a simple daemon to update database of vnstat in specified period
VNSTAT=/usr/bin/vnstat
IFACE=eth0
PERIOD=5
while :;
do
    $VNSTAT -u -i $IFACE
    sleep $PERIOD
done
</pre>

Save the above script to **/usr/bin** and append a simple line at the end of your system&#8217;s **/etc/rc.local** (or similar script file will run during boot) may let it work.

<pre>/usr/bin/vnstat-update.sh &#038;
</pre>

### Cross compile it for ARM platform

vnStat itself support cross compling, but no direct method, herein, let&#8217;s discuss how to compile it for ARM platform as an example.

Firstly, let&#8217;s install a cross compiler, in Ubuntu 12.10 (or newer) host, we can simply install it:

<pre>$ sudo apt-get install gcc-arm-linux-gnueabi
</pre>

On other Linux systems which don&#8217;t provide a prebuilt cross compiler package, the Linaro one is recommended, see: <https://launchpad.net/linaro-toolchain-binaries>

Now, Let&#8217;s cross compile vnStat, at first, should replace the **host gcc** with **cross gcc**:

<pre>$ sed -i -e 's/gcc/arm-linux-gnueabi-gcc/g' src/Makefile
$ make
</pre>

If want a standalone binary, link it statically with **-static**, Let&#8217;s configure it for **CFLAGS**:

<pre>$ sed -i -e 's/-O2/-static -O2/g' src/Makefile
</pre>

Afterwards, we will get the ARM binary:

<pre>$ file src/vnstat
src/vnstat: ELF 32-bit LSB executable, ARM, version 1 (SYSV), dynamically linked (uses shared libs), for GNU/Linux 2.6.31, BuildID[sha1]=0xbb188e3e644cee77282f1d99652aae0285062607, not stripped
</pre>

Then, install it to the target file system specified with **DESTDIR** environment variable, Let&#8217;s assume the target embedded file system is **../target**. To install it, we should at first specify the right **cross strip** for the **install** command and then install to **../target**:

<pre>$ sed -i -e 's/install -s/install -s --strip-program=arm-linux-gnueabi-strip/g'; Makefile
$ mkdir ../target/
$ DESTDIR=../target/ make install
</pre>

At last, configure your cron service or start our **vnstat-update.sh** or use the just built **vnstatd** service. Please get more help from the **INSTALL** file in the root directory of vnStat&#8217;s source code.

## Install vnStatSVG for different systems

In theory, vnStatSVG is available for any Linux platforms which have installed a CGI supported web server, but we have only tested it on Ubuntu and a Busybox based embedded system, so, we will only discuss its installation on them.

### Install vnStatSVG for Ubuntu

At first, Let&#8217;s install the web server: apache2,

<pre>$ sudo apt-get install apache2
</pre>

Note: we can also use another lightweight http server: Nginx, but must install extra CGI support: fcgiwrap, please get help [here][4] or read our article: [Add CGI support for Nginx][5].

Then, Let&#8217;s clone the latest version from its git repository:

<pre>$ git clone https://github.com/tinyclub/vnstatsvg.git
$ cd vnstatsvg
</pre>

And then, configure and install it:

<pre>$ ./configure
$ make
$ sudo -s
$ make install
</pre>

By default, files under **src/admin** will be installed to the web root: **/var/www**, and files under **src/cgi-bin** will be installed to the cgi-bin root **/usr/lib/cgi-bin**. The last section will show which files should be installed. To customize the installation targets, please get help below:

<pre>$ ./configure -h
 Usage:
      $ ./configure -c /path/to/cgi-bin
                    -w /path/to/web-root
                    -d a directory in web-root
                    -m [c|p|shell]
                    -h get help
  -c indicates the cgi-bin directory
  -w indicates the web root directory
  -d indicates a directory in web root to store the index page of vnstatsvg
  -m indicates the method to dump XML data, there are three choices, one is
     using vnStatXML(c), another is using (shell) script with the --dumpdb option
     provided by vnStat. the third is using the --dumpxml option after patch vnStat
     with vnStatXML.
  -h print this information
</pre>

To cross compile it with static linking:

<pre>$ ./configure
$ make CFLAGS=' -static ' CROSS_COMPILE=arm-linux-gnueabi-
$ make install
</pre>

Now, you should be able to access vnstatsvg web service, open http://localhost in your chromium or firefox browser. It will only list the default demo host and interface we have added:

<img alt="" src="/wp-content/uploads/file/vnstatsvg-default-homepage.png" style="width: 580px; height: 486px;" />

To monitor your own host and interface, you can modify **/var/www/sidebar.xml**, for example, monitor **eth0** of **localhost**:

<pre>$ cat /var/www/sidebar.xml
<?xml version='1.0' encoding='UTF-8' standalone='no' ?>
&lt;sidebar id="sidebar">
&lt;iface>
    &lt;name>eth0&lt;/name>
    &lt;host>localhost&lt;/host>
&lt;/iface>
&lt;/sidebar>
</pre>

If have another host and another interface eth1, you can add it as below:

<pre>$ cat /var/www/sidebar.xml
<?xml version='1.0' encoding='UTF-8' standalone='no' ?>
&lt;sidebar id="sidebar">
&lt;iface>
    &lt;name>eth0&lt;/name>
    &lt;host>localhost&lt;/host>
&lt;/iface>
&lt;iface>
    &lt;name>eth1&lt;/name>
    &lt;host>example.com&lt;/host>
&lt;/iface>
&lt;/sidebar>
</pre>

To monitor the **example.com** host together in &#8216;one&#8217; monitor window, you may need to install a web server there and install the **src/cgi-bin** files. No need to install **src/admin** files for vnStatSVG allows to share other files except the XML formatted network traffic data and vnStatSVG can grab the XML data from the other hosts smartly and transparently with a proxy mechanism. Now, we get such web output, just like the first demo picture we have seen above:

<img alt="" src="/wp-content/uploads/file/vnstatsvg-multi-hosts.png" style="width: 580px; height: 486px;" />

Currently, only &#8216;eth0&#8242; and &#8216;eth1&#8242; network interfaces are allowed to be monitored, to monitor other interfaces, please modify **/usr/lib/cgi-bin/vnstat.sh** yourselves. In the coming 2.0 release, I plan to provide a better solution to configure the network interafces.

To display a detailed information of your host, use the **description** attribute the **iface** node in **/var/www/sidebar.xml**, see the examples in **src/admin/sidebar.xml**. Please get more information about installation from the **INSTALL** document.

### Install vnStatSVG for a Cluster

To use vnStat for a Linux cluster and not install web server in all of the compute nodes in the cluster, you can write a daemon to sync XML data to local **/var/lib/vnstat** directory periodically and store the data with the name like **cluster\_node\_name-iface_name**, for example, **example.com-eth0**, then, you can configure the the **sidebar.xml** as below:

<pre>$ cat /var/www/sidebar.xml
<?xml version='1.0' encoding='UTF-8' standalone='no' ?>
&lt;sidebar id="sidebar">
&lt;iface>
    &lt;name>eth0&lt;/name>
    &lt;host>localhost&lt;/host>
&lt;/iface>
&lt;iface>
    &lt;name>example.com-eth0&lt;/name>
    &lt;host>localhost&lt;/host>
    &lt;description>example.com&lt;/description>
&lt;/iface>
&lt;/sidebar>
</pre>

To sync data from remote computer nodes to the web service node, we can use NFS service, SSH service, FTP service and the others, we will not demonstrate how for there are lots of tutorials in the internet.  
To sync data &#8216;real time&#8217;, the virtual **file** protocol should give a help. with this protocol, you can specify your own **dump_tool**, that means, you can write your own shell script to sync data and dump the XML data out with the help of our **/usr/lib/cgi-bin/vnstat.sh**. see a simple example:

<pre>$ cat /var/www/sidebar.xml
<?xml version='1.0' encoding='UTF-8' standalone='no' ?>
&lt;sidebar id="sidebar">
&lt;iface>
    &lt;name>eth0&lt;/name>
    &lt;host>localhost&lt;/host>
&lt;protocol>file&lt;/protocol>
    &lt;dump_tool>/usr/lib/cgi-bin/vnstat.sh&lt;/dump_tool>
    &lt;description>Local Host&lt;/description>
&lt;/iface>
&lt;/sidebar>
</pre>

### Install vnStatSVG for a Busybox based embedded system

The only difference here may be, we may need cross compiling here and need to do some manual configure for the lightweight web server of **Busybox**: **httpd**.

We have just discussed the cross compiling of vnStat and vnStatSVG above, will not rediscuss them. To continue the left parts, please install vnStat and the update script: **vnstat-update.sh** or the **vnstatd** daemon built with vnstat yourselves to get vnStat database.

To let httpd transfer the XML, XSL and XHtml files with right MIME types, the following lines must be added to the configure file of httpd, for example, **/etc/httpd.conf**:

<pre>.xml:text/xml
.xhtml:text/xml
.xsl:text/xml
</pre>

Since embedded system may not use the standard **web root**, **web port** and **cgi-bin** directory, Let&#8217;s assume the web root is **/data/www**, the default cgi-bin directory of httpd will be **/data/www/cgi-bin** and assume the port is **8080**. Now, Let&#8217;s start the httpd service on Busybox based embedded system:

<pre>$ httpd -h /data/www/ -p 8080 -c /etc/httpd.conf
</pre>

To let our vnStatSVG work, we must install the files under **src/admin** to **/data/www** and the files under **src/cgi-bin** to **/data/www/cgi-bin**. Let&#8217;s refer to Makefile, the files of **ADMIN_FILES** under **src/admin** must be installed to **/data/www**, the files of **CGI_FILES** under **src/cgi-bin** must be installed to **/data/www/cgi-bin**.

<pre>$ grep -e '^ADMIN_FILES|^CGI_FILES' -ur Makefile
ADMIN_FILES=index.xhtml index.xsl sidebar.xml sidebar.xsl vnstat.xsl vnstat.js vnstat.css menu.xml menu.xsl
CGI_FILES=httpclient proxy.sh vnstat.sh
</pre>

Note, there is no real **vnstat.sh** under **src/cgi-bin**, but there are three similar files named with suffix, **-c**, **-p** and **-shell**, by default we use **-shell**. If not want to install vnStat separately, please use the **-p** method to compile vnStat and vnStatSVG together, Let&#8217;s assume **../target** is our embedded system&#8217;s root:

<pre>$ mkdir -p ../target/data/www/cgi-bin/; mkdir -p ../target/usr/bin
$ ./configure -c ../target/data/www/cgi-bin/ -w ../target/data/www/ -b ../target/usr/bin -m p
$ make CFLAGS=' -static ' CROSS_COMPILE=arm-linux-gnueabi-
$ make install CROSS_COMPILE=arm-linux-gnueabi-
</pre>

With the above steps, you should be able to configure **sidebar.xml** and after that, package your Busybox file system and start it on your target board. Then, after network configuration, vnStatSVG should work.

## Conclusion

As we can see from the above exercises, with the backend vnStat, vnStatSVG is really powerful to monitor network traffic for different systems, from a single Linux host, to a Linux cluster and even for a simple Busybox based embedded system.

And it is very friendly to the resource limited embedded system which have no enough disk and memory to install apache2 with PHP modules and which have only a limited bandwidth of network connection.

Besides, vnStatSVG is configurable, scalable and easy to use.



 [1]: /vnstatsvg-demo/
 [2]: https://tinylab.org
 [3]: http://ieeexplore.ieee.org/xpl/mostRecentIssue.jsp?punumber=4562771
 [4]: http://wiki.nginx.org/Fcgiwrap
 [5]: /add-cgi-support-for-nginx/
