<?php
/**
 * Asigna los menus a las locations de Editorial
 * Editorial usa: primary, top-header, footer
 */
$primary = getenv('PRIMARY_MENU');
$top     = getenv('TOP_MENU');

$locations = array();
if ($primary) {
    $locations['primary'] = (int) $primary;
}
if ($top) {
    $locations['top-header'] = (int) $top;
}

if (!empty($locations)) {
    set_theme_mod('nav_menu_locations', $locations);
    echo "nav_menu_locations set: " . json_encode($locations) . "\n";
}

// Asignar front page si está en el env
$front = getenv('MAG_ID');
if ($front) {
    update_option('page_on_front', (int) $front);
    update_option('show_on_front', 'page');
    echo "page_on_front={$front}\n";
}

// Guardar menu locations en theme_mods_editorial (por si acaso)
$mods = get_option('theme_mods_editorial', array());
$mods['nav_menu_locations'] = $locations;
update_option('theme_mods_editorial', $mods);
echo "theme_mods_editorial updated\n";
