# Forwards the phone's localhost:3000 to the PC's localhost:3000 over USB,
# so api_endpoints.dart's baseUrl (http://localhost:3000) works on any
# network without editing an IP address. Run this once per USB connection
# (e.g. after reconnecting the cable) before `flutter run`.
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { $adb = "adb" }

& $adb reverse tcp:3000 tcp:3000
