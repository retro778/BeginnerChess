@echo off
rem BeginnerChess - checks the Windows network code (WinHTTP) against public test servers.
rem Needs an Internet connection. Build first with: build.bat
cd /d "%~dp0\.."
if not exist tests\test_online.exe (
    echo tests\test_online.exe is missing - run build.bat first.
    exit /b 1
)
set FAILED=0
echo.
echo 1. A secure WebSocket connection and a message round trip:
tests\test_online.exe --echo wss://echo.websocket.org/
if errorlevel 1 set FAILED=1
echo.
echo 2. Certificates that must be refused (self-signed, expired, wrong host name):
tests\test_online.exe --expect-fail wss://self-signed.badssl.com/
if errorlevel 1 set FAILED=1
tests\test_online.exe --expect-fail wss://expired.badssl.com/
if errorlevel 1 set FAILED=1
tests\test_online.exe --expect-fail wss://wrong.host.badssl.com/
if errorlevel 1 set FAILED=1
echo.
echo 3. Cancelling a connection that hangs must not freeze the program:
tests\test_online.exe --cancel-test -
if errorlevel 1 set FAILED=1
echo.
if "%FAILED%"=="1" (
    echo ONLINE CHECK FAILED - please send the output above.
    exit /b 1
)
echo All online checks passed.
