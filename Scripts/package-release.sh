set -euo pipefail

source_app=$1
sparkle_bin=$2
repo_url=https://github.com/ditarget/rowvi
source_plist="$source_app/Contents/Info.plist"
version=$(plutil -extract CFBundleShortVersionString raw "$source_plist")
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

expected_key=$(plutil -extract SUPublicEDKey raw "$source_plist")
if ! public_key=$("$sparkle_bin/generate_keys" --account rowvi -p) ||
    [[ $public_key != "$expected_key" ]]; then
    echo "В Связке ключей отсутствует оригинальный ключ Sparkle для Rowvi" >&2
    exit 1
fi

stage=$(mktemp -d .build/releases/.stage.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT
app="$stage/Rowvi.app"
assets="$stage/$tag"
mkdir "$assets"
ditto "$source_app" "$app"

plist="$app/Contents/Info.plist"
plutil -insert SUFeedURL -string "$repo_url/releases/latest/download/appcast.xml" "$plist"
plutil -insert SUEnableAutomaticChecks -bool YES "$plist"
plutil -insert SUAutomaticallyUpdate -bool YES "$plist"
plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$plist"
plutil -insert SURequireSignedFeed -bool YES "$plist"

bash Scripts/sign-app.sh "$app"
codesign --verify --deep --strict -R="$(cat Resources/ReleaseSigningRequirement.txt)" "$app"

archive="$assets/Rowvi-$tag.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
"$sparkle_bin/generate_appcast" --account rowvi --maximum-deltas 0 \
    --download-url-prefix "$repo_url/releases/download/$tag/" "$assets"
signature=$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$assets/appcast.xml")
xcrun --sdk macosx swift Scripts/verify-release.swift "$expected_key" "$assets/appcast.xml" "$archive" "$signature"

mv -n "$assets" .build/releases/
if [[ -e $assets ]]; then
    echo "Релиз уже собран: $output" >&2
    exit 1
fi
echo "Готово к публикации: $output"
