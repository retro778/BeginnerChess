@echo off
rem BeginnerChess build script - Windows 32-bit
rem Requires the 32-bit FreeBASIC compiler (fbc32.exe, or fbc.exe from a win32 package) on PATH.
rem Set FBC to override, e.g.:  set FBC=C:\FreeBASIC\fbc32.exe
rem Usage: build.bat          build the program and the tests
rem        build.bat test     build, then run the tests

cd /d "%~dp0"
if "%FBC%"=="" if exist "C:\Users\ronen\Desktop\Shared\freebasic\FreeBASIC-1.10.1-winlibs-gcc-9.3.0\fbc32.exe" set FBC=C:\Users\ronen\Desktop\Shared\freebasic\FreeBASIC-1.10.1-winlibs-gcc-9.3.0\fbc32.exe
if "%FBC%"=="" set FBC=fbc32
set FLAGS=-w all -gen gcc -O 2 -mt
set CORE=modules\rules.bas modules\notation.bas modules\game.bas modules\engine.bas modules\openings.bas modules\pgn.bas modules\savegame.bas modules\progress.bas modules\lessons.bas modules\puzzles.bas modules\db.bas modules\famous.bas modules\profile.bas modules\career.bas modules\coach.bas modules\analysis.bas
set GUI=modules\audio.bas modules\clipboard.bas modules\files.bas modules\gfx.bas modules\pieces.bas modules\board.bas modules\gui.bas modules\explain.bas modules\settings.bas modules\menu.bas modules\play.bas modules\boardctl.bas modules\learn.bas modules\famousui.bas modules\profileui.bas modules\tournamentui.bas modules\review.bas modules\analyzeui.bas modules\json.bas modules\net.bas modules\online.bas modules\onlineui.bas modules\tokenstore.bas

echo Building beginnerchess.exe...
%FBC% %FLAGS% -s gui beginnerchess.bas %CORE% %GUI% -x beginnerchess.exe
if errorlevel 1 goto failed

echo Building tests...
%FBC% %FLAGS% tests\test_core.bas %CORE% -x tests\test_core.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_engine.bas %CORE% -x tests\test_engine.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_pgn.bas %CORE% -x tests\test_pgn.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_audio.bas modules\audio.bas modules\settings.bas -x tests\test_audio.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_content.bas %CORE% -x tests\test_content.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_famous.bas %CORE% -x tests\test_famous.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_profile.bas %CORE% -x tests\test_profile.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_coach.bas %CORE% -x tests\test_coach.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_gfx.bas modules\gfx.bas -x tests\test_gfx.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_json.bas modules\json.bas -x tests\test_json.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_tokenstore.bas modules\tokenstore.bas -x tests\test_tokenstore.exe
if errorlevel 1 goto failed
%FBC% %FLAGS% tests\test_online.bas modules\online.bas modules\net.bas modules\json.bas -x tests\test_online.exe
if errorlevel 1 goto failed

if not "%1"=="test" goto done
tests\test_core.exe
if errorlevel 1 goto testfailed
tests\test_engine.exe
if errorlevel 1 goto testfailed
tests\test_pgn.exe
if errorlevel 1 goto testfailed
tests\test_audio.exe
if errorlevel 1 goto testfailed
tests\test_content.exe
if errorlevel 1 goto testfailed
tests\test_famous.exe
if errorlevel 1 goto testfailed
rem The game library must also work without SQLite.
set BEGINNERCHESS_SQLITE=%TEMP%\no_such_sqlite.dll
tests\test_famous.exe --nodb
set RESULT=%ERRORLEVEL%
set BEGINNERCHESS_SQLITE=
if not "%RESULT%"=="0" goto testfailed
tests\test_profile.exe
if errorlevel 1 goto testfailed
tests\test_coach.exe
if errorlevel 1 goto testfailed
tests\test_gfx.exe
if errorlevel 1 goto testfailed
tests\test_json.exe
if errorlevel 1 goto testfailed
tests\test_tokenstore.exe
if errorlevel 1 goto testfailed
:done
echo Done.
goto end

:testfailed
echo TESTS FAILED - see the FAIL lines above.
exit /b 1

:failed
echo BUILD FAILED.
exit /b 1
:end
