#!/bin/bash
# periodico3 - One-shot WordPress bootstrap (Editorial theme, magazine style)
set -e

DB_HOST="${WORDPRESS_DB_HOST:-127.0.0.1}"
DB_USER="${WORDPRESS_DB_USER:-periodico3}"
DB_PASS="${WORDPRESS_DB_PASSWORD:-P3r10d1c03_M4r1adb_2026!}"
DB_NAME="${WORDPRESS_DB_NAME:-periodico3}"

export WORDPRESS_DB_HOST="$DB_HOST"
export WORDPRESS_DB_USER="$DB_USER"
export WORDPRESS_DB_PASSWORD="$DB_PASS"
export WORDPRESS_DB_NAME="$DB_NAME"

echo "==> WordPress DB target: $DB_USER@$DB_HOST/$DB_NAME"

cd /var/www/html

# Wait for DB
for i in {1..30}; do
  if wp --path=/var/www/html db check --allow-root 2>/dev/null; then
    echo "  db OK"
    break
  fi
  echo "  waiting for db ($i)..."
  sleep 2
done

# Install WP if not installed
if ! wp --path=/var/www/html core is-installed --allow-root 2>/dev/null; then
  echo "==> Installing WordPress core"
  wp --path=/var/www/html core install \
    --url="${WP_SITEURL:-https://periodico3.statusloop.app}" \
    --title="${WP_TITLE:-Periodico2}" \
    --admin_user="${WP_ADMIN_USER:-admin}" \
    --admin_password="${WP_ADMIN_PASSWORD}" \
    --admin_email="${WP_ADMIN_EMAIL:-admin@periodico3.statusloop.app}" \
    --skip-email --allow-root
else
  echo "==> WordPress ya instalado, saltando install"
fi

echo "==> Site settings"
wp --path=/var/www/html option update blogdescription "${WP_TAGLINE:-El periódico digital — actualidad, cultura, política y opinión}" --allow-root
wp --path=/var/www/html option update timezone_string "America/Santo_Domingo" --allow-root
wp --path=/var/www/html option update date_format "d/m/Y" --allow-root
wp --path=/var/www/html option update time_format "H:i" --allow-root
wp --path=/var/www/html option update start_of_week "1" --allow-root
wp --path=/var/www/html option update posts_per_page "10" --allow-root
wp --path=/var/www/html option update default_comment_status "open" --allow-root

echo "==> Permalinks"
wp --path=/var/www/html rewrite structure "/%postname%/" --allow-root
wp --path=/var/www/html rewrite flush --hard --allow-root

echo "==> Editorial theme (magazine style by Mystery Themes)"
# Editorial es un theme magazine gratuito muy completo de WP.org:
# - Featured slider (bxslider)
# - News ticker
# - Multi-column grid layouts por categoría
# - Page builder via widgets
# - Top header con fecha + social icons
if ! wp --path=/var/www/html theme is-installed editorial --allow-root 2>/dev/null; then
  echo "  Instalando Editorial..."
  wp --path=/var/www/html theme install editorial --allow-root 2>&1 | tail -3
fi
wp --path=/var/www/html theme activate editorial --allow-root 2>&1 | tail -1

echo "==> Editorial theme options (customizer)"
# Top header
wp --path=/var/www/html option update editorial_top_header_option "enable" --allow-root
wp --path=/var/www/html option update editorial_social_icons_option "enable" --allow-root
# News ticker
wp --path=/var/www/html option update editorial_ticker_option "enable" --allow-root
wp --path=/var/www/html option update editorial_ticker_caption "Última Hora" --allow-root
# Single post layout
wp --path=/var/www/html option update editorial_single_page_layout "right_sidebar" --allow-root
# Copyright
wp --path=/var/www/html option update editorial_copyright_text "© 2026 Periodico2 — Todos los derechos reservados" --allow-root
# Color primario del theme (lo deja en rojo periodístico por defecto)
# Editorial no expone color primario directo en options; lo manejamos via CSS

echo "==> Custom CSS (Editorial - ajustes Public Opinion style)"
# Editorial ya es un theme magazine-style. Solo ajustamos paleta y tipografía
# para acercarlo al look de Public Opinion de CSSIgniter.
wp --path=/var/www/html option update periodico3_custom_css "$(cat /seed/custom.css)" --allow-root

