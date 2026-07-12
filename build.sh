#!/bin/bash

source scripts/select.sh

selected_item=0
menu_items=("Testing" "Github" "Github (No GMS/Cronet)" "Store")
title="Select a build type (arrow keys to select, enter to confirm):"
forced_network_arg=""

if [ -z "$1" ]; then
    run_menu "$title" "$selected_item" "${menu_items[@]}"
    menu_result="$?"
else
    case "$1" in
        "testing" | "test" | "debug")
            menu_result=0
            ;;
        "github" | "gh")
            menu_result=1
            ;;
        "github-nocronet" | "github-no-cronet" | "github-foss" | "gh-nocronet" | "gh-no-cronet" | "gh-foss" | "foss" | "nocronet" | "no-cronet")
            menu_result=2
            forced_network_arg="no-cronet"
            ;;
        "test-nocronet" | "test-no-cronet" | "testing-nocronet" | "testing-no-cronet")
            menu_result=0
            forced_network_arg="no-cronet"
            ;;
        "store" | "release")
            menu_result=3
            ;;
        *)
            echo "Invalid option: $1" >&2
            exit 1
            ;;
    esac
fi

echo

build_arg="LS_IS_TESTING=true"
build_desc="Testing"
build_modes=("apk --split-per-abi")
build_extras="--dart-define-from-file=./config/secrets.json"
suffix="test"
case "$menu_result"
in
    0)
        build_arg="LS_IS_TESTING=true"
        build_desc="Testing"
        build_modes=("apk --split-per-abi")
        suffix="test"
        ;;
    1)
        build_arg="LS_IS_STORE=false"
        build_desc="Github"
        build_modes=("apk --split-per-abi")
        suffix="github"
        ;;
    2)
        build_arg="LS_IS_STORE=false"
        build_desc="Github (No GMS/Cronet)"
        suffix="github"
        forced_network_arg="${forced_network_arg:-no-cronet}"
        ;;
    3)
        build_arg="LS_IS_STORE=true"
        build_desc="Store"
        build_modes=("appbundle" "apk --split-per-abi")
        suffix="store"
        ;;
esac

network_arg="${2:-${forced_network_arg:-${LS_NETWORK_STACK:-cronet-gms}}}"
network_desc="Cronet (Google Play Services)"
network_suffix=""
cronet_define="LS_ENABLE_CRONET=true"
cronet_no_play_define=""
use_native_dio_stub=false

case "$network_arg" in
    "cronet" | "gms" | "cronet-gms")
        ;;
    "nogms" | "no-gms" | "embedded" | "cronet-embedded")
        network_desc="Cronet (embedded, no Google Play Services)"
        network_suffix="_nogms"
        cronet_no_play_define="--dart-define=cronetHttpNoPlay=true"
        ;;
    "nocronet" | "no-cronet" | "foss")
        network_desc="Dart IO HTTP (no native_dio_adapter/Cronet)"
        network_suffix="_nocronet"
        cronet_define="LS_ENABLE_CRONET=false"
        use_native_dio_stub=true
        ;;
    *)
        echo "Invalid network stack: $network_arg" >&2
        echo "Allowed values: cronet-gms, cronet-embedded, no-cronet" >&2
        exit 1
        ;;
esac

suffix="${suffix}${network_suffix}"

clear

echo "Doing a [$build_desc] build with [$network_desc]"
echo "Build command: flutter build [$build_modes] --dart-define=$build_arg --dart-define=$cronet_define $cronet_no_play_define $build_extras"
# Generate empty secret vars config if it's not there
sh gen_config.sh

overrides_file="pubspec_overrides.yaml"
overrides_backup=""
pubspec_lock_backup=""
package_config_backup=""
flutter_plugins_backup=""
flutter_plugins_dependencies_backup=""
created_native_dio_override=false

restore_pubspec_overrides() {
    if [ -n "$overrides_backup" ]; then
        mv "$overrides_backup" "$overrides_file"
    elif [ "$created_native_dio_override" = true ]; then
        rm -f "$overrides_file"
    fi

    if [ -n "$pubspec_lock_backup" ]; then
        mv "$pubspec_lock_backup" "pubspec.lock"
    fi
    if [ -n "$package_config_backup" ]; then
        mv "$package_config_backup" ".dart_tool/package_config.json"
    fi
    if [ -n "$flutter_plugins_backup" ]; then
        mv "$flutter_plugins_backup" ".flutter-plugins"
    fi
    if [ -n "$flutter_plugins_dependencies_backup" ]; then
        mv "$flutter_plugins_dependencies_backup" ".flutter-plugins-dependencies"
    fi
}

