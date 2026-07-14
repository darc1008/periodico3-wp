FROM wordpress:6.7-php8.3-apache

# Install mariadb-server, supervisor, wp-cli, jq
RUN apt-get update && apt-get install -y --no-install-recommends \
    mariadb-server \
    supervisor \
    curl \
    ca-certificates \
    jq \
    && rm -rf /var/lib/apt/lists/* \
    && curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# PHP limits
RUN echo 'memory_limit = 256M' > /usr/local/etc/php/conf.d/zz-wp-limits.ini \
    && echo 'upload_max_filesize = 64M' >> /usr/local/etc/php/conf.d/zz-wp-limits.ini \
    && echo 'post_max_size = 64M' >> /usr/local/etc/php/conf.d/zz-wp-limits.ini \
    && echo 'max_execution_time = 120' >> /usr/local/etc/php/conf.d/zz-wp-limits.ini

# MariaDB runtime config
RUN mkdir -p /var/run/mysqld /var/lib/mysql \
    && chown -R mysql:mysql /var/run/mysqld /var/lib/mysql
COPY mariadb.cnf /etc/mysql/conf.d/periodico3.cnf

# Seed scripts and sample articles
COPY seed/seed.sh /usr/local/bin/seed.sh
COPY seed/assign_menu.php /seed/assign_menu.php
COPY seed/articles /seed/articles
COPY seed/custom.css /seed/custom.css
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/seed.sh /usr/local/bin/entrypoint.sh

ENV APACHE_RUN_USER=www-data
ENV APACHE_RUN_GROUP=www-data
ENV MARIADB_DATABASE=periodico3
ENV MARIADB_USER=periodico3
ENV MARIADB_PASSWORD=P3r10d1c03_M4r1adb_2026!
ENV MARIADB_ROOT_PASSWORD=P3r10d1c03_R00t_2026!

EXPOSE 80
CMD ["/usr/local/bin/entrypoint.sh"]
