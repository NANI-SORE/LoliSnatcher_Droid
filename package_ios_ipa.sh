#!/bin/bash

set -euo pipefail

default_app_path="build/ios/iphoneos/Runner.app"
fallback_app_path="build/ios/Release-iphoneos/Runner.app"

app_path="${1:-$default_app_path}"

if [ ! -d "$app_path" ] && [ -z "${1:-}" ] && [ -d "$fallback_app_path" ]; then
    app_path="$fallback_app_path"
fi

if [ ! -d "$app_path" ]; then
    echo "Runner.app not found: $app_path" >&2
    echo "Usage: $0 [path/to/Runner.app] [path/to/Payload.ipa]" >&2
    exit 1
fi

if [ "$(basename "$app_path")" != "Runner.app" ]; then
    echo "Expected a Runner.app directory, got: $app_path" >&2
    exit 1
fi

output_ipa="${2:-$(dirname "$app_path")/Payload.ipa}"
output_dir="$(dirname "$output_ipa")"

mkdir -p "$output_dir"
app_path="$(cd "$app_path" && pwd -P)"
output_dir="$(cd "$output_dir" && pwd -P)"
output_ipa="$output_dir/$(basename "$output_ipa")"
case "$output_ipa" in
    "$app_path"|"$app_path"/*)
        echo "The IPA output must be outside Runner.app" >&2
        exit 1
        ;;
esac
case "$output_ipa" in
    *.ipa) ;;
    *) echo "Output must have an .ipa extension: $output_ipa" >&2; exit 1 ;;
esac
if [ -L "$output_ipa" ] || { [ -e "$output_ipa" ] && [ ! -f "$output_ipa" ]; }; then
    echo "Output must be a regular file: $output_ipa" >&2
    exit 1
fi

# Own a unique staging directory. Never remove a caller's existing Payload.
staging_dir="$(mktemp -d "$output_dir/.ios-ipa.XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT
payload_dir="$staging_dir/Payload"
mkdir -p "$payload_dir"

echo "Copying $app_path to $payload_dir/Runner.app"
cp -R "$app_path" "$payload_dir/Runner.app"

find "$payload_dir" \( -name ".DS_Store" -o -name "._*" \) -delete

echo "Creating $output_ipa"
(
    cd "$staging_dir"
    COPYFILE_DISABLE=1 zip -qry --symlinks archive.ipa Payload -x "*/.DS_Store" "*/._*" "__MACOSX/*"
)
mv -f -- "$staging_dir/archive.ipa" "$output_ipa"

echo "Created IPA: $output_ipa"