if [ "$use_native_dio_stub" = true ]; then
    if [ -f "$overrides_file" ]; then
        overrides_backup="${overrides_file}.build_backup"
        mv "$overrides_file" "$overrides_backup"
    fi

    if [ -f "pubspec.lock" ]; then
        pubspec_lock_backup="pubspec.lock.build_backup"
        cp "pubspec.lock" "$pubspec_lock_backup"
    fi
    if [ -f ".dart_tool/package_config.json" ]; then
        package_config_backup=".dart_tool/package_config.json.build_backup"
        cp ".dart_tool/package_config.json" "$package_config_backup"
    fi
    if [ -f ".flutter-plugins" ]; then
        flutter_plugins_backup=".flutter-plugins.build_backup"
        cp ".flutter-plugins" "$flutter_plugins_backup"
    fi
    if [ -f ".flutter-plugins-dependencies" ]; then
        flutter_plugins_dependencies_backup=".flutter-plugins-dependencies.build_backup"
        cp ".flutter-plugins-dependencies" "$flutter_plugins_dependencies_backup"
    fi

    cat > "$overrides_file" << EOF
dependency_overrides:
  native_dio_adapter:
    path: tool/stubs/native_dio_adapter
EOF
    created_native_dio_override=true
    trap restore_pubspec_overrides EXIT
fi

# Prefer the project-pinned FVM SDK, then fall back to fvm/global flutter.
if [ -x "./.fvm/flutter_sdk/bin/flutter" ]; then
    flutter_cmd="./.fvm/flutter_sdk/bin/flutter"
elif command -v fvm &> /dev/null; then
    flutter_cmd="fvm flutter"
else
    flutter_cmd="flutter"
fi

if ! $flutter_cmd pub get ; then
    echo "Build failed"
    exit 1
fi

for mode in "${build_modes[@]}"; do
    if $flutter_cmd build $mode --release --dart-define=$build_arg --dart-define=$cronet_define $cronet_no_play_define $build_extras ; then
        echo "Build succeeded"
    else
        echo "Build failed"
        exit 1
    fi
done

get_version_and_build() {
    version_and_build=$(grep "version:" pubspec.yaml | awk '{print $2}')
    IFS='+' read -ra version_build_array <<< "$version_and_build"
    version="${version_build_array[0]}"
    build="${version_build_array[1]}"
}
get_version_and_build

has_build_mode() {
    local expected="$1"
    local mode
    for mode in "${build_modes[@]}"; do
        if [ "$mode" = "$expected" ]; then
            return 0
        fi
    done
    return 1
}

if has_build_mode "appbundle"; then
    src_aab="build/app/outputs/bundle/release/app-release.aab"
    dest_aab="build/app/outputs/bundle/release/LoliSnatcher_${version}_${build}_appbundle_${suffix}.aab"
    cp "$src_aab" "$dest_aab"

    echo
    echo "=> Built AAB: LoliSnatcher_${version}_${build}_appbundle_${suffix}.aab"
fi

if has_build_mode "apk --split-per-abi"; then
    srcv8_apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    destv8_apk="build/app/outputs/flutter-apk/LoliSnatcher_${version}_${build}_arm64-v8a_${suffix}.apk"
    cp "$srcv8_apk" "$destv8_apk"

    srcv7_apk="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
    destv7_apk="build/app/outputs/flutter-apk/LoliSnatcher_${version}_${build}_armeabi-v7a_${suffix}.apk"
    cp "$srcv7_apk" "$destv7_apk"

    src64_apk="build/app/outputs/flutter-apk/app-x86_64-release.apk"
    dest64_apk="build/app/outputs/flutter-apk/LoliSnatcher_${version}_${build}_x86_64_${suffix}.apk"
    cp "$src64_apk" "$dest64_apk"

    echo
    echo "=> Built APKs: LoliSnatcher_${version}_${build}_[arch]_${suffix}.apk"
fi

if has_build_mode "apk"; then
    src_apk="build/app/outputs/flutter-apk/app-release.apk"
    dest_apk="build/app/outputs/flutter-apk/LoliSnatcher_${version}_${build}_${suffix}.apk"
    cp "$src_apk" "$dest_apk"

    echo
    echo "=> Built APK: LoliSnatcher_${version}_${build}_${suffix}.apk"
fi
