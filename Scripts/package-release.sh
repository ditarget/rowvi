set -euo pipefail

: "${SIGN_IDENTITY:?Укажите имя или SHA-1 сертификата Developer ID Application}"
: "${NOTARY_PROFILE:?Укажите профиль notarytool из Связки ключей}"

source_app=$1
sparkle_bin=$2
repo_url=https://github.com/ditarget/rowvi
version=$(plutil -extract CFBundleShortVersionString raw "$source_app/Contents/Info.plist")
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "CFBundleShortVersionString должен быть в формате X.Y.Z" >&2
    exit 1
fi

tag=v$version
mkdir -p .build/releases
output=".build/releases/$tag"
if [[ -e $output ]]; then
    echo "Релиз уже собран: $output" >&2
    exit 1
fi

if ! public_key=$("$sparkle_bin/generate_keys" --account rowvi -p) ||
    [[ ! $public_key =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "Выполните make sparkle-keys, чтобы настроить ключ обновлений Rowvi" >&2
    exit 1
fi

stage=$(mktemp -d .build/releases/.stage.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT
app="$stage/Rowvi.app"
assets="$stage/assets"
mkdir "$assets"
ditto "$source_app" "$app"

plist="$app/Contents/Info.plist"
plutil -insert SUFeedURL -string "$repo_url/releases/latest/download/appcast.xml" "$plist"
plutil -insert SUPublicEDKey -string "$public_key" "$plist"
plutil -insert SUEnableAutomaticChecks -bool YES "$plist"
plutil -insert SUAutomaticallyUpdate -bool YES "$plist"
plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$plist"
plutil -insert SURequireSignedFeed -bool YES "$plist"

framework="$app/Contents/Frameworks/Sparkle.framework"
sparkle="$framework/Versions/Current"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$sparkle/Autoupdate" "$sparkle/Updater.app" \
    "$sparkle/XPCServices/Downloader.xpc" "$sparkle/XPCServices/Installer.xpc" \
    "$framework" "$app"

codesign --verify --deep --strict \
    -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/notarization.zip"
xcrun notarytool submit "$stage/notarization.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"

archive="$assets/Rowvi-$tag.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
"$sparkle_bin/generate_appcast" --account rowvi --maximum-deltas 0 \
    --download-url-prefix "$repo_url/releases/download/$tag/" "$assets"
signature=$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$assets/appcast.xml")
"$sparkle_bin/sign_update" --account rowvi --verify "$assets/appcast.xml"
"$sparkle_bin/sign_update" --account rowvi --verify "$archive" "$signature"

mv "$assets" "$output"
echo "Готово к публикации: $output"
