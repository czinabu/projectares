; Windows installer for Verge, built by .github/workflows/windows-client.yml
; with NSIS (makensis) on Linux:
;   makensis -DSRC=<folder with Verge.exe, .pck and the readme> -DICON=<.ico>
;            -DBUILD=<n> -DOUTFILE=<setup.exe> Verge.nsi
;
; It installs for the current user, into %LOCALAPPDATA%\Programs\Verge,
; where Windows puts per-user games and apps (no admin prompt). Program Files
; is left alone on purpose: it needs admin rights to write, and the game
; updates itself by replacing Verge.pck in its own folder
; (core/update/updater.gd). Saves live in %APPDATA%\Godot\app_userdata and are
; never touched by installing or uninstalling.
;
; Before the rename the game was installed as ProjectAres.exe in
; Programs\Project Ares under the uninstall key "ProjectAres". Installing over
; such a copy moves it: the old files, shortcuts and key are removed and the
; game goes into the new folder (the saves stay where they are).

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
  !define OUTFILE "Verge-Setup.exe"
!endif

!define NAME "Verge"
!define EXE "Verge.exe"
!define PACK "Verge.pck"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Verge"
; The install from before the rename (ProjectAres.exe in Programs\Project Ares).
!define OLD_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProjectAres"
!define OLD_EXE "ProjectAres.exe"
!define OLD_PACK "ProjectAres.pck"

Name "${NAME}"
OutFile "${OUTFILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${NAME}"
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
  ; Move an install from before the rename: its files go (never the saves,
  ; which are elsewhere), then its folder if that leaves it empty, then its key.
  ReadRegStr $0 HKCU "${OLD_KEY}" "InstallLocation"
  StrCmp $0 "" old_done
  Delete "$0\${OLD_EXE}"
  Delete "$0\${OLD_PACK}"
  Delete "$0\${OLD_PACK}.new"
  StrCmp $0 $INSTDIR old_key
  Delete "$0\PLAYTEST-README.txt"
  Delete "$0\BUILD.txt"
  Delete "$0\Uninstall.exe"
  RMDir "$0"
old_key:
  DeleteRegKey HKCU "${OLD_KEY}"
old_done:

  SetOutPath "$INSTDIR"
  File "${SRC}\${EXE}"
  File "${SRC}\${PACK}"
  File "${SRC}\PLAYTEST-README.txt"
  ; A pack the updater left half swapped in an older install.
  Delete "$INSTDIR\${PACK}.new"
  ; The old exe and pack, if this folder held them.
  Delete "$INSTDIR\${OLD_EXE}"
  Delete "$INSTDIR\${OLD_PACK}"
  Delete "$INSTDIR\${OLD_PACK}.new"
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
  Delete "$INSTDIR\${PACK}"
  Delete "$INSTDIR\${PACK}.new"
  Delete "$INSTDIR\PLAYTEST-README.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${NAME}.lnk"
  Delete "$SMPROGRAMS\${NAME}\${NAME}.lnk"
  Delete "$SMPROGRAMS\${NAME}\Uninstall ${NAME}.lnk"
  RMDir "$SMPROGRAMS\${NAME}"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
