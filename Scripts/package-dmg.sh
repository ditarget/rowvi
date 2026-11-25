set -euo pipefail

app=$1
image=$2
if [[ -e $image ]]; then
    echo "Образ уже существует: $image" >&2
    exit 1
fi

stage=$(mktemp -d "$(dirname "$image")/.dmg.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/contents"
ditto "$app" "$stage/contents/Rowvi.app"
ln -s /Applications "$stage/contents/Applications"

temporary_image="$stage/Rowvi.dmg"
hdiutil create -quiet -fs HFS+ -format UDZO -volname Rowvi -srcfolder "$stage/contents" "$temporary_image"
hdiutil verify -quiet "$temporary_image"
mv -n "$temporary_image" "$image"
if [[ -e $temporary_image ]]; then
    echo "Образ уже существует: $image" >&2
    exit 1
fi
