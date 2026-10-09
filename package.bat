@echo off
rem BeginnerChess release package - Windows 32-bit
rem Usage: package.bat         builds, tests and writes dist\BeginnerChess-<version>-win32.zip
rem        package.bat quick   skips the tests
cd /d "%~dp0"
for /f "tokens=3" %%v in ('findstr /c:"#define CM_VERSION" modules\chessdefs.bi') do set VERSION=%%~v
set NAME=BeginnerChess-%VERSION%-win32
set OUT=dist\%NAME%

echo == BeginnerChess %VERSION%: build
if "%1"=="quick" (call build.bat) else (call build.bat test)
if errorlevel 1 goto failed
if not exist beginnerchess.exe goto failed

echo == package %OUT%
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%\data" "%OUT%\sound\effects" "%OUT%\sound\music" "%OUT%\saves" "%OUT%\docs\screenshots"
copy /y beginnerchess.exe "%OUT%\" >nul
copy /y bass.dll "%OUT%\" >nul
copy /y sqlite3.dll "%OUT%\" >nul
xcopy /e /i /q /y data\lessons "%OUT%\data\lessons" >nul
xcopy /e /i /q /y data\puzzles "%OUT%\data\puzzles" >nul
xcopy /e /i /q /y data\openings "%OUT%\data\openings" >nul
xcopy /e /i /q /y data\games "%OUT%\data\games" >nul
rem data\beginnerchess.db is not shipped: BeginnerChess builds it from famous.pgn on first start.
copy /y sound\effects\README.txt "%OUT%\sound\effects\" >nul
copy /y sound\music\README.txt "%OUT%\sound\music\" >nul
copy /y README.md "%OUT%\" >nul
copy /y LICENSE.txt "%OUT%\" >nul
copy /y docs\ARCHITECTURE.md "%OUT%\docs\" >nul
copy /y docs\ASSETS.md "%OUT%\docs\" >nul
copy /y docs\USER_GUIDE.md "%OUT%\docs\" >nul
copy /y docs\ONLINE_GUIDE.md "%OUT%\docs\" >nul
copy /y docs\PRIVACY.md "%OUT%\docs\" >nul
copy /y docs\SECURITY.md "%OUT%\docs\" >nul
for %%f in (play_classic practice review online online_game online_profile) do copy /y docs\screenshots\%%f.png "%OUT%\docs\screenshots\" >nul

powershell -NoProfile -Command "Compress-Archive -Force -Path '%OUT%' -DestinationPath 'dist\%NAME%.zip'"
if errorlevel 1 goto failed
echo == done: dist\%NAME%.zip
goto end
:failed
echo Packaging FAILED.
exit /b 1
:end
