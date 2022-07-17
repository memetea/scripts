#!/bin/bash
#本脚本可以在centos上安装trojan，注意必须有域名指向本机

install_deps() {
	yum install epel-release -y
	yum install wget certbot nginx -y
}

install_trojan_from_source() {
    install_deps
    yum install git tmux net-tools boost cmake make automake gcc gcc-c++ kernel-devel boost-devel openssl-devel mysql-devel  -y

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
	install_deps
	wget https://github.com/trojan-gfw/trojan/releases/download/v1.16.0/trojan-1.16.0-linux-amd64.tar.xz
	tar xvf trojan-1.16.0-linux-amd64.tar.xz
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

#apply certificate
systemctl stop nginx
[ ! -d "/usr/local/trojan-cert/" ] && mkdir /usr/local/trojan-cert
sed -i 's|/path/to/|/usr/local/trojan-cert/|' /usr/local/etc/trojan/config.json
for i in 1 2 3
do
    read -p "input domain:" domain
    if [ ! -z "$domain" ] 
    then
	    break
    fi
done;
[ -z "$domain" ] && echo "domain is empty" && exit 1

cat > /usr/local/bin/renew-cert.sh <<EOF
#!/bin/bash
certbot renew
cat /etc/letsencrypt/live/${domain}/fullchain.pem > /usr/local/trojan-cert/certificate.crt
cat /etc/letsencrypt/live/${domain}/privkey.pem > /usr/local/trojan-cert/private.key
EOF
chmod u+x /usr/local/bin/renew-cert.sh

sudo certbot certonly --standalone -d $domain
sudo cat /etc/letsencrypt/live/$domain/fullchain.pem > /usr/local/trojan-cert/certificate.crt
sudo cat /etc/letsencrypt/live/$domain/privkey.pem > /usr/local/trojan-cert/private.key
sudo echo "0 0 1 */2 0 /bin/sh /usr/local/bin/renew_cert.sh" >> /var/spool/cron/root


#开启tcp拥塞控制bbr
sudo echo net.core.default_qdisc=fq >> /etc/sysctl.conf
sudo echo net.ipv4.tcp_congestion_control=bbr >> /etc/sysctl.conf
sudo sysctl -p

systemctl daemon-reload
systemctl start nginx
systemctl restart trojan
