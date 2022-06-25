#!/bin/bash

#本脚本可以在centos上安装trojan，注意必须有域名指向本机
sudo apt install git tmux net-tools libboost-all-dev cmake make automake build-essential linux-libc-dev  openssl  libssl-dev libmysqlclient-dev nginx
sudo apt install certbot -y

#compile and install trojan
git clone https://github.com/trojan-gfw/trojan.git
cd trojan/
mkdir build
cd build/
cmake ..
make
ctest
sudo make install

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

sudo systemctl start nginx
sudo ystemctl restart trojan
