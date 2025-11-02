@echo off
setlocal EnableDelayedExpansion

rem Edit this to your desired basename
set "APP_BASENAME=DITrix_Attendance_Scanner"

rem The script assumes you ran:
rem   flutter build apk --split-per-abi
set "OUT_DIR=build\app\outputs\apk\release"

if not exist "%OUT_DIR%" (
  echo Output dir not found: %OUT_DIR%
  echo Run: flutter build apk --split-per-abi
  exit /b 1
)

set "found=0"
for %%F in ("%OUT_DIR%\app-*-release.apk") do (
  set "fname=%%~nxF"
  set "nameNoExt=%%~nF"
  rem remove prefix "app-" and suffix "-release"
  set "abi=!nameNoExt:app-=!"
  set "abi=!abi:-release=!"
  set "newname=%APP_BASENAME%-!abi!.apk"
  echo Renaming "!fname!" -> "!newname!"
  move /Y "%%~fF" "%OUT_DIR%\!newname!" >nul 2>&1
  set "found=1"
)

if "%found%"=="0" (
  echo No split apks found matching app-*-release.apk
)

if exist "%OUT_DIR%\app-release.apk" (
  echo Renaming app-release.apk -> %APP_BASENAME%.apk
  move /Y "%OUT_DIR%\app-release.apk" "%OUT_DIR%\%APP_BASENAME%.apk" >nul 2>&1
)

echo.
echo Done. Files in %OUT_DIR%:
dir /b "%OUT_DIR%"

endlocal
exit /b 0