# shellcheck shell=bash
# shellcheck disable=SC2061,SC3010,SC2166,SC2044,SC2046,SC2086,SC1090,SC2034,SC2155,SC1091,SC2001

set -o pipefail,functrace
export API
API=$(resetprop ro.build.version.sdk)
it_failed() {
  ui_print " "
  ui_print "⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠"
  ui_print " "
  ui_print " Uh-oh, the installer encountered an issue!"
  ui_print " It's probably one of these reasons:"
  ui_print "	 1) Installer is corrupt"
  ui_print "	 2) You didn't follow instructions"
  ui_print "	 3) You have an unstable internet connection"
  ui_print "	 4) Your ROM is broken"
  ui_print "	 5) There's a *tiny* chance we screwed up"
  ui_print " Please fix any issues and retry."
  ui_print " If you feel this is a bug or need assistance, head to our telegram"
  ui_print " All files besides logs are assumed to be corrupt, and have been removed."
  rm -fr "$EXT_DATA"/fonts "$EXT_DATA"/emojis
  ## API_LOGGING ##
  # shellcheck disable=SC3020
  am start -a android.intent.action.VIEW -d "https://www.androidacy.com/contact/?f=fm%20$MODULE_VERSION%20install%20fail" &>/dev/null
  ui_print " "
  ui_print "⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠ ⚠"
  ui_print " "
  exit 1
}

mv "$MODPATH"/common/tools/curl-$ARCH "$MODPATH"/tools/curl
alias curl='$MODPATH/tools/curl --dns-servers 1.1.1.1,8.8.8.8'
abort() {
  ui_print "$1"
  rm -fr $MODPATH 2>/dev/null
  $BOOTMODE || recovery_cleanup
  rm -fr $TMPDIR 2>/dev/null
  it_failed
}
detect_ext_data() {
  export EXT_DATA='/sdcard/FontManager'
  export MODPATH="/data/adb/modules_update/fontrevival"
  export TMPDIR="/data/adb/modules_update/fontrevival"
  mkdir -p "$MODPATH"/logs/
  mkdir -p "$EXT_DATA"/apks/
  mkdir -p "$EXT_DATA"/logs/
  chmod 750 -R "$EXT_DATA"
}
detect_ext_data
### Logging functions

export BRAND=$(getprop ro.product.brand)
export MODEL=$(getprop ro.product.model)
export DEVICE=$(getprop ro.product.device)
export ROM=$(getprop ro.build.display.id)
export API=$(grep_prop ro.build.version.sdk)
# Log <level> <message>
log() {
  echo "[$1] $2" >>$LOGFILE
}

# Initialize logging
setup_logger() {
  LOGFILE=$EXT_DATA/logs/install.log
  export LOGFILE
  {
    echo "[INFO] Module: FontManager $(grep 'version=' $MODPATH/module.prop | cut -d"=" -f2)"
    echo "[INFO] Device: $BRAND $MODEL ($DEVICE)"
    echo "[INFO] ROM: $ROM, sdk $API"
  } >$LOGFILE
  set -x 2
  exec 2>$EXT_DATA/logs/install-debug.log
}

setup_logger
# Source util-functions.sh since we switched shells
. /data/adb/magisk/util_functions.sh
[ -f "$MODPATH/common/addon.tar.xz" ] && tar -xf $MODPATH/common/addon.tar.xz -C $MODPATH/common 2>/dev/null
alias ui_print="echo"
# All error catching attempts failed, let's bail out.
# Debug
ui_print "ⓘ Logging verbosely to ${EXT_DATA}/logs"
# alias busybox applets
set_busybox() {
  set +x
  if [ -x "$1" ]; then
    for i in $(${1} --list); do
      if [ "$i" != 'echo' ]; then
        # shellcheck disable=SC2140,2139
        alias "$i"="${1} $i" &>/dev/null
      fi
    done
    _busybox=true
    _bb=$1
  fi
  set -x
}
_busybox=true
_bb=/data/adb/magisk/busybox
if ! set_busybox $_bb; then
  abort "Unknown error!";
