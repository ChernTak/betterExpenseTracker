# Sets up adb reverse then runs the app pointed at localhost:3000
# (dart_defines.usb.json). Requires the phone connected via USB debugging.
& "$PSScriptRoot\adb_reverse.ps1"
flutter run --dart-define-from-file=dart_defines.usb.json
