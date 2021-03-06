#!/bin/sh
# Script to build and import alpine edge docker image

REL=${REL:-edge}
MIRROR=${MIRROR:-http://mirror.clarkson.edu/alpine}
SAVE=${SAVE:-0}
REPO=$MIRROR/$REL/main
COMMUNITY_REPO=$MIRROR/$REL/community
ARCH="$(uname -m)"
BUILD_ARCH=${BUILD_ARCH:-$ARCH}

case "$BUILD_ARCH" in
  armv* )
    ARCH_TYPE="armhf"
    TAG=tokinring/alpine-arm
    ;;
  *)
    ARCH_TYPE=$ARCH
    TAG=tokinring/alpine
esac

[ $(id -u) -eq 0 ] || {
  printf >&2 '%s requires root\n' "$0"
  exit 1
}

usage() {
  printf >&2 '%s: [-r release] [-m mirror] [-s]\n' "$0"
  exit 1
}

tmp() {
  TMP=$(mktemp -d /tmp/alpine-docker-XXXXXXXXXX)
  ROOTFS=$(mktemp -d /tmp/alpine-docker-rootfs-XXXXXXXXXX)
  trap "rm -rf $TMP $ROOTFS" EXIT TERM INT
}

apkv() {
  set -x
  curl -s $REPO/$ARCH_TYPE/APKINDEX.tar.gz | tar -Oxz |grep '^P:apk-tools-static$' -a -A1 | tail -n1 | cut -d: -f2
}

getapk() {
  curl -s $REPO/$ARCH_TYPE/apk-tools-static-$(apkv).apk | tar -xz -C $TMP sbin/apk.static
}

mkbase() {
  $TMP/sbin/apk.static --repository $REPO --repository $COMMUNITY_REPO --update-cache --allow-untrusted --root $ROOTFS --initdb add alpine-base
}

pack() {
  local id
  id=$(tar --numeric-owner -C $ROOTFS -c . | docker import - $TAG:$REL)

  docker tag $id $TAG:latest
#  docker run -i -t $TAG printf 'alpine:%s with id=%s created!\n' $REL $id
}

save() {
  [ $SAVE -eq 1 ] || return
  tar --numeric-owner -C $ROOTFS -cf rootfs.tar .
}

while getopts "hr:m:s" opt; do
  case $opt in
    r)
      REL=$OPTARG
      ;;
    m)
      MIRROR=$OPTARG
      ;;
    s)
      SAVE=1
      ;;
    *)
      usage
      ;;
  esac
done

echo -e "Preparing temporary root filesystem for ${TAG} and static apk executable\n"
tmp && getapk

echo -e "Creating base environment\n"
mkbase

echo -e "Configuring repositories\n"
echo -e "$REPO\n" > $ROOTFS/etc/apk/repositories
echo -e "$COMMUNITY_REPO\n" >> $ROOTFS/etc/apk/repositories

echo -e "Packing temporary filesystem into docker image\n"
pack

echo -e "Saving packed filesystem archive\n"
save
