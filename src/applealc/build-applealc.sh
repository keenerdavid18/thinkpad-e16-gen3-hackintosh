#!/bin/zsh
# Builds AppleALC 1.9.8 with an added Synaptics/Conexant SN6140 entry (codec 0x14F11F87, this
# E16's codec), using only the Command Line Tools (no Xcode).
#   zsh build-applealc.sh          -> build/AppleALC.kext
#   DEBUG=1 zsh build-applealc.sh  -> debug build (logs with -alcdbg; needs the Lilu DEBUG kext
#                                     and -liludbg), for working out why AppleHDA rejects a layout
# Upstream AppleALC has no SN6140. Linux drives it with the same code as its sibling CX8070
# (0x14F11F86), so the SN6140 entry is the CX8070 one re-keyed: same layouts (15 = ThinkPad
# E590, 21 = ThinkPad E14) with their CodecID set to 0x14F11F87, same pin configs, and the
# AppleHDA codec-table patch rewritten to insert 0x14F11F87 instead of 0x14F11F86. Pick the layout with layout-id in DeviceProperties.
# The internal mics are DMICs behind the DSP, which AppleHDA can't drive.
set -e
ROOT=${0:A:h}
DEPS=$ROOT/build/deps
OUT=$ROOT/build/AppleALC.kext
TAG=1.9.8
LILU_VER=1.7.2
NAME=AppleALC; BID=as.vit9696.AppleALC; VER=$TAG
mkdir -p $DEPS
[[ -d $DEPS/MacKernelSDK ]] || git clone --depth 1 https://github.com/acidanthera/MacKernelSDK.git $DEPS/MacKernelSDK
if [[ ! -d $DEPS/Lilu.kext ]]; then
  curl -sfL -o $DEPS/lilu.zip https://github.com/acidanthera/Lilu/releases/download/$LILU_VER/Lilu-$LILU_VER-DEBUG.zip
  unzip -qo $DEPS/lilu.zip 'Lilu.kext/*' -d $DEPS
fi
[[ -d $DEPS/AppleALC ]] || git -c advice.detachedHead=false clone -q --depth 1 --branch $TAG https://github.com/acidanthera/AppleALC.git $DEPS/AppleALC
A=$DEPS/AppleALC
SDK=$DEPS/MacKernelSDK
LILU=$DEPS/Lilu.kext/Contents/Resources

# 1. SN6140 resources, derived from CX8070 (idempotent).
python3 -I - $A/Resources <<'EOF'
import plistlib, shutil, sys, os
R = sys.argv[1]
src, dst = os.path.join(R, "CX8070"), os.path.join(R, "SN6140")
shutil.rmtree(dst, ignore_errors=True)
os.mkdir(dst)
for f in os.listdir(src):
    if f.endswith(".xml"):
        x = open(os.path.join(src, f)).read()
        # Layouts tag their PathMapRef with the codec id (decimal); AppleHDA ignores a layout
        # whose CodecID list lacks the running codec and stops 5 s later.
        if f.startswith("layout"):
            assert "<integer>351346566</integer>" in x, f
            x = x.replace("<integer>351346566</integer>", "<integer>351346567</integer>")
        open(os.path.join(dst, f), "w").write(x)
d = plistlib.load(open(os.path.join(src, "Info.plist"), "rb"))
d["CodecID"] = 0x1F87
d["CodecName"] = "SN6140"
for p in d["Patches"]:
    if p["Replace"] == bytes.fromhex("861ff114"):  # AppleHDA codec table: insert our codec id
        p["Replace"] = bytes.fromhex("871ff114")
for group in d["Files"].values():
    for e in group:
        e["Comment"] = e["Comment"].replace("CX8070", "SN6140 (as CX8070)")
plistlib.dump(d, open(os.path.join(dst, "Info.plist"), "wb"))
pc_path = os.path.join(R, "PinConfigs.kext/Contents/Info.plist")
pc = plistlib.load(open(pc_path, "rb"))
cfg = pc["IOKitPersonalities"]["as.vit9696.AppleALC"]["HDAConfigDefault"]
cfg[:] = [e for e in cfg if e.get("CodecID") != 0x14F11F87]
for e in [e for e in cfg if e.get("CodecID") == 0x14F11F86]:
    n = dict(e); n["CodecID"] = 0x14F11F87
    n["Codec"] = e["Codec"].replace("CX8070", "SN6140 (as CX8070)")
    cfg.append(n)
plistlib.dump(pc, open(pc_path, "wb"))
EOF

