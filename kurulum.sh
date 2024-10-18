#!/bin/bash

# Güncellemeleri yap
apt update && apt upgrade -y

# Gerekli bağımlılıkları kur
apt install -y software-properties-common curl wget unzip git

# PHP ve uzantılarını kur
apt install -y php php-cli php-fpm php-mysql php-zip php-curl php-xml php-mbstring php-tokenizer php-bcmath php-json php-gd

# MariaDB (MySQL) kur
apt install -y mariadb-server

# MariaDB servisini başlat ve etkinleştir
systemctl start mariadb
systemctl enable mariadb

# MariaDB güvenlik ayarlarını yap
mysql_secure_installation <<EOF

y
bana1kolaal
bana1kolaal
y
y
y
y
EOF

# MariaDB'ye giriş yap ve kullanıcı oluştur
mysql -u root -pbana1kolaal <<EOF
CREATE DATABASE pterodactyl;
CREATE USER 'pterodactyl'@'localhost' IDENTIFIED BY 'bana1kolaal';
GRANT ALL PRIVILEGES ON pterodactyl.* TO 'pterodactyl'@'localhost';
FLUSH PRIVILEGES;
EOF

# Gerekli PHP uzantılarını kontrol et
php -m | grep -E 'zip|curl|xml|mbstring|tokenizer|bcmath|json|gd'

# Nginx kurulumunu yap
apt install -y nginx

# Nginx servisini başlat ve etkinleştir
systemctl start nginx
systemctl enable nginx

# Pterodactyl Panel dizinini oluştur
mkdir -p /var/www/pterodactyl

# Pterodactyl Panel dosyalarını indir
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/download/v1.0.3/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# Ortam ayarlarını yapılandır
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force

# Yapılandırmayı başlat
php artisan p:environment:setup <<EOF
your_email@example.com
http://your-server-ip
Europe/Istanbul
file
database
database
yes
EOF

# Veritabanı ayarlarını yapılandır
php artisan p:environment:database <<EOF
127.0.0.1
3306
pterodactyl
pterodactyl
bana1kolaal
EOF

# Veritabanı göçünü çalıştır
php artisan migrate --seed

# Kullanıcı oluştur
php artisan p:user:make --admin yes --email your_email@example.com --username JDoe --first John --last Doe --password YourPassword

# Dosya izinlerini ayarla
chown -R www-data:www-data /var/www/pterodactyl/

# Cron işini ekle
echo "* * * * * www-data php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" >> /etc/crontab

# Servisi oluştur
echo "[Unit]
Description=Pterodactyl Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/pteroq.service

# Servisi başlat
systemctl enable --now pteroq.service

# Nginx yapılandırması
echo "server {
    listen 80 default_server;
    server_name _;

    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php7.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}" > /etc/nginx/sites-available/pterodactyl.conf

# Web sunucusunu etkinleştir
rm /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
systemctl restart nginx

# Pterodactyl Panel için PHP-FPM ayarlarını yap
sed -i 's/user = www-data/user = www-data/' /etc/php/7.3/fpm/pool.d/www.conf
sed -i 's/group = www-data/group = www-data/' /etc/php/7.3/fpm/pool.d/www.conf
systemctl restart php7.3-fpm

echo "Kurulum tamamlandı. Pterodactyl Panel'e erişmek için http://your-server-ip adresini ziyaret edin."
