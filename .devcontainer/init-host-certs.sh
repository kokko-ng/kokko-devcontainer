#!/usr/bin/env bash
# Runs on the HOST before docker build (initializeCommand).
# Extracts macOS system CA certificates so the container can trust
# corporate proxy CAs without disabling SSL verification.
#
# Splits into individual .crt files so update-ca-certificates processes
# them without rehash warnings. Expired certificates are dropped when
# openssl is available to check them.
set -euo pipefail

# Derive the certs directory from this script's own location — a relative
# path silently depends on the caller's cwd, which is exactly the kind of
# thing you do not want feeding a delete-and-recreate.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"
mkdir -p "$CERT_DIR"
# Remove only our own previous output; .gitkeep stays so the directory always
# exists in git and plain `docker build` works.
rm -f "$CERT_DIR"/host-ca-*.crt

extract_individual_certs() {
    local bundle="$1"
    awk -v dir="$CERT_DIR" '
        /-----BEGIN CERTIFICATE-----/ { n++; f = dir "/host-ca-" (n - 1) ".crt" }
        f { print > f }
        /-----END CERTIFICATE-----/ { close(f); f = "" }
        END { printf "  Extracted %d certificates\n", n }
    ' "$bundle"
}

prune_expired_certs() {
    command -v openssl >/dev/null 2>&1 || return 0
    local f removed=0
    for f in "$CERT_DIR"/host-ca-*.crt; do
        [[ -e "$f" ]] || continue
        if ! openssl x509 -checkend 0 -noout -in "$f" >/dev/null 2>&1; then
            rm -f "$f"
            removed=$((removed + 1))
        fi
    done
    [[ $removed -gt 0 ]] && echo "  Dropped $removed expired certificate(s)"
    return 0
}

echo "=== Extracting host CA certificates ==="

TMPBUNDLE="$(mktemp)"
trap 'rm -f "$TMPBUNDLE"' EXIT

if [[ "$(uname)" == "Darwin" ]]; then
    security find-certificate -a -p /Library/Keychains/System.keychain > "$TMPBUNDLE" 2>/dev/null || true
    security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain >> "$TMPBUNDLE" 2>/dev/null || true
else
    if [[ -f /etc/ssl/certs/ca-certificates.crt ]]; then
        cp /etc/ssl/certs/ca-certificates.crt "$TMPBUNDLE"
    fi
fi

if [[ -s "$TMPBUNDLE" ]]; then
    extract_individual_certs "$TMPBUNDLE"
    prune_expired_certs
else
    echo "  No certificates found; leaving $CERT_DIR empty (.gitkeep keeps it present)"
fi

echo "=== Host CA certificates extracted to $CERT_DIR ==="