# mu-plugin para inyectar CSS
mkdir -p /var/www/html/wp-content/mu-plugins
cat > /var/www/html/wp-content/mu-plugins/periodico3-custom-css.php <<'MUPLUGIN'
<?php
/**
 * Plugin Name: periodico3 custom CSS
 * Description: Inyecta CSS en wp_head (estilo Public Opinion sobre Editorial)
 */
add_action('wp_head', function() {
    $css = get_option('periodico3_custom_css');
    if ($css) {
        echo '<style id="periodico3-custom-css">' . "\n" . $css . "\n</style>\n";
    }
}, 99);

// FIX: deshabilitar redirect_canonical para evitar loop 301 en la home
// cuando show_on_front=page y page_on_front es una página Magazine.
// WordPress 6.7 + Magazine template genera redirect_canonical() que
// produce 301 → 301 → ... en la URL raíz. Este filter corta ese loop.
add_filter('redirect_canonical', function($redirect_url, $requested_url) {
    // Si la canonical es la misma URL que se pidió, no redirigir
    if (rtrim($redirect_url, '/') === rtrim($requested_url, '/')) {
        return false;
    }
    return $redirect_url;
}, 10, 2);

// Asegurar que la home apunte a la página Magazine
add_action('init', function() {
    $front = get_option('show_on_front');
    if ($front !== 'page') {
        update_option('show_on_front', 'page');
    }
});
MUPLUGIN

echo "==> Essential plugins"
for PLUGIN in akismet contact-form-7 classic-editor seo-by-rank-math; do
  if ! wp --path=/var/www/html plugin is-installed "$PLUGIN" --allow-root 2>/dev/null; then
    wp --path=/var/www/html plugin install "$PLUGIN" --allow-root 2>&1 | tail -2
  fi
  wp --path=/var/www/html plugin activate "$PLUGIN" --allow-root 2>&1 | tail -1
done
wp --path=/var/www/html option update classic-editor-replace "classic" --allow-root
wp --path=/var/www/html option update classic-editor-allow-users "allow" --allow-root

echo "==> Categories"
declare -A SECTIONS=(
  [politica]="Politica"
  [economia]="Economia"
  [mundo]="Mundo"
  [tecnologia]="Tecnologia"
  [deportes]="Deportes"
  [cultura]="Cultura"
  [opinion]="Opinion"
  [estilo]="Estilo de Vida"
)
for SLUG in "${!SECTIONS[@]}"; do
  wp --path=/var/www/html term create category "${SECTIONS[$SLUG]}" --slug="$SLUG" --description="Sección de ${SECTIONS[$SLUG]}" --allow-root 2>/dev/null || true
done

echo "==> Navigation menu"
if ! wp --path=/var/www/html menu list --allow-root 2>/dev/null | grep -q "Menú Principal"; then
  wp --path=/var/www/html menu create "Menú Principal" --allow-root 2>&1 | tail -1
fi
# Limpiar items previos
EXISTING_ITEMS=$(timeout 10 wp --path=/var/www/html menu item list "Menú Principal" --field=db_id --format=ids --allow-root 2>/dev/null | head -50)
if [ -n "$EXISTING_ITEMS" ]; then
  for ITEM_ID in $EXISTING_ITEMS; do
    [ -n "$ITEM_ID" ] && timeout 5 wp --path=/var/www/html menu item delete "$ITEM_ID" --allow-root 2>/dev/null
  done
fi
# Items
timeout 10 wp --path=/var/www/html menu item add-custom "Menú Principal" "Inicio" "/" --allow-root 2>&1 | tail -1
for SLUG in politica economia mundo tecnologia deportes cultura opinion estilo; do
  CAT_ID=$(wp --path=/var/www/html term list category --slug="$SLUG" --field=term_id --allow-root 2>/dev/null | head -1)
  if [ -n "$CAT_ID" ]; then
    LABEL=$(echo "${SECTIONS[$SLUG]}")
    timeout 10 wp --path=/var/www/html menu item add-custom \
      "Menú Principal" "$LABEL" "/category/$SLUG/" --allow-root 2>&1 | tail -1
  fi
