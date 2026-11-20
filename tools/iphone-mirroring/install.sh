#!/bin/zsh
# install.sh: iPhone Mirroring / AirPlay-to-Mac workarounds for this Iris Xe (NootedGreen) build. Run WITHOUT sudo.
#   zsh tools/iphone-mirroring/install.sh          build + install both parts, run them now
#   zsh tools/iphone-mirroring/install.sh remove   uninstall everything
# 1. ws-nogva  : turns off WindowServer's AppleGVA scaler at every login (stops the WindowServer crash -> logout)
# 2. vtbgra    : makes the AirPlay receiver (ControlCenter) decode to BGRA + `enableGVATransfer = NO`, so the
#                iPhone picture shows instead of a black screen. Loaded into ControlCenter at login.
# Needs amfi_get_out_of_my_way=1 in boot-args (this EFI has it) and the Xcode Command Line Tools.
set -e
here=${0:A:h}; dst="$HOME/Library/Application Support/E16Mirroring"; la="$HOME/Library/LaunchAgents"
plist1="$la/local.e16.ws-nogva.plist"; plist2="$la/local.e16.airplay-bgra.plist"
if [[ ${1:-} == remove ]]; then
  launchctl bootout gui/$UID "$plist1" 2>/dev/null || true; launchctl bootout gui/$UID "$plist2" 2>/dev/null || true
  rm -f "$plist1" "$plist2"; rm -rf "$dst"; defaults delete -g enableGVATransfer 2>/dev/null || true
  killall ControlCenter 2>/dev/null || true
  print "removed (WindowServer's GVA scaler comes back after the next login)"; exit 0
fi
mkdir -p "$dst" "$la"
clang -O2 -o "$dst/ws-nogva" "$here/ws-nogva.c" -F/System/Library/PrivateFrameworks -framework SkyLight
codesign -s - -f --entitlements "$here/ent.plist" "$dst/ws-nogva"
clang -arch x86_64 -dynamiclib -O2 -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
  -framework CoreFoundation -o "$dst/vtbgra.dylib" "$here/vtbgra.c"
codesign -s - -f "$dst/vtbgra.dylib"
cat > "$dst/airplay-bgra.sh" <<'S'
#!/bin/sh
# restart ControlCenter (the AirPlay receiver) with vtbgra.dylib loaded; the variable is only set for 5 s
LIB="$HOME/Library/Application Support/E16Mirroring/vtbgra.dylib"
[ -f "$LIB" ] || exit 0
launchctl setenv DYLD_INSERT_LIBRARIES "$LIB"; killall ControlCenter 2>/dev/null; sleep 5; launchctl unsetenv DYLD_INSERT_LIBRARIES
S
chmod +x "$dst/airplay-bgra.sh"
agent() {  # label program [args]
  cat > "$la/$1.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array><string>$2</string></array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
P
  launchctl bootout gui/$UID "$la/$1.plist" 2>/dev/null || true
  launchctl bootstrap gui/$UID "$la/$1.plist"
}
defaults write -g enableGVATransfer -bool NO
agent local.e16.ws-nogva "$dst/ws-nogva"
agent local.e16.airplay-bgra "$dst/airplay-bgra.sh"
print "installed. Turn AirPlay mirroring off and on again on the iPhone. iPhone Mirroring (the app): see README."
