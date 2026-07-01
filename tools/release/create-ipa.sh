#!/bin/sh

set -eu

CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"

cd "$ROOT_DIR"

if [ ! -d "$APP_DIR" ]; then
        echo "Missing archive output at $APP_DIR"
        echo "Run tools/release/build-app.sh first."
        exit 1
fi

APP_PATH="$(find "$APP_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -z "$APP_PATH" ]; then
        echo "No .app found in $APP_DIR"
        exit 1
fi

plutil -replace CFBundleIdentifier -string "com.minh-ton.ReynardLite" "$APP_PATH/Info.plist"

if [ -d "$APP_PATH/PlugIns/Reynard Helper.appex" ]; then
        plutil -replace CFBundleIdentifier -string "com.minh-ton.ReynardLite.Helper" \
                "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist"
fi

if [ -d "$APP_PATH/PlugIns/OpenIn.appex" ]; then
        plutil -replace CFBundleIdentifier -string "com.minh-ton.ReynardLite.OpenIn" \
                "$APP_PATH/PlugIns/OpenIn.appex/Info.plist"
fi

rm -rf "$WORK_DIR" "$ROOT_DIR/dist/Reynard.ipa" "$ROOT_DIR/dist/Reynard-TrollStore.tipa" "$ROOT_DIR/dist/Reynard-Jailbroken.ipa"
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

cd "$WORK_DIR"
zip -r ../Reynard.ipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX"

PTRACE_JIT_SRC="$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.c"
PTRACE_JIT_OUT="Payload/Reynard.app/ptrace_jit"

"$CLANG_PATH" \
        -arch arm64 \
        -isysroot "$SDK_PATH" \
        -miphoneos-version-min=13.0 \
        -Os \
        "$PTRACE_JIT_SRC" \
        -o "$PTRACE_JIT_OUT"

chmod 0755 "$PTRACE_JIT_OUT"
ldid -S"$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" "$PTRACE_JIT_OUT"
ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "Payload/Reynard.app/Reynard"

if [ -f "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper" ]; then
        ldid -S"$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" \
                "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper"
fi

# ── TrollStore signing ────────────────────────────────────────────────────────
# TrollStoreHelper's final step runs `ldid -s <app>` to strip Apple-format
# codesign signatures from every Mach-O binary it didn't explicitly re-sign
# itself. On large binaries (e.g. GeckoView.framework/GeckoView) this hits
# ldid.cpp:517, which cannot parse/rewrite the Apple-format signature blob.
# The failure isn't silent: trollstorehelper repeatedly logs "Write failed"
# (once per mmap'd segment it tries to patch) before aborting the install,
# which is exactly the symptom reported.
#
# Root-cause fix: don't hand-pick which binaries to pre-sign. Recursively
# find *every* Mach-O file inside the .app bundle (main binary, appex
# binaries, frameworks, dylibs — including anything nested inside
# GeckoView.framework), strip any Apple codesign, and re-sign it with ldid
# ahead of time. TrollStoreHelper then finds every binary already carrying
# an ldid-format signature and either skips it or reprocesses it cleanly,
# instead of choking on whichever binary we forgot to list by hand.
APP_BUNDLE="Payload/Reynard.app"

is_macho() {
        # Reads the first 4 bytes and checks for Mach-O / fat-binary magic.
        magic="$(dd if="$1" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
        case "$magic" in
                cffaedfe|feedfacf|cafebabe|bebafeca) return 0 ;;
                *) return 1 ;;
        esac
}

# The main app binary and the Helper appex binary were already re-signed
# above with their specific entitlements files — don't clobber those with a
# blank `ldid -S` here.
MAIN_BIN="$APP_BUNDLE/Reynard"
HELPER_BIN="$APP_BUNDLE/PlugIns/Reynard Helper.appex/Reynard Helper"

echo "Scanning $APP_BUNDLE for remaining Mach-O binaries to re-sign for TrollStore…"
find "$APP_BUNDLE" -type f | while IFS= read -r bin; do
        case "$bin" in
                "$MAIN_BIN"|"$HELPER_BIN") continue ;;
        esac
        if is_macho "$bin"; then
                echo "  pre-signing: $bin"
                codesign --remove-signature "$bin" 2>/dev/null || true
                ldid -S "$bin" 2>&1 | sed "s#^#    #"
        fi
done

zip -r ../Reynard-TrollStore.tipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX"
cp ../Reynard-TrollStore.tipa ../Reynard-Jailbroken.ipa
