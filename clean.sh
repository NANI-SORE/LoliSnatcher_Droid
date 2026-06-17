flutter clean
flutter pub get
cd ios
rm Podfile.lock
rm -rf Pods
pod deintegrate
pod install