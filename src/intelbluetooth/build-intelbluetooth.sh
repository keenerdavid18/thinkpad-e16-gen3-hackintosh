#!/bin/zsh
# Builds IntelBluetoothFirmware.kext and IntelBTPatcher.kext from the lshbluesky fork of
# OpenIntelWireless/IntelBluetoothFirmware, using only the Command Line Tools (no Xcode).
#   zsh build-intelbluetooth.sh        -> build/IntelBluetoothFirmware.kext, build/IntelBTPatcher.kext
# Why the fork (v2.5.2): it is upstream master a414375 (Sequoia DMA fix for the 2.4.0
# IntelBTPatcher login panic, support through Tahoe) plus Bluetooth LE fixes and the June 2026
# linux-firmware update - including a new ibt-0040-0041.sfi, the image this AX211 (8087:0033)
# loads. With 2.4.0's firmware, Sequoia's bluetoothd aborts HCI init on LE_Read_BufferSize_V2,
# which that firmware doesn't implement (supported-commands byte 41 bit 5 = 0).
# Install: replace EFI/OC/Kexts/IntelBluetoothFirmware.kext and IntelBTPatcher.kext with the
# outputs (IntelBTPatcher needs Lilu first).
set -e
ROOT=${0:A:h}
DEPS=$ROOT/build/deps
REPO=https://github.com/lshbluesky/IntelBluetoothFirmware.git
REV=14787a2
LILU_VER=1.7.2
VER=2.5.2
mkdir -p $DEPS
[[ -d $DEPS/MacKernelSDK ]] || git clone --depth 1 https://github.com/acidanthera/MacKernelSDK.git $DEPS/MacKernelSDK
if [[ ! -d $DEPS/Lilu.kext ]]; then
  curl -sfL -o $DEPS/lilu.zip https://github.com/acidanthera/Lilu/releases/download/$LILU_VER/Lilu-$LILU_VER-DEBUG.zip
  unzip -qo $DEPS/lilu.zip 'Lilu.kext/*' -d $DEPS
fi
if [[ ! -d $DEPS/IntelBluetoothFirmware ]]; then
  git clone $REPO $DEPS/IntelBluetoothFirmware
  git -C $DEPS/IntelBluetoothFirmware checkout -q $REV
