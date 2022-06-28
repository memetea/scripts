#!/bin/bash

install_trojan_from_source() {
	sudo apt update
	sudo apt install git tmux net-tools libboost-all-dev cmake make automake build-essential linux-libc-dev  openssl  libssl-dev libmysqlclient-dev nginx
	sudo apt install certbot 

	#compile and install trojan
	git clone https://github.com/trojan-gfw/trojan.git
	cd trojan/
	mkdir build
	cd build/
	cmake ..
	make
	ctest
	sudo make install
}

install_trojan_from_precompiled() {
	if [ -f /usr/local/bin/trojan ] ; then
		echo 'trojan已经安装， 请选择>'
		select choice in 覆盖 退出 
		do 
			if [[ "$choice" = "覆盖" ]]; then
				uninstall_trojan
				break;
			elif [[ "$choice" = "退出" ]]; then
			    exit;
			fi;
		done
	fi;
	sudo apt install wget nginx
	[ ! -f trojan-1.16.0-linux-amd64.tar.xz ] && wget https://github.com/trojan-gfw/trojan/releases/download/v1.16.0/trojan-1.16.0-linux-amd64.tar.xz && tar xvf trojan-1.16.0-linux-amd64.tar.xz
	[ ! -d /usr/local/etc/trojan ] && mkdir /usr/local/etc/trojan
	cp trojan/config.json /usr/local/etc/trojan/
	cp trojan/trojan /usr/local/bin/
	rm -rf trojan && rm trojan-1.16.0-linux-amd64.tar.xz
	cat  > /lib/systemd/system/trojan.service << EOF
[Unit]
Description=trojan
Documentation=man:trojan(1) https://trojan-gfw.github.io/trojan/config https://trojan-gfw.github.io/trojan/
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service

[Service]
Type=simple
StandardError=journal
User=nobody
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/trojan /usr/local/etc/trojan/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
}

uninstall_trojan() {
	[ -f /lib/systemd/system/trojan.service ] && sudo systemctl stop trojan && rm /lib/systemd/system/trojan.service 
	[ -f /usr/local/etc/trojan ] && rm -rf /usr/local/etc/trojan
	[ -f /usr/local/bin/trojan ] && rm /usr/local/bin/trojan
}

echo '请输入trojan安装方式:'
select choice in '从源码编译' '使用预编译的程序' '卸载trojan' quit
do case "$choice" in
'从源码安装')
    install_trojan_from_source;
    break;
    ;;
'使用预编译的程序')
    install_trojan_from_precompiled;
    break;
    ;;
'卸载trojan')
   uninstall_trojan;
   echo 'trojan uninstalled';
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
 sed -i '/password2/d' /usr/local/etc/trojan/config.json

 #set trojan password
 read -p 'input trojan password(ramdom password will be generated if left empty):' pwd
 #read pwd
 if [ ! $pwd ]; then
    pwd=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c9`
 fi;

 sed -i "s/\"password1\",/\"${pwd}\"/" /usr/local/etc/trojan/config.json

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

 sed -i "s|/path/to/certificate.crt|/usr/local/etc/trojan/fullchain.pem|" /usr/local/etc/trojan/config.json
 sed -i "s|/path/to/private.key|/usr/local/etc/trojan/privkey.pem|" /usr/local/etc/trojan/config.json


 sudo certbot certonly --standalone -d $domain
 cat > /usr/local/etc/trojan/renew-cert.sh <<EOF
 #!/bin/bash
 certbot renew
 cp /etc/letsencrypt/live/${domain}/fullchain.pem  /usr/local/etc/trojan/certificate.crt
 cat /etc/letsencrypt/live/${domain}/privkey.pem  /usr/local/etc/trojan/private.key
EOF
chmod u+x /usr/local/etc/trojan/renew-cert.sh

if ! grep -q "0 0 1 */2 0 /usr/local/etc/trojan/renew-cert.sh" /var/spool/cron/root; then
 sudo echo "0 0 1 */2 0 /usr/local/etc/trojan/renew-cert.sh" >> /var/spool/cron/root
fi;


 #开启tcp拥塞控制bbr
 sudo echo net.core.default_qdisc=fq >> /etc/sysctl.conf
 sudo echo net.ipv4.tcp_congestion_control=bbr >> /etc/sysctl.conf
 sudo sysctl -p

 sudo systemctl start nginx
 sudo systemctl restart trojan
