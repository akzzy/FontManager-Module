# shellcheck shell=ash

# This file is a wrapper around functions-real.sh so we can switch to bash

# Pretty banner
do_banner() {
  echo "=========================================="
  echo "   ____            __                     "
  echo "  / __/___   ___  / /_                    "
  echo " / _/ / _ \ / _ \/ __/                    "
  echo "/_/   \___//_//_/\__/                     "
  echo "   __  ___                                "
  echo "  /  |/  /___ _ ___  ___ _ ___ _ ___  ____"
  echo " / /|_/ // _ \`// _ \/ _ \`// _ \`// -_)/ __/"
  echo "/_/  /_/ \_,_//_//_/\_,_/ \_, / \__//_/   "
  echo "                         /___/            "
  echo "=========================================="
  sleep 0.5
}
do_banner
ui_print "ⓘ Extracting installer..."
ui_print "ⓘ Please be patient, this may take a minute on some devices"
unzip -o "$ZIPFILE" -x 'META-INF/*' 'common/functions.sh' -d "$MODPATH" >&2
tar -xf "$MODPATH/common/tools/tools.tar.xz" -C "$MODPATH/common/tools" >&2
chmod -R 755 "$MODPATH"/common/tools/
# Execute real functions in bash
# shellcheck disable=SC2097,SC2098
MODPATH=$MODPATH TMPDIR=$TMPDIR ARCH=$ARCH API=$API "$MODPATH"/common/tools/bash-"$ARCH" "$MODPATH"/common/functions-real.sh