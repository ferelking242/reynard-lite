#!/bin/sh

set -eu

GECKO_DIST_BIN="${GECKO_DIST}/bin"
APP_BUNDLE="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
FRAMEWORKS_DIR="${APP_BUNDLE}/Frameworks"
GECKOVIEW_FW="${FRAMEWORKS_DIR}/GeckoView.framework"
GECKOVIEW_FW_FRAMEWORKS="${GECKOVIEW_FW}/Frameworks"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY_NAME:--}}"
DEFAULT_THEME_SRC="${SRCROOT}/../engine/firefox/toolkit/mozapps/extensions/default-theme"

mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}"

# copy dylibs and XUL, then sign
cp -fL "${GECKO_DIST_BIN}/"*.dylib "${FRAMEWORKS_DIR}/"
cp -fL "${GECKO_DIST_BIN}/XUL" "${GECKOVIEW_FW}/XUL"

for file in "${GECKOVIEW_FW}/XUL" "${FRAMEWORKS_DIR}/"*.dylib; do
        if [ -f "${file}" ]; then
                codesign --force --sign "${SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements "${file}"
        fi
done

# copy the rest of the files, excluding the ones we already copied and the test files
# exit 23 = partial transfer (broken symlinks in dist/bin are non-fatal)
set +e
rsync -pvtrlL --delete --exclude "XUL" --exclude "*.dylib" --exclude "Test*" --exclude "test_*" --exclude "*_unittest" "${GECKO_DIST_BIN}/" "${GECKOVIEW_FW_FRAMEWORKS}"
rsync_exit=$?
set -e
if [ "${rsync_exit}" -ne 0 ] && [ "${rsync_exit}" -ne 23 ]; then
    exit "${rsync_exit}"
fi

# default theme — only copy when Firefox source is present (not just dist cache)
if [ -d "${DEFAULT_THEME_SRC}" ]; then
    mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}/default-theme"
    cp -RfL "${DEFAULT_THEME_SRC}/" "${GECKOVIEW_FW_FRAMEWORKS}/default-theme/"
    echo "resource default-theme file:default-theme/" >> "${GECKOVIEW_FW_FRAMEWORKS}/chrome.manifest"
fi

# sign the GeckoView.framework
codesign --force --sign "${SIGN_IDENTITY}" "${GECKOVIEW_FW}"
