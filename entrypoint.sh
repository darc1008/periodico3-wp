#!/bin/bash
# periodico3 - Entrypoint: inicializa MariaDB local, ejecuta seed, arranca Apache
set -e

echo "[entrypoint] Iniciando periodico3..."

# Inicializar MariaDB si la base está vacía
if [ ! -d /var/lib/mysql/mysql ]; then
  echo "[entrypoint] Inicializando MariaDB..."
  mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi

# Si /var/www/html está vacío (volumen nuevo en primer arranque), copiar el WP de la imagen
if [ ! -f /var/www/html/wp-load.php ]; then
  echo "[entrypoint] Copiando WordPress core al volumen..."
  cp -a /usr/src/wordpress/. /var/www/html/
  chown -R www-data:www-data /var/www/html
fi

# Asegurar permisos
chown -R mysql:mysql /var/lib/mysql /var/run/mysqld 2>/dev/null || true

# Iniciar MariaDB
echo "[entrypoint] Iniciando MariaDB..."
/usr/bin/mysqld_safe --datadir=/var/lib/mysql --user=mysql > /var/log/mariadb-startup.log 2>&1 &
sleep 5

# Esperar a MariaDB
for i in $(seq 1 20); do
  if mysqladmin ping --silent 2>/dev/null; then
    echo "[entrypoint] MariaDB OK"
    break
  fi
  sleep 1
done

# Crear DB y usuario si no existen
mysql -uroot <<EOSQL
CREATE DATABASE IF NOT EXISTS \`${MARIADB_DATABASE:-periodico3}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MARIADB_USER:-periodico3}'@'localhost' IDENTIFIED BY '${MARIADB_PASSWORD}';
CREATE USER IF NOT EXISTS '${MARIADB_USER:-periodico3}'@'127.0.0.1' IDENTIFIED BY '${MARIADB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MARIADB_DATABASE:-periodico3}\`.* TO '${MARIADB_USER:-periodico3}'@'localhost';
GRANT ALL PRIVILEGES ON \`${MARIADB_DATABASE:-periodico3}\`.* TO '${MARIADB_USER:-periodico3}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOSQL
echo "[entrypoint] MariaDB ready"

# Generar wp-config.php
cd /var/www/html
if [ ! -f wp-config.php ]; then
  echo "[entrypoint] Creando wp-config.php..."
  wp config create \
    --dbhost=127.0.0.1 \
    --dbname="${MARIADB_DATABASE:-periodico3}" \
    --dbuser="${MARIADB_USER:-periodico3}" \
    --dbpass="${MARIADB_PASSWORD}" \
    --dbcharset=utf8mb4 \
    --dbcollate=utf8mb4_unicode_ci \
    --locale=es_ES \
    --allow-root
fi

# Forzar que .htaccess tenga las reglas de permalinks para que
# Apache pueda servir las URLs amigables y no haya redirect loop
echo "[entrypoint] Verificando .htaccess..."
HTACCESS=/var/www/html/.htaccess
NEEDS_HTACCESS=0
if [ ! -f "$HTACCESS" ] || ! grep -q "BEGIN WordPress" "$HTACCESS"; then
  NEEDS_HTACCESS=1
fi
if [ "$NEEDS_HTACCESS" = "1" ]; then
  echo "[entrypoint] Generando .htaccess con reglas de WP..."
  cat > "$HTACCESS" <<'HTEOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTEOF
  chown www-data:www-data "$HTACCESS"
  chmod 644 "$HTACCESS"
fi

echo "[entrypoint] Ejecutando seed..."
/usr/local/bin/seed.sh 2>&1 | tee /tmp/seed.log
echo "[seed] done"

echo "[entrypoint] Iniciando Apache..."
exec apache2-foreground
