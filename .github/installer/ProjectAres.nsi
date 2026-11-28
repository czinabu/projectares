; Windows installer for Verge, built by .github/workflows/windows-client.yml
; with NSIS (makensis) on Linux:
;   makensis -DSRC=<folder with ProjectAres.exe, .pck and the readme> -DICON=<.ico>
;            -DBUILD=<n> -DOUTFILE=<setup.exe> ProjectAres.nsi
;
; It installs for the current user, into %LOCALAPPDATA%\Programs\Project Ares,
; where Windows puts per-user games and apps (no admin prompt). Program Files
; is left alone on purpose: it needs admin rights to write, and the game
; updates itself by replacing ProjectAres.pck in its own folder
; (core/update/updater.gd). Saves live in %APPDATA%\Godot\app_userdata and are
; never touched by installing or uninstalling.

Unicode true
!include "MUI2.nsh"

!ifndef BUILD
  !define BUILD "0"
!endif
!ifndef SRC
  !define SRC "."
!endif
!ifndef ICON
  !define ICON "..\..\assets\branding\icon.ico"
!endif
!ifndef OUTFILE
  !define OUTFILE "ProjectAres-Setup.exe"
!endif

!define NAME "Verge"
!define EXE "ProjectAres.exe"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProjectAres"

Name "${NAME}"
OutFile "${OUTFILE}"
RequestExecutionLevel user
; The folder keeps the prototype name so an install made before the rename is
; updated in place.
InstallDir "$LOCALAPPDATA\Programs\Project Ares"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
SetCompressor /SOLID lzma
BrandingText "${NAME} build ${BUILD}"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Play ${NAME} now"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  File "${SRC}\${EXE}"
  File "${SRC}\ProjectAres.pck"
  File "${SRC}\PLAYTEST-README.txt"
  ; A pack the updater left half swapped in an older install.
  Delete "$INSTDIR\ProjectAres.pck.new"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Shortcuts from before the rename.
  Delete "$DESKTOP\Project Ares.lnk"
  Delete "$SMPROGRAMS\Project Ares\Project Ares.lnk"
  Delete "$SMPROGRAMS\Project Ares\Uninstall Project Ares.lnk"
  RMDir "$SMPROGRAMS\Project Ares"
  CreateShortcut "$DESKTOP\${NAME}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
  CreateDirectory "$SMPROGRAMS\${NAME}"
  CreateShortcut "$SMPROGRAMS\${NAME}\${NAME}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
  CreateShortcut "$SMPROGRAMS\${NAME}\Uninstall ${NAME}.lnk" "$INSTDIR\Uninstall.exe"

  ; Listed under Settings > Apps, so it uninstalls like any other game.
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${EXE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "build ${BUILD}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\${EXE}"
  Delete "$INSTDIR\ProjectAres.pck"
  Delete "$INSTDIR\ProjectAres.pck.new"
  Delete "$INSTDIR\PLAYTEST-README.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${NAME}.lnk"
  Delete "$SMPROGRAMS\${NAME}\${NAME}.lnk"
  Delete "$SMPROGRAMS\${NAME}\Uninstall ${NAME}.lnk"
  RMDir "$SMPROGRAMS\${NAME}"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