fi
I=$DEPS/IntelBluetoothFirmware
# Local patches (patches/*.patch) on top of the pinned fork; IBF_PATCHES=0 builds the fork unmodified.
# 0001: power-child state uses kIOPMLowPower so the controller can idle-suspend (with BTIdle; ~1.6 W idle).
git -C $I checkout -q -- .
if [[ ${IBF_PATCHES:-1} = 1 ]]; then
  for p in $ROOT/patches/*.patch(N); do git -C $I apply $p && echo "applied ${p:t}"; done
fi
SDK=$DEPS/MacKernelSDK
LILU=$DEPS/Lilu.kext/Contents/Resources
BASE=(-arch x86_64 -mkernel -nostdinc -fno-builtin -fno-common -fno-stack-protector -mmacosx-version-min=11.0
      -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -isystem $SDK/Headers -O2 -g -DMODULE_VERSION=$VER)
CXX=(-std=gnu++14 -nostdinc++ -fno-exceptions -fno-rtti -fapple-kext
     -Wno-deprecated-declarations -Wno-inconsistent-missing-override)

# $1 name, $2 bundle id, $3 Info.plist, $4 start fn (or empty), $5 stop fn, $6 object dir
make_kext() {
  local NAME=$1 BID=$2 PLIST=$3 START=$4 STOP=$5 OBJ=$6 OUT=$ROOT/build/$1.kext
  rm -rf $OUT; mkdir -p $OUT/Contents/MacOS
  sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BID/g" -e "s/\$(PRODUCT_NAME:rfc1034identifier)/$NAME/g" \
      -e "s/\$(PRODUCT_NAME)/$NAME/g" -e "s/\$(EXECUTABLE_NAME)/$NAME/g" -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
      -e "s/\$(PRODUCT_BUNDLE_PACKAGE_TYPE)/KEXT/g" -e "s/\$(MODULE_NAME)/$BID/g" \
      -e "s/\$(MODULE_VERSION)/$VER/g" -e "s/\$(CURRENT_PROJECT_VERSION)/$VER/g" -e "s/\$(MARKETING_VERSION)/$VER/g" \
      $PLIST > $OUT/Contents/Info.plist
  grep -q '\$(' $OUT/Contents/Info.plist && { echo "unresolved variable in $NAME Info.plist"; grep '\$(' $OUT/Contents/Info.plist; exit 1; }
  # Same kmod layout Xcode generates: libkmod's _start/_stop call _realmain/_antimain (MODULE_START/STOP).
  cat > $OBJ/info.c <<EOC
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
${START:+extern kern_return_t $START(kmod_info_t *ki, void *data);}
${STOP:+extern kern_return_t $STOP(kmod_info_t *ki, void *data);}
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL($BID, "$VER", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = ${START:-0};
__private_extern__ kmod_stop_func_t *_antimain = ${STOP:-0};
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOC
  clang $BASE -c $OBJ/info.c -o $OBJ/info.o
  clang++ -arch x86_64 -mkernel -nostdlib -static -Xlinker -kext -Xlinker -export_dynamic -mmacosx-version-min=11.0 \
    $OBJ/*.o $SDK/Library/x86_64/libkmod.a -lcc_kext -o $OUT/Contents/MacOS/$NAME
  strip -S $OUT/Contents/MacOS/$NAME 2>/dev/null   # drop debug stabs (they embed local build paths)
  codesign -f -s - $OUT >/dev/null 2>&1 || true
  echo "built $OUT"
}

# IntelBluetoothFirmware: plain IOKit kext; firmware images zlib-packed into FwBinary.cpp.
TMP=$(mktemp -d); mkdir -p $TMP/fw $TMP/pt
# Our own packer, producing what the fork's scripts/zlib_compress_fw.py does: one zlib-compressed
# array per unique image (deduplicated by SHA-1), plus the fwList[]/fwNumber table FwData.h reads.
python3 -I - $I/IntelBluetoothFirmware/fw $TMP/FwBinary.cpp <<'EOF'
import hashlib, os, sys, zlib
src, dst = sys.argv[1], sys.argv[2]
names = sorted(f for f in os.listdir(src) if os.path.isfile(os.path.join(src, f)))
out, seen = ['#include "FwData.h"\n'], set()
for f in names:
    data = open(os.path.join(src, f), "rb").read()
    h = hashlib.sha1(data).hexdigest()
    arr, var = "firmware_" + h, f.replace(".", "_").replace("-", "_")
    if h not in seen:
        seen.add(h)
        z = zlib.compress(data)
        out.append(f"\nconst unsigned char {arr}[] = {{\n")
        out += [", ".join(f"0x{b:02X}" for b in z[i:i + 16]) + ",\n" for i in range(0, len(z), 16)]
        out.append("};\n")
    out.append(f"\nconst unsigned char *{var} = {arr};\nconst long int {var}_size = sizeof({arr});\n")
out.append("\nconst struct FwDesc fwList[] = {")
out += [f'{{IBT_FW("{f}", {f.replace(".", "_").replace("-", "_")}, {f.replace(".", "_").replace("-", "_")}_size)}},\n' for f in names]
out.append(f"}};\nconst int fwNumber = {len(names)};\n")
open(dst, "w").write("".join(out))
print(f"packed {len(names)} firmware files ({len(seen)} unique)")
EOF
for f in $I/IntelBluetoothFirmware/*.cpp $I/IntelBluetoothFirmware/*.c $TMP/FwBinary.cpp; do
  clang++ $BASE $CXX -x c++ -I$I/IntelBluetoothFirmware -DPRODUCT_NAME=IntelBluetoothFirmware \
    -c $f -o $TMP/fw/$(basename ${f%.*}).o
done
make_kext IntelBluetoothFirmware com.zxystd.IntelBluetoothFirmware $I/IntelBluetoothFirmware/Info.plist "" "" $TMP/fw

# IntelBTPatcher: Lilu plugin.
for f in $I/IntelBTPatcher/*.cpp $LILU/Library/plugin_start.cpp; do
  clang++ $BASE $CXX -I$I/IntelBTPatcher -I$LILU -DPRODUCT_NAME=IntelBTPatcher \
    -c $f -o $TMP/pt/$(basename ${f%.cpp}).o
done
make_kext IntelBTPatcher com.zxystd.IntelBTPatcher $I/IntelBTPatcher/Info.plist \
  IntelBTPatcher_kern_start IntelBTPatcher_kern_stop $TMP/pt
rm -rf $TMP
