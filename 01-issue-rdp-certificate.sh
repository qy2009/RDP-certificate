#!/usr/bin/env bash
set -Eeuo pipefail

# Obtain/renew a publicly trusted Let's Encrypt certificate through Cloudflare
# DNS-01, then package it as a PFX suitable for the Windows RDP listener.
#
# Usage:
#   ./01-issue-rdp-certificate.sh <rdp-hostname> <acme-email> [output-directory]
#
# Example:
#   ./01-issue-rdp-certificate.sh win.rui-qiu.com me@example.com ./rdp-certs

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <rdp-hostname> <acme-email> [output-directory]" >&2
  exit 2
fi

DOMAIN=${1,,}
ACME_EMAIL=$2
OUTPUT_INPUT=${3:-./rdp-certs}

if [[ ! "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || [[ "$DOMAIN" != *.* ]]; then
  echo "Error: '$DOMAIN' is not a valid fully-qualified DNS hostname." >&2
  exit 2
fi

for command_name in docker openssl sed; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: required command '$command_name' was not found." >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT_INPUT"
OUTPUT_DIR=$(cd "$OUTPUT_INPUT" && pwd -P)
LEGO_DIR="$OUTPUT_DIR/lego-state"
mkdir -p "$LEGO_DIR"

if [[ -z "${CF_DNS_API_TOKEN:-}" ]]; then
  read -r -s -p "Cloudflare API token (Zone:Read + DNS:Edit): " CF_DNS_API_TOKEN
  echo
fi

if [[ -z "$CF_DNS_API_TOKEN" ]]; then
  echo "Error: the Cloudflare API token cannot be empty." >&2
  exit 1
fi

if [[ -z "${RDP_PFX_PASSWORD:-}" ]]; then
  read -r -s -p "Password for the output PFX: " RDP_PFX_PASSWORD
  echo
  read -r -s -p "Repeat the PFX password: " RDP_PFX_PASSWORD_CONFIRM
  echo
  if [[ "$RDP_PFX_PASSWORD" != "$RDP_PFX_PASSWORD_CONFIRM" ]]; then
    echo "Error: the PFX passwords do not match." >&2
    exit 1
  fi
fi

if [[ -z "$RDP_PFX_PASSWORD" ]]; then
  echo "Error: the PFX password cannot be empty." >&2
  exit 1
fi

cleanup_secrets() {
  unset CF_DNS_API_TOKEN RDP_PFX_PASSWORD RDP_PFX_PASSWORD_CONFIRM
}
trap cleanup_secrets EXIT

echo "Obtaining or renewing the certificate for $DOMAIN ..."
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e CF_DNS_API_TOKEN \
  -v "$LEGO_DIR:/lego" \
  goacme/lego:latest \
  --path /lego \
  --email "$ACME_EMAIL" \
  --accept-tos \
  --key-type RSA2048 \
  --dns cloudflare \
  --domains "$DOMAIN" \
  run

CERT_FILE="$LEGO_DIR/certificates/$DOMAIN.crt"
KEY_FILE="$LEGO_DIR/certificates/$DOMAIN.key"

if [[ ! -s "$CERT_FILE" || ! -s "$KEY_FILE" ]]; then
  echo "Error: lego completed without producing the expected certificate files." >&2
  exit 1
fi

if ! openssl x509 -in "$CERT_FILE" -noout -checkhost "$DOMAIN" >/dev/null 2>&1; then
  echo "Error: the issued certificate does not match $DOMAIN." >&2
  exit 1
fi

PFX_FILE="$OUTPUT_DIR/$DOMAIN.pfx"
SHA1_FILE="$OUTPUT_DIR/$DOMAIN.sha1"

# Lego's .crt contains the leaf certificate followed by the issuer chain.
openssl pkcs12 -export \
  -out "$PFX_FILE" \
  -inkey "$KEY_FILE" \
  -in "$CERT_FILE" \
  -name "$DOMAIN" \
  -passout env:RDP_PFX_PASSWORD

openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha1 \
  | sed 's/^.*=//; s/://g' > "$SHA1_FILE"

chmod 600 "$PFX_FILE" "$SHA1_FILE"

echo
echo "Created:"
echo "  $PFX_FILE"
echo "  $SHA1_FILE"
echo
echo "Copy both files to the Windows machine, then run script 02 as Administrator."