done

# Top header menu (fecha + social icons los pone el theme automáticamente)
if ! wp --path=/var/www/html menu list --allow-root 2>/dev/null | grep -q "Menú Superior"; then
  wp --path=/var/www/html menu create "Menú Superior" --allow-root 2>&1 | tail -1
fi
EXISTING_TOP=$(timeout 10 wp --path=/var/www/html menu item list "Menú Superior" --field=db_id --format=ids --allow-root 2>/dev/null | head -20)
if [ -n "$EXISTING_TOP" ]; then
  for ITEM_ID in $EXISTING_TOP; do
    [ -n "$ITEM_ID" ] && timeout 5 wp --path=/var/www/html menu item delete "$ITEM_ID" --allow-root 2>/dev/null
  done
fi
timeout 10 wp --path=/var/www/html menu item add-custom "Menú Superior" "Acerca de" "/acerca-de/" --allow-root 2>&1 | tail -1
timeout 10 wp --path=/var/www/html menu item add-custom "Menú Superior" "Contacto" "/contacto/" --allow-root 2>&1 | tail -1

# Asignar menus via PHP (Editorial usa locations: primary, top-header, footer)
MENU_ID=$(wp --path=/var/www/html menu list --fields=term_id,name --allow-root 2>/dev/null | awk -F'|' '/Menú Principal/ {gsub(/ /,"",$1); print $1; exit}')
MENU_TOP_ID=$(wp --path=/var/www/html menu list --fields=term_id,name --allow-root 2>/dev/null | awk -F'|' '/Menú Superior/ {gsub(/ /,"",$1); print $1; exit}')
if [ -n "$MENU_ID" ] || [ -n "$MENU_TOP_ID" ]; then
  echo "==> Asignando menus via PHP (primary=$MENU_ID, top-header=$MENU_TOP_ID)"
  PRIMARY_MENU=$MENU_ID TOP_MENU=$MENU_TOP_ID wp --path=/var/www/html eval-file /seed/assign_menu.php --allow-root 2>&1 | tail -10
fi

# Borrar Sample Page y Hello World
SAMPLE_ID=$(wp --path=/var/www/html post list --post_type=page --name="sample-page" --field=ID --allow-root 2>/dev/null | head -1)
[ -n "$SAMPLE_ID" ] && wp --path=/var/www/html post delete "$SAMPLE_ID" --force --allow-root 2>&1 | tail -1
wp --path=/var/www/html post delete 1 --force --allow-root 2>/dev/null || true

# Crear página Magazine para el home
MAG_ID=$(wp --path=/var/www/html post list --post_type=page --name=inicio --field=ID --allow-root 2>/dev/null | head -1)
if [ -z "$MAG_ID" ]; then
  echo "==> Creando página 'Inicio' con template Magazine"
  MAG_ID=$(wp --path=/var/www/html post create \
    --post_type=page \
    --post_status=publish \
    --post_title="Inicio" \
    --post_name="inicio" \
    --post_content="" \
    --porcelain \
    --allow-root 2>/dev/null | head -1) || true
fi
# Borrar página Blog default
BLOG_ID=$(wp --path=/var/www/html post list --post_type=page --name=blog --field=ID --allow-root 2>/dev/null | head -1)
[ -n "$BLOG_ID" ] && [ "$BLOG_ID" != "$MAG_ID" ] && wp --path=/var/www/html post delete "$BLOG_ID" --force --allow-root 2>&1 | tail -1

# Asignar home = Magazine
wp --path=/var/www/html option update show_on_front "page" --allow-root
wp --path=/var/www/html option update page_on_front "$MAG_ID" --allow-root
wp --path=/var/www/html option update page_for_posts 0 --allow-root

echo "==> Magazine widgets (slider + grids + sidebar)"
MAG_WIDGETS_OUT=$(MAG_ID=$MAG_ID wp --path=/var/www/html eval-file /seed/magazine_widgets.php --allow-root 2>&1)
echo "$MAG_WIDGETS_OUT" | tail -10

# Frontmatter parser
parse_frontmatter() {
  local FILE="$1"
  local FIELD="$2"
  sed -n "/^${FIELD}:/p" "$FILE" | head -1 | sed "s/^${FIELD}:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//' | sed "s/'$//" | sed "s/'\$//"
}

