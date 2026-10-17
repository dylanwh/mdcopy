#!/bin/bash
# Build, sign, package, notarize and staple mdcopy as a .pkg installer.
#
# Runs as the Xcode Archive post-action (picks the binary out of the archive)
# or standalone (builds Release itself).
#
# Environment overrides:
#   OUTPUT_DIR       where the .pkg is written            (default: ~/Desktop)
#   NOTARY_PROFILE   notarytool keychain profile name     (default: mdcopy-notary)
#   NOTARY_KEYCHAIN  keychain file holding that profile       (default: login keychain)
#   SKIP_NOTARIZE=1  sign only, do not submit to Apple
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-${HOME}/Desktop}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mdcopy-notary}"
IDENTIFIER="net.hardison.mdcopy"
TEAM_ID="7MAQ6Y7MWC"
APP_CERT="Developer ID Application: Dylan Hardison (${TEAM_ID})"
INSTALLER_CERT="Developer ID Installer: Dylan Hardison (${TEAM_ID})"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

log() { echo "==> $*"; }
die() { echo "Error: $*" >&2; exit 1; }

# 1. Locate the binary (Xcode Archive env first, otherwise build Release).
BINARY_PATH=""
for pair in \
    "ARCHIVE_PATH:Products/usr/local/bin/mdcopy" \
    "ARCHIVE_PRODUCTS_PATH:usr/local/bin/mdcopy" \
    "TARGET_BUILD_DIR:mdcopy" \
    "BUILT_PRODUCTS_DIR:mdcopy"; do
    var="${pair%%:*}"; rel="${pair#*:}"
    base="${!var:-}"
    if [ -n "${base}" ] && [ -f "${base}/${rel}" ]; then
        BINARY_PATH="${base}/${rel}"
        break
    fi
done

if [ -z "${BINARY_PATH}" ]; then
    log "Building mdcopy (Release)..."
    xcodebuild -scheme mdcopy -configuration Release \
        -derivedDataPath "${PROJECT_ROOT}/build" -quiet
    BINARY_PATH="${PROJECT_ROOT}/build/Build/Products/Release/mdcopy"
fi
[ -f "${BINARY_PATH}" ] || die "Could not locate mdcopy binary at ${BINARY_PATH}"
log "Binary: ${BINARY_PATH}"

# 2. Version from MARKETING_VERSION (Xcode env) or the project.
VERSION="${MARKETING_VERSION:-}"
if [ -z "${VERSION}" ]; then
    VERSION="$(xcodebuild -project "${PROJECT_ROOT}/mdcopy.xcodeproj" -scheme mdcopy \
        -configuration Release -showBuildSettings 2>/dev/null \
        | awk '/ MARKETING_VERSION = /{print $3}')"
fi
[ -n "${VERSION}" ] || die "Could not determine MARKETING_VERSION"
PKG_PATH="${OUTPUT_DIR}/mdcopy-${VERSION}.pkg"
log "Version: ${VERSION}"

# 3. Certificates must exist and must chain to the G2 Sub-CA (the original
#    Developer ID CA expires 2027-02-01 and .pkg files signed under it stop
#    installing on that date).
check_cert() {
    local name="$1"
    security find-identity -v -p basic | grep -qF "\"${name}\"" \
        || die "No valid identity named: ${name}"
    local issuer
    issuer="$(security find-certificate -c "${name}" -p | openssl x509 -noout -issuer)"
    case "${issuer}" in
        *"OU=G2"*) ;;
        *) echo "WARNING: ${name} was issued by the ORIGINAL Developer ID CA (expires 2027-02-01)." >&2
           echo "         Re-create it in the developer portal selecting the G2 Sub-CA intermediary." >&2 ;;
    esac
}
check_cert "${APP_CERT}"
check_cert "${INSTALLER_CERT}"

# 4. Stage and re-sign. Plain `xcodebuild build` output carries the
#    get-task-allow debug entitlement and no secure timestamp; notarization
#    rejects both. Re-sign with hardened runtime, timestamp, no entitlements.
STAGING_DIR="$(mktemp -d -t mdcopy_pkg_staging)"
trap 'rm -rf "${STAGING_DIR}"' EXIT

mkdir -p "${STAGING_DIR}/usr/local/bin"
cp "${BINARY_PATH}" "${STAGING_DIR}/usr/local/bin/mdcopy"
chmod 755 "${STAGING_DIR}/usr/local/bin/mdcopy"

log "Signing binary with: ${APP_CERT}"
codesign --force --options runtime --timestamp \
    --identifier "${IDENTIFIER}" \
    --sign "${APP_CERT}" \
    "${STAGING_DIR}/usr/local/bin/mdcopy"
codesign --verify --strict --verbose=2 "${STAGING_DIR}/usr/local/bin/mdcopy"

# 5. Build and sign the package.
log "Building package: ${PKG_PATH}"
mkdir -p "${OUTPUT_DIR}"
/usr/bin/pkgbuild \
    --root "${STAGING_DIR}" \
    --identifier "${IDENTIFIER}" \
    --version "${VERSION}" \
    --ownership recommended \
    --install-location "/" \
    --timestamp \
    --sign "${INSTALLER_CERT}" \
    "${PKG_PATH}"

# 6. Notarize and staple.
NOTARY_KEYCHAIN_ARGS=()
[ -n "${NOTARY_KEYCHAIN:-}" ] && NOTARY_KEYCHAIN_ARGS=(--keychain "${NOTARY_KEYCHAIN}")
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    log "SKIP_NOTARIZE set; package is signed but not notarized."
elif ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" ${NOTARY_KEYCHAIN_ARGS[@]+"${NOTARY_KEYCHAIN_ARGS[@]}"} >/dev/null 2>&1; then
    echo "WARNING: no notarytool profile '${NOTARY_PROFILE}'. Create one with:" >&2
    echo "  xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id <id> --team-id ${TEAM_ID} --password <app-specific-password>" >&2
    echo "Package is signed but NOT notarized." >&2
else
    log "Submitting to Apple notary service (profile: ${NOTARY_PROFILE})..."
    xcrun notarytool submit "${PKG_PATH}" --keychain-profile "${NOTARY_PROFILE}" ${NOTARY_KEYCHAIN_ARGS[@]+"${NOTARY_KEYCHAIN_ARGS[@]}"} --wait
    log "Stapling ticket..."
    xcrun stapler staple "${PKG_PATH}"
fi

log "Result:"
pkgutil --check-signature "${PKG_PATH}" | sed -n '1,4p'
log "Done: ${PKG_PATH}"
