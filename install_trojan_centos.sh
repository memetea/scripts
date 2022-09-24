#!/bin/bash
install_deps() {
        yum install epel-release -y
        yum install wget certbot nginx -y
}

install_tapnet_from_source() {
        install_deps
yum install git tmux net-tools boost cmake make automake gcc gcc-c++ kernel-devel boost-devel openssl-devel mysql-devel  -y

        #compile and install tapnet
        git clone https://github.com/tapnet-gfw/tapnet.git
        cd tapnet/
        mkdir build
        cd build/
        cmake ..
        make
        ctest
        sudo make install
}

install_tapnet_from_precompiled() {
	if [ -f /usr/local/bin/tapnet ] ; then
		echo 'tapnet已经安装， 请选择>'
		select choice in 覆盖 退出 
		do 
			if [[ "$choice" = "覆盖" ]]; then
				uninstall_tapnet
				break;
			elif [[ "$choice" = "退出" ]]; then
			    exit;
			fi;
		done
	fi;
	install_deps
	[ ! -f trojan-1.16.0-linux-amd64.tar.xz ] && wget https://github.com/trojan-gfw/trojan/releases/download/v1.16.0/trojan-1.16.0-linux-amd64.tar.xz && tar xvf trojan-1.16.0-linux-amd64.tar.xz
	[ ! -d /usr/local/etc/tapnet ] && mkdir /usr/local/etc/tapnet
	cp trojan/config.json /usr/local/etc/tapnet/
	cp trojan/trojan /usr/local/bin/tapnet
	rm -rf trojan && rm trojan-1.16.0-linux-amd64.tar.xz
	cat  > /lib/systemd/system/tapnet.service << EOF
[Unit]
Description=tapnet
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service

[Service]
Type=simple
StandardError=journal
User=nobody
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/tapnet /usr/local/etc/tapnet/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
}

uninstall_tapnet() {
	[ -f /lib/systemd/system/tapnet.service ] && sudo systemctl stop tapnet && rm /lib/systemd/system/tapnet.service 
	[ -f /usr/local/etc/tapnet ] && rm -rf /usr/local/etc/tapnet
	[ -f /usr/local/bin/tapnet ] && rm /usr/local/bin/tapnet
}

echo '请输入tapnet安装方式:'
select choice in '从源码编译' '使用预编译的程序' '卸载tapnet' quit
do case "$choice" in
'从源码安装')
    install_tapnet_from_source;
    break;
    ;;
'使用预编译的程序')
    install_tapnet_from_precompiled;
    break;
    ;;
'卸载tapnet')
   uninstall_tapnet;
   echo 'tapnet uninstalled';
   exit;
   break;
   ;; 
quit)
    exit;
    ;;
*)
    echo 'error input';
esac
done

 #delete line contains password2
 sed -i '/password2/d' /usr/local/etc/tapnet/config.json

 #set tapnet password
 read -p 'input tapnet password(ramdom password will be generated if left empty):' pwd
 #read pwd
 if [ ! $pwd ]; then
    pwd=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c9`
 fi;

 sed -i "s/\"password1\",/\"${pwd}\"/" /usr/local/etc/tapnet/config.json

 sudo systemctl stop nginx
 #apply certificate
 for i in 1 2 3
 do
     read -p "input domain:" domain
     if [ ! -z "$domain" ] 
     then
 	    break
     fi
 done;
 [ -z "$domain" ] && echo "domain is empty" && exit 1

 sed -i "s|/path/to/certificate.crt|/usr/local/etc/tapnet/fullchain.pem|" /usr/local/etc/tapnet/config.json
 sed -i "s|/path/to/private.key|/usr/local/etc/tapnet/privkey.pem|" /usr/local/etc/tapnet/config.json


 sudo certbot certonly --standalone -d $domain
 sudo cat /etc/letsencrypt/live/$domain/fullchain.pem > /usr/local/etc/tapnet/fullchain.pem
sudo cat /etc/letsencrypt/live/$domain/privkey.pem > /usr/local/etc/tapnet/privkey.pem
 cat > /usr/local/etc/tapnet/renew-cert.sh <<EOF
 #!/bin/bash
 systemctl stop nginx
 certbot renew
 cp /etc/letsencrypt/live/${domain}/fullchain.pem  /usr/local/etc/tapnet/fullchain.crt
 cat /etc/letsencrypt/live/${domain}/privkey.pem  /usr/local/etc/tapnet/private.key
 systemctl start nginx
EOF
chmod u+x /usr/local/etc/tapnet/renew-cert.sh

if ! grep -q "0 0 1 */2 0 /usr/local/etc/tapnet/renew-cert.sh" /var/spool/cron/root; then
 sudo echo "0 0 1 */2 0 /usr/local/etc/tapnet/renew-cert.sh" >> /var/spool/cron/root
fi;


 #开启tcp拥塞控制bbr
 sudo echo net.core.default_qdisc=fq >> /etc/sysctl.conf
 sudo echo net.ipv4.tcp_congestion_control=bbr >> /etc/sysctl.conf
 sudo sysctl -p

 sudo systemctl start nginx
 sudo systemctl restart tapnet