fi
. $MODPATH/common/apiClient.sh
# Set ABORT and ERR trap to logUploader
trap 'logUploader $MODPATH/logs/install-debug.log' ERR
mount_apex() {
  $BOOTMODE || [ ! -d /system/apex ] && return
  local APEX DEST
  setup_mntpoint /apex
  for APEX in /system/apex/*; do
    DEST=/apex/$(basename $APEX .apex)
    [ "$DEST" = /apex/com.android.runtime.release ] && DEST=/apex/com.android.runtime
    mkdir -p $DEST 2>/dev/null
    if [ -f $APEX ]; then
      # APEX APKs, extract and loop mount
      unzip -qo $APEX apex_payload.img -d /apex
      loop_setup apex_payload.img
      if [ -n "$LOOPDEV" ]; then
        mount -t ext4 -o ro,noatime $LOOPDEV $DEST
      fi
      rm -f apex_payload.img
    elif [ -d $APEX ]; then
      # APEX folders, bind mount directory
      mount -o bind $APEX $DEST
    fi
  done
  export ANDROID_RUNTIME_ROOT=/apex/com.android.runtime
  export ANDROID_TZDATA_ROOT=/apex/com.android.tzdata
  local APEXRJPATH=/apex/com.android.runtime/javalib
  local SYSFRAME=/system/framework
  export BOOTCLASSPATH="$APEXRJPATH/core-oj.jar:$APEXRJPATH/core-libart.jar:$APEXRJPATH/okhttp.jar:$APEXRJPATH/bouncycastle.jar:$APEXRJPATH/apache-xml.jar:$SYSFRAME/framework.jar:$SYSFRAME/ext.jar:$SYSFRAME/telephony-common.jar:$SYSFRAME/voip-common.jar:$SYSFRAME/ims-common.jar:$SYSFRAME/android.test.base.jar:$SYSFRAME/telephony-ext.jar:/apex/com.android.conscrypt/javalib/conscrypt.jar:/apex/com.android.media/javalib/updatable-media.jar"
}

umount_apex() {
  [ -d /apex ] || return
  local DEST SRC
  for DEST in /apex/*; do
    [ "$DEST" = '/apex/*' ] && break
    SRC=$(grep $DEST /proc/mounts | awk '{ print $1 }')
    umount -l $DEST
    losetup -d $SRC 2>/dev/null
  done
  rm -fr /apex
  unset ANDROID_RUNTIME_ROOT
  unset ANDROID_TZDATA_ROOT
  unset BOOTCLASSPATH
}

cleanup() {
  rm -fr $MODPATH/common 2>/dev/null
  ui_print " "
  ui_print "**************************************"
  ui_print "*         AMMT by Androidacy         *"
  ui_print "*   Based on the original MMT-ex     *"
  ui_print "**************************************"
  ui_print " "
}

device_check() {
  local opt=$(getopt -o dm -- "$@") type=device
  eval set -- "$opt"
  while true; do
    case "$1" in
    -d)
      local type=device
      shift
      ;;
    -m)
      local type=manufacturer
      shift
      ;;
    --)
      shift
      break
      ;;
    *) abort "Invalid device_check argument $1! Aborting!" ;;
    esac
  done
  local prop=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  for i in /system /vendor /odm /product; do
    if [ -f $i/build.prop ]; then
      for j in "ro.product.$type" "ro.build.$type" "ro.product.vendor.$type" "ro.vendor.product.$type"; do
        [ "$(sed -n "s/^$j=//p" $i/build.prop 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')" = "$prop" ] && return 0
      done
    fi
  done
  return 1
}

cp_ch() {
  local opt=$(getopt -o nr -- "$@") BAK=true UBAK=true FOL=false
  eval set -- "$opt"
  while true; do
    case "$1" in
    -n)
      UBAK=false
      shift
      ;;
    -r)
      FOL=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *) abort "Invalid cp_ch argument $1! Aborting!" ;;
    esac
  done
  local SRC="$1" DEST="$2" OFILES="$1"
  $FOL && local OFILES=$(find $SRC -type f 2>/dev/null)
  [ -z $3 ] && PERM=0644 || PERM=$3
  case "$DEST" in
  $TMPDIR/* | $MODULEROOT/* | $NVBASE/modules/$MODID/*) BAK=false ;;
  esac
  for OFILE in ${OFILES}; do
    if $FOL; then
      if [ "$(basename $SRC)" = "$(basename $DEST)" ]; then
        local FILE=$(echo $OFILE | sed "s|$SRC|$DEST|")
      else
        local FILE=$(echo $OFILE | sed "s|$SRC|$DEST/$(basename $SRC)|")
      fi
    else
      if [[ -d "$DEST" ]]; then
        local FILE="$DEST/$(basename $SRC)"
      else
        local FILE="$DEST"
      fi
    fi
    if $BAK && $UBAK; then
      # shellcheck disable=SC2143
      [ ! "$(grep "$FILE$" $INFO 2>/dev/null)" ] && echo "$FILE" >>$INFO
      [ -f "$FILE" -a ! -f "$FILE~" ] && {
        mv -f $FILE $FILE~
        echo "$FILE~" >>$INFO
      }
    elif $BAK; then
      # shellcheck disable=SC2143
      [ ! "$(grep "$FILE$" $INFO 2>/dev/null)" ] && echo "$FILE" >>$INFO
    fi
    install -D -m $PERM "$OFILE" "$FILE"
  done
}

install_script() {
  case "$1" in
  -l)
    shift
    local INPATH=$NVBASE/service.d
    ;;
  -p)
    shift
    local INPATH=$NVBASE/post-fs-data.d
    ;;
  *) local INPATH=$NVBASE/service.d ;;
  esac
  # shellcheck disable=SC2143
  [ "$(grep "#!/system/bin/sh" $1)" ] || sed -i "1i #!/system/bin/sh" $1
  local i
  for i in "MODPATH" "LIBDIR" "MODID" "INFO" "MODDIR"; do
    case $i in
    "MODPATH") sed -i "1a $i=$NVBASE/modules/$MODID" $1 ;;
    "MODDIR") sed -i "1a $i=\${0%/*}" $1 ;;
    *) sed -i "1a $i=$(eval echo \$$i)" $1 ;;
    esac
  done
  [ "$1" = "$MODPATH/uninstall.sh" ] && return 0
  case $(basename $1) in
  post-fs-data.sh | service.sh) ;;
  *) cp_ch -n $1 $INPATH/$(basename $1) 0755 ;;
  esac
}

prop_process() {
  sed -i -e "/^#/d" -e "/^ *$/d" $1
  [ -f $MODPATH/system.prop ] || mktouch $MODPATH/system.prop
  while read -r LINE; do
    echo "$LINE" >>$MODPATH/system.prop
  done <$1
}

# Check for min/max api version
if test $API -lt 24; then
  abort "! Your system API of $API is less than the minimum api of 26 (Oreo)! Aborting!"
fi

initClient

# Set variables
[ $API -lt 26 ] && DYNLIB=false
[ -z $DYNLIB ] && DYNLIB=false
[ -z $DEBUG ] && DEBUG=false
[ -e "$PERSISTDIR" ] && PERSISTMOD=$PERSISTDIR/magisk/$MODID
INFO=$NVBASE/modules/.$MODID-files
ORIGDIR="$MAGISKTMP/mirror"
if $DYNLIB; then
  LIBPATCH="\/vendor"
  LIBDIR=/system/vendor
else
  LIBPATCH="\/system"
  LIBDIR=/system
fi

# Run addons
if [ "$(ls -A $MODPATH/common/addon/*/install.sh 2>/dev/null)" ]; then
  ui_print " "
  ui_print "ⓘ Running Addons -"
  for i in "$MODPATH"/common/addon/*/install.sh; do
    ui_print "ⓘ Running $(echo $i | sed -r "s|$MODPATH/common/addon/(.*)/install.sh|\1|")..."
    . $i
  done
fi

# Remove files outside of module directory
ui_print "ⓘ Removing old files"

if [ -f $INFO ]; then
  while read -r LINE; do
    if [ "$(echo -n $LINE | tail -c 1)" = "~" ]; then
      continue
    elif [ -f "$LINE~" ]; then
      mv -f $LINE~ $LINE
    else
      rm -f $LINE
      while true; do
        LINE=$(dirname $LINE)
        if [[ "$(ls -A $LINE 2>/dev/null)" ]]; then
          break 1
        else
          rm -fr $LINE
        fi
      done
    fi
  done <$INFO
  rm -f $INFO
fi

### Install

[ -f "$MODPATH/common/install.sh" ] && . $MODPATH/common/install.sh

# Remove comments from files and place them, add blank line to end if not already present
for i in $(find $MODPATH -type f -name "*.sh" -o -name "*.prop" -o -name "*.rule"); do
  if [[ -f $i ]]; then
    {
      sed -i -e "/^#/d" -e "/^ *$/d" $i
      [ "$(tail -1 $i)" ] && echo "" >>$i
    }
  else
    continue
  fi
  case $i in
  "$MODPATH/service.sh") install_script -l $i ;;
  "$MODPATH/post-fs-data.sh") install_script -p $i ;;
  "$MODPATH/uninstall.sh") if [ -s $INFO ] || [ "$(head -n1 $MODPATH/uninstall.sh)" != "# Don't modify anything after this" ]; then
    install_script $MODPATH/uninstall.sh
  else
    rm -f $INFO $MODPATH/uninstall.sh
  fi ;;
  esac
done

$IS64BIT || for i in $(find $MODPATH/system -type d -name "lib64"); do rm -fr $i 2>/dev/null; done
[ -d "/system/priv-app" ] || mv -f $MODPATH/system/priv-app $MODPATH/system/app 2>/dev/null
[ -d "/system/xbin" ] || mv -f $MODPATH/system/xbin $MODPATH/system/bin 2>/dev/null
if $DYNLIB; then
  for FILE in $(find $MODPATH/system/lib* -type f 2>/dev/null | sed "s|$MODPATH/system/||"); do
    [ -s $MODPATH/system/$FILE ] || continue
    case $FILE in
    lib*/modules/*) continue ;;
    esac
    mkdir -p "$(dirname $MODPATH/system/vendor/$FILE)"
    mv -f $MODPATH/system/$FILE $MODPATH/system/vendor/$FILE
    [ "$(ls -A $(dirname $MODPATH/system/$FILE))" ] || rm -fr $(dirname $MODPATH/system/$FILE)
  done
  # Delete empty lib folders (busybox find doesn't have this capability)
  toybox find $MODPATH/system/* -type d -empty -delete >/dev/null 2>&1
fi

# Set permissions
ui_print " "
ui_print "ⓘ Setting Permissions"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive $MODPATH/tools 0 0 0755 0755
set_perm_recursive $MODPATH/system/bin 0 0 0755 0755
if [ -d $MODPATH/system/vendor ]; then
  set_perm_recursive $MODPATH/system/vendor 0 0 0755 0644 u:object_r:vendor_file:s0
  [ -d $MODPATH/system/vendor/app ] && set_perm_recursive $MODPATH/system/vendor/app 0 0 0755 0644 u:object_r:vendor_app_file:s0
  [ -d $MODPATH/system/vendor/etc ] && set_perm_recursive $MODPATH/system/vendor/etc 0 0 0755 0644 u:object_r:vendor_configs_file:s0
  [ -d $MODPATH/system/vendor/overlay ] && set_perm_recursive $MODPATH/system/vendor/overlay 0 0 0755 0644 u:object_r:vendor_overlay_file:s0
  for FILE in $(find $MODPATH/system/vendor -type f -name -- *".apk"); do
    [ -f $FILE ] && chcon u:object_r:vendor_app_file:s0 $FILE
  done
fi

# Complete install
cleanup

# Grep prop
grep_prop() {
  local REGEX="s/^$1=//p"
  shift
  local FILES='/system/build.prop'
  sed -n "$REGEX" $FILES 2>/dev/null | head -n 1
}
