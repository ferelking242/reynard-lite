#!/bin/sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"

TARGET="aarch64-apple-ios"

cd "$ROOT_DIR"

if [ ! -d "$FIREFOX_DIR" ]; then
        echo "Missing firefox source at $FIREFOX_DIR"
        echo "Add the submodule, then run tools/development/update-gecko.sh."
        exit 1
fi

rm -f "$FIREFOX_DIR/.mozconfig"

{
        # ── Core ───────────────────────────────────────────────────────────────
        echo "ac_add_options --enable-application=mobile/ios"
        echo "ac_add_options --target=$TARGET"
        echo "ac_add_options --enable-ios-target=13.0"

        # ── Build mode ─────────────────────────────────────────────────────────
        echo "ac_add_options --enable-optimize=-O2"
        echo "ac_add_options --disable-debug"
        echo "ac_add_options --disable-tests"
        echo "ac_add_options --disable-debug-symbols"

        # ── Linker: use Apple ld64 for iOS cross-compilation.
        # lld was used here previously for link speed, but Apple's clang from
        # Xcode 26+ rejects -fuse-ld=lld for aarch64-apple-ios targets:
        # the configure test exits with "Could not use lld as linker".
        # Homebrew lld is not integrated into Apple's iOS toolchain path.
        # Firefox 152 accepts --enable-linker=ld64 which maps to Apple's
        # bundled ld64 linker — the correct linker for all iOS targets.
        echo "ac_add_options --enable-linker=ld64"

        # ── LTO: thin-LTO gives most of the size/speed benefit with much shorter
        #    link times and fewer toolchain compatibility issues than full/cross LTO.
        echo "ac_add_options --enable-lto=thin"

        # ── Strip heavy subsystems not needed for a single-site browser ─────────
        # NOTE: --disable-accessibility is intentionally ABSENT.  Removing the
        # accessibility subsystem at build time causes Gecko's startup sequence
        # to call ErrorLoadingSheet(eCrash) on the missing chrome CSS files,
        # which hard-crashes the app.  We disable accessibility at runtime via
        # user_pref("accessibility.force_disabled", 1) instead.
        echo "ac_add_options --disable-webrtc"
        echo "ac_add_options --disable-crashreporter"
        echo "ac_add_options --disable-updater"
        echo "ac_add_options --disable-parental-controls"
        echo "ac_add_options --disable-eme"

        # ── WASM sandboxing off (saves ~5 MB, no security regression for this use) ─
        echo "ac_add_options --without-wasm-sandboxed-libraries"
} > "$FIREFOX_DIR/.mozconfig"

if ! rustup target list | grep -q "^$TARGET (installed)"; then
        rustup target add "$TARGET"
fi

export PATH="/opt/homebrew/bin:$PATH"

cd "$FIREFOX_DIR"
./mach build