# 2. Pack layouts/platforms and generate kern_resources.cpp (generate.sh minus Xcode-only steps).
(cd $A && find ./Resources -name "*.xml" | while read x; do perl Tools/zlib.pl deflate "$x" > "$x.zlib"; done)
TMP=$(mktemp -d)
clang++ -fobjc-arc -O2 -std=gnu++17 -framework Foundation -framework Cocoa \
  $A/ResourceConverter/main.mm -o $TMP/ResourceConverter
rm -f $A/AppleALC/kern_resources.cpp
$TMP/ResourceConverter $A/Resources $A/AppleALC/kern_resources.cpp
grep -q "0x1F87" $A/AppleALC/kern_resources.cpp || { echo "SN6140 missing from kern_resources.cpp"; exit 1; }

# 3. Info.plist with the pin configs merged in (what Tools/merge_pinconfigs.sh does).
rm -rf $OUT; mkdir -p $OUT/Contents/MacOS
sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BID/g" -e "s/\$(PRODUCT_NAME:rfc1034identifier)/$NAME/g" \
    -e "s/\$(PRODUCT_NAME)/$NAME/g" -e "s/\$(EXECUTABLE_NAME)/$NAME/g" -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
    -e "s/\$(PRODUCT_BUNDLE_PACKAGE_TYPE)/KEXT/g" -e "s/\$(MODULE_NAME)/$BID/g" \
    -e "s/\$(MODULE_VERSION)/$VER/g" -e "s/\$(CURRENT_PROJECT_VERSION)/$VER/g" -e "s/\$(MARKETING_VERSION)/$VER/g" \
    $A/AppleALC/AppleALC-Info.plist > $OUT/Contents/Info.plist
grep -q '\$(' $OUT/Contents/Info.plist && { echo "unresolved variable in Info.plist"; grep '\$(' $OUT/Contents/Info.plist; exit 1; }
P=$OUT/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :Tmp dict" -c "Merge $A/Resources/PinConfigs.kext/Contents/Info.plist :Tmp" \
  -c "Delete :IOKitPersonalities:as.vit9696.AppleALC" \
  -c "Copy :Tmp:IOKitPersonalities:as.vit9696.AppleALC :IOKitPersonalities:as.vit9696.AppleALC" \
  -c "Delete :Tmp" $P >/dev/null
/usr/libexec/PlistBuddy -c "Delete :OSBundleLibraries:as.vit9696.PinConfigs" $P >/dev/null 2>&1 || true

# 4. Compile and link.
FLAGS=(-arch x86_64 -mkernel -nostdinc -fno-builtin -fno-common -fno-stack-protector -mmacosx-version-min=11.0
       -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -isystem $SDK/Headers -O2 -g
       -DPRODUCT_NAME=$NAME -DMODULE_VERSION=$VER -DHAVE_ANALOG_AUDIO=1 -I$LILU ${DEBUG:+-DDEBUG=1}
       -mmmx -msse -msse2 -msse3 -mssse3 -mfpmath=sse -fno-asynchronous-unwind-tables)
cat > $TMP/info.c <<EOC
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
extern kern_return_t ${NAME}_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t ${NAME}_kern_stop(kmod_info_t *ki, void *data);
// Same layout Xcode generates: libkmod's _start/_stop call _realmain/_antimain (MODULE_START/STOP).
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL($BID, "$VER", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = ${NAME}_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = ${NAME}_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOC
clang $FLAGS -c $TMP/info.c -o $TMP/info.o
for f in $A/AppleALC/*.cpp $A/AppleALC/ALCUserClient/*.cpp $A/AppleALC/ALCUserClientProvider/*.cpp $LILU/Library/plugin_start.cpp; do
  clang++ $FLAGS -std=gnu++14 -nostdinc++ -fno-exceptions -fno-rtti -fapple-kext -I$A/AppleALC -I$A/AppleALC/ALCUserClient -I$A/AppleALC/ALCUserClientProvider \
    -Wno-deprecated-declarations -Wno-inconsistent-missing-override -Wno-vla -c $f -o $TMP/$(basename ${f%.cpp}).o
done
clang++ -arch x86_64 -mkernel -nostdlib -static -Xlinker -kext -Xlinker -export_dynamic -mmacosx-version-min=11.0 \
  $TMP/*.o $SDK/Library/x86_64/libkmod.a -lcc_kext -o $OUT/Contents/MacOS/$NAME
strip -S $OUT/Contents/MacOS/$NAME 2>/dev/null   # drop debug stabs (they embed local build paths)
codesign -f -s - $OUT >/dev/null 2>&1 || true
rm -rf $TMP; echo "built $OUT"
