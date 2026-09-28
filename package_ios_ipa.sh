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
payload_dir="$output_dir/Payload"

mkdir -p "$output_dir"
rm -rf "$payload_dir" "$output_ipa"
mkdir -p "$payload_dir"

echo "Copying $app_path to $payload_dir/Runner.app"
cp -R "$app_path" "$payload_dir/Runner.app"

find "$payload_dir" \( -name ".DS_Store" -o -name "._*" \) -delete

echo "Creating $output_ipa"
(
    cd "$output_dir"
    COPYFILE_DISABLE=1 zip -qry --symlinks "$(basename "$output_ipa")" Payload -x "*/.DS_Store" "*/._*" "__MACOSX/*"
)

echo "Created IPA: $output_ipa"
