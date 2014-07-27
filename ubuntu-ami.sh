#!/bin/sh
if [ $# -ne 3 ]; then
    echo "$0 RELEASE CPU_ARCH REGION"
    exit 1
fi
RELEASE=$1
ARCH=$2
REGION=$3
STORAGE=${STORAGE_TYPE:-ebs-ssd}
VIRTUALIZATION=${VIRTUALIZATION:-paravirtual}

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ubuntu-ami"
[ -d "$CACHE_DIR" ] || mkdir "$CACHE_DIR"
CACHE_FILE="${CACHE_DIR}/${RELEASE}"
if [ ! -e "$CACHE_FILE" ]; then
    curl http://uec-images.ubuntu.com/query/${RELEASE}/server/released.current.txt -o "$CACHE_FILE"
fi
awk "(\$1 == \"$RELEASE\") && (\$6 == \"$ARCH\") && (\$5 == \"$STORAGE\") && (\$7 == \"$REGION\") && (\$10 == \"$VIRTUALIZATION\") {print \$8}" <"$CACHE_FILE"
