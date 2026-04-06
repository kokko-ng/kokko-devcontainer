#!/usr/bin/env bash
# Runs on the HOST before docker build (initializeCommand).
# Extracts macOS system CA certificates so the container can trust
# corporate proxy CAs without disabling SSL verification.
#
# Splits into individual .crt files so update-ca-certificates processes
# them without rehash warnings.
set -euo pipefail

CERT_DIR=".devcontainer/certs"
rm -rf "$CERT_DIR"
mkdir -p "$CERT_DIR"

extract_individual_certs() {
    local bundle="$1"
    local idx=0
    local current=""
    local in_cert=false

    while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
            in_cert=true
            current="$line"$'\n'
        elif [[ "$line" == "-----END CERTIFICATE-----" ]]; then
            current+="$line"$'\n'
            printf '%s' "$current" > "$CERT_DIR/host-ca-${idx}.crt"
            idx=$((idx + 1))
            in_cert=false
            current=""
        elif $in_cert; then
            current+="$line"$'\n'
        fi
    done < "$bundle"

    echo "  Extracted $idx certificates"
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
else
    echo "  No certificates found, creating empty placeholder"
    touch "$CERT_DIR/.keep"
fi

echo "=== Host CA certificates extracted to $CERT_DIR ==="
