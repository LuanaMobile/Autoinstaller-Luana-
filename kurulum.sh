#!/bin/bash

# Güncellemeleri yap
apt update

# Gerekli bağımlılıkları kur
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg sudo php7.3 php7.3-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} nginx tar unzip git

# Composer'ı kur
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# NodeJS'i kur
curl -sL https://deb.nodesource.com/setup_14.x | bash -
apt update
apt -y install nodejs make gcc g++

# Docker'ı kur
curl -sSL https://get.docker.com/ | CHANNEL=stable bash
usermod -aG docker www-data
systemctl enable --now docker
/etc/init.d/docker restart

# Veritabanını kur
apt -y install mariadb-server

# MariaDB yönetim aracına giriş yap ve kullanıcı oluştur
mysql -u root -p <<EOF
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'bana1kolaal';
CREATE DATABASE panel;
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# Panel dizinini oluştur
chown -R www-data:www-data /var/www
su -l www-data -s /bin/bash <<EOF
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

# Panel dosyalarını indir ve aç
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/download/v1.0.3/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# Ortam ayarlarını yapılandır
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force

# Yapılandırmayı başlat
php artisan p:environment:setup

# Veritabanı ayarlarını yapılandır
php artisan p:environment:database

# Veritabanı göçünü çalıştır
php artisan migrate --seed

# Kullanıcı oluştur
php artisan p:user:make --admin yes --email your_email@example.com --username JDoe --first John --last Doe --password YourPassword
EOF

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
        fastcgi_param PHP_VALUE \"upload_max_filesize = 100M \n post_max_size=100M\";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY \"\";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}" > /etc/nginx/sites-available/pterodactyl.conf

# Web sunucusunu etkinleştir
rm /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
/etc/init.d/nginx restart