parse_categories() {
  local FILE="$1"
  local VAL=$(parse_frontmatter "$FILE" categories)
  if [[ "$VAL" == \[* ]]; then
    echo "$VAL" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ',' | sed 's/,$//'
  elif [[ -n "$VAL" ]]; then
    echo "$VAL"
  else
    awk '/^categories:/{f=1; next} f && /^- /{sub(/^- /,""); gsub(/[[:space:]]/,""); print; f=0; next} f && /^[^ -]/{f=0}' "$FILE" | tr '\n' ',' | sed 's/,$//'
  fi
}

echo "==> Sample articles"
EXISTING=$(wp --path=/var/www/html post list --post_type=post --post_status=publish --format=count --allow-root 2>/dev/null | tr -d ' ')
if [ "${EXISTING:-0}" -lt 6 ]; then
  wp --path=/var/www/html post delete $(wp --path=/var/www/html post list --post_type=post --post_status=publish --format=ids --allow-root 2>/dev/null) --force --allow-root 2>/dev/null || true

  for FILE in /seed/articles/*.md; do
    [ -f "$FILE" ] || continue
    SLUG=$(basename "$FILE" .md | sed 's/^[0-9]*-//')
    TITLE=$(parse_frontmatter "$FILE" title)
    CATS=$(parse_categories "$FILE")
    CATS_CLEAN=$(echo "$CATS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^\*\*//;s/\*\*$//' | tr '\n' ',' | sed 's/,$//')

    echo "  + $SLUG | cat=[$CATS_CLEAN] | title='$TITLE'"
    if [ -n "$CATS_CLEAN" ]; then
      awk 'BEGIN{fm=0} /^---$/{fm=!fm; next} !fm{print}' "$FILE" | \
        sed 's/^#\+[[:space:]]*//' | sed 's/\*\*//g' | sed 's/^>//' | \
        wp --path=/var/www/html post create - \
        --post_type=post --post_status=publish \
        --post_title="$TITLE" --post_name="$SLUG" \
        --post_excerpt="$TITLE." \
        --post_category="$CATS_CLEAN" \
        --allow-root 2>&1 | tail -1
    else
      awk 'BEGIN{fm=0} /^---$/{fm=!fm; next} !fm{print}' "$FILE" | \
        sed 's/^#\+[[:space:]]*//' | sed 's/\*\*//g' | sed 's/^>//' | \
        wp --path=/var/www/html post create - \
        --post_type=post --post_status=publish \
        --post_title="$TITLE" --post_name="$SLUG" \
        --post_excerpt="$TITLE." \
        --allow-root 2>&1 | tail -1
    fi

    # Featured image
    IMG_URL=$(grep '^featured_image:' "$FILE" | head -1 | sed 's/^featured_image:[[:space:]]*//' | sed 's/^"//;s/"$//')
    if [ -n "$IMG_URL" ]; then
      POST_ID=$(wp --path=/var/www/html post list --post_type=post --name="$SLUG" --field=ID --allow-root 2>/dev/null | head -1)
      if [ -n "$POST_ID" ]; then
        CURRENT_THUMB=$(wp --path=/var/www/html post get "$POST_ID" --field=meta_value --meta_key=_thumbnail_id --allow-root 2>/dev/null | head -1)
        if [ -z "$CURRENT_THUMB" ]; then
          echo "    downloading $IMG_URL"
          curl -sL --max-time 30 -o /tmp/feat.jpg "$IMG_URL" 2>/dev/null
          if [ -s /tmp/feat.jpg ] && [ "$(stat -c%s /tmp/feat.jpg 2>/dev/null)" -gt 1000 ]; then
            wp --path=/var/www/html media import /tmp/feat.jpg --post_id="$POST_ID" --featured_image --allow-root 2>&1 | tail -1
          fi
        fi
      fi
    fi
  done
fi

echo "==> ✓ Bootstrap done"
wp --path=/var/www/html post list --post_type=post --post_status=publish --format=count --allow-root
wp --path=/var/www/html post list --post_type=page --post_status=publish --format=count --allow-root
