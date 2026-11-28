@echo off
rem Runs the Verge playtest server on this PC (docs/hosting.md, "Host from a
rem PC at home"): the account service, the plaza and every launch world, each
rem a program of its own, restarted if one stops. Close this window, or press
rem Ctrl+C, to stop all of it.
rem
rem It runs the installed game, so the server is always the same version as
rem the game on this PC. To update: close this window, start the game once so
rem it updates itself, quit it, and run this again.

setlocal
set "GAME=%LOCALAPPDATA%\Programs\Project Ares\ProjectAres.exe"
set "DATA=%USERPROFILE%\VergeServer"

if not exist "%GAME%" (
	echo Could not find the game at "%GAME%".
	echo Install it first, or change GAME at the top of this file.
	pause
	exit /b 1
)
if not exist "%DATA%" mkdir "%DATA%"

echo Accounts and backups are kept in %DATA%
echo Players join this PC's public address. Forward UDP ports 24565-24567 to it.
echo.
"%GAME%" --headless -- --server --cluster --port 24565 --accounts "%DATA%\accounts"
pause