set -euo pipefail
umask 077

signing_dir=${ROWVI_SIGNING_DIR:-"$HOME/Library/Application Support/Rowvi/Signing"}
if [[ -f "$signing_dir/certificate.pem" && -f "$signing_dir/private.key" ]]; then
    echo "Ключ подписи Rowvi уже существует: $signing_dir"
    exit 0
fi

mkdir -p "$(dirname "$signing_dir")"
mkdir "$signing_dir"
trap 'rm -f "$signing_dir/private.key" "$signing_dir/certificate.pem"; rmdir "$signing_dir"' EXIT
/usr/bin/openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
    -subj '/CN=Rowvi Release Signing' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=codeSigning' \
    -keyout "$signing_dir/private.key" -out "$signing_dir/certificate.pem"
trap - EXIT
echo "Ключ подписи Rowvi создан: $signing_dir"
