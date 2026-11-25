set -euo pipefail

app=$1
signing_dir=${ROWVI_SIGNING_DIR:-"$HOME/Library/Application Support/Rowvi/Signing"}
certificate="$signing_dir/certificate.pem"
private_key="$signing_dir/private.key"
if [[ ! -f $certificate || ! -f $private_key ]]; then
    echo "Не найден ключ подписи Rowvi: $signing_dir" >&2
    exit 1
fi

identifier=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
fingerprint=$(/usr/bin/openssl x509 -in "$certificate" -outform DER | shasum | awk '{print $1}')
requirement="identifier \"$identifier\" and certificate leaf = H\"$fingerprint\""
if codesign --verify --deep --strict -R="$requirement" "$app" 2>/dev/null; then
    exit 0
fi

signer=${RCODESIGN:-rcodesign}
if [[ -z ${RCODESIGN:-} && -x "$HOME/Library/Application Support/Rowvi/bin/rcodesign" ]]; then
    signer="$HOME/Library/Application Support/Rowvi/bin/rcodesign"
fi
if ! command -v "$signer" >/dev/null; then
    echo "Установите rcodesign или укажите путь к нему в RCODESIGN" >&2
    exit 1
fi
"$signer" sign --config-file /dev/null --timestamp-url none --shallow \
    --pem-file "$certificate" --pem-file "$private_key" "$app"
codesign --verify --deep --strict -R="$requirement" "$app"
