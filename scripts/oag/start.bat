@echo off
rem XMRig for OAG: start mining Orange (OAG) on a community pool.
rem
rem It asks for your OAG address, checks its form, saves it next to this file
rem (oag-address.txt), lets you pick a pool and starts xmrig.exe.
rem It only ever needs your public address: it never asks for a recovery phrase
rem or a private key, and it downloads nothing and changes no system settings.
rem
rem Pools: keep this list in sync with "Community pools" in the Orange README,
rem   https://github.com/manh923/Orange#community-pools
rem
rem   start.bat             start mining
rem   start.bat --dry-run   print the xmrig command and exit
rem
rem   OAG_ADDRESS=oag1...   use this address instead of asking (it is not saved)
rem   OAG_POOL=1, 2 or 3    use this pool choice instead of asking

setlocal EnableExtensions DisableDelayedExpansion
set "XMRIG=%~dp0xmrig.exe"
set "ADDRFILE=%~dp0oag-address.txt"
set "DRYRUN="
if /i "%~1"=="--dry-run" set "DRYRUN=1"
cd /d "%~dp0"
setlocal EnableDelayedExpansion

title XMRig for OAG
echo XMRig for OAG
echo.

if not exist "!XMRIG!" (
    echo xmrig.exe was not found next to start.bat.
    echo Extract the whole ZIP first ^(right-click it, Extract All^), then run start.bat from that folder.
    if not defined DRYRUN goto no_xmrig
)

rem ---- address --------------------------------------------------------------

set "ADDR="
if defined OAG_ADDRESS (
    set "ADDR=!OAG_ADDRESS!"
    call :check_address
    if defined REASON goto bad_env_address
    goto have_address
)

if exist "!ADDRFILE!" (
    set /p "ADDR=" < "!ADDRFILE!"
    call :check_address
    if not defined REASON (
        echo Using the address saved in oag-address.txt: !ADDR!
        echo To use a different address, delete oag-address.txt and run start.bat again.
        goto have_address
    )
    echo oag-address.txt does not hold an OAG address: !REASON!.
)

echo Only your public address is needed. Never type your recovery phrase here.
set /a "TRIES=0"
:ask
set /a "TRIES+=1"
if !TRIES! gtr 5 goto give_up
echo.
echo Paste your OAG address (oag1...). Create one at https://wallet.oagcoin.org/
set "ADDR="
set /p "ADDR=Address: "
call :check_address
if defined REASON (
    echo That is not an OAG address: !REASON!.
    goto ask
)

if defined DRYRUN (
    echo Dry run: not saving the address.
) else (
    > "!ADDRFILE!" echo(!ADDR!
    if errorlevel 1 (
        echo Could not save the address to oag-address.txt. You will be asked again next time.
    ) else (
        echo Saved to oag-address.txt. To use a different address, delete that file.
    )
)

:have_address

rem ---- pool -----------------------------------------------------------------

set "P1=-o mine.orange.gen.nz:1920 -u !ADDR! -a rx/oag"
set "P2=-o oagnode.vslabs.co.in:1919 -u !ADDR! -a rx/oag"

echo.
echo Pick a pool:
echo   1  Orange Pool                      mine.orange.gen.nz:1920     fee 1%%, PPLNS
echo   2  VSLabs Orange Coin Mining Pool   oagnode.vslabs.co.in:1919   fee 0%%, PPLNS
echo   3  Auto: both; if one goes down, switch to the other (default)
echo Both pools are run by third parties, independently of the Orange project.

if defined OAG_POOL (
    set "POOL=!OAG_POOL!"
    echo Pool choice from OAG_POOL: !POOL!
) else (
    choice /c 123 /t 15 /d 3 /n /m "Your choice [1-3, 3 after 15 seconds]: "
    set "POOL=!errorlevel!"
    if "!POOL!"=="255" set "POOL=3"
)

if "!POOL!"=="1" (
    set "POOLS=!P1!"
) else if "!POOL!"=="2" (
    set "POOLS=!P2!"
) else if "!POOL!"=="3" (
    rem Pick the order at random each time, so neither pool gets everyone first.
    set /a "COIN=!RANDOM! %% 2"
    if "!COIN!"=="0" (
        set "POOLS=!P1! !P2!"
    ) else (
        set "POOLS=!P2! !P1!"
    )
) else (
    goto bad_pool
)

rem ---- start ----------------------------------------------------------------

set "ARGS=!POOLS! --cpu-priority 0 --pause-on-battery"

net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo Tip: run start.bat as administrator to let xmrig use large pages, 10-20%% faster.
)

echo.
echo "!XMRIG!" !ARGS!

if defined DRYRUN goto dry_run_done

echo.
"!XMRIG!" !ARGS!
set "RC=!errorlevel!"
if not "!RC!"=="0" (
    echo.
    echo xmrig stopped with exit code !RC!.
    pause
)
exit /b !RC!

rem ---- endings ---------------------------------------------------------------
rem Every early exit happens here, outside any parentheses, so that cmd /c
rem passes the exit code on.

:dry_run_done
echo Dry run: xmrig was not started.
exit /b 0

:no_xmrig
pause
exit /b 1

:bad_env_address
echo OAG_ADDRESS is not an OAG address: !REASON!.
exit /b 2

:give_up
echo No valid address was entered. Giving up.
if not defined DRYRUN pause
exit /b 2

:bad_pool
echo Unknown pool choice "!POOL!". Use 1, 2 or 3.
exit /b 2

rem ---- check_address: sets REASON when ADDR is not an OAG address -------------

:check_address
set "REASON="
call :trim
if not defined ADDR (
    set "REASON=it is empty"
    goto :eof
)
if not "!ADDR:~0,4!"=="oag1" (
    set "REASON=it must start with oag1, in lowercase"
    goto :eof
)
set "REST=!ADDR!"
set /a "LEN=0"
:count
if defined REST (
    set "REST=!REST:~1!"
    set /a "LEN+=1"
    goto count
)
if !LEN! lss 20 (
    set "REASON=it is too short"
    goto :eof
)
if !LEN! gtr 90 (
    set "REASON=it is too long"
    goto :eof
)
rem Split the rest on the allowed characters: anything left over is not allowed.
rem The leading 2 keeps a 0 at the start from being taken as the end-of-line mark.
set "BAD="
for /f "eol=0 delims=023456789acdefghjklmnpqrstuvwxyz" %%x in ("2!ADDR:~4!") do set "BAD=%%x"
if defined BAD set "REASON=after oag1 it may only use the letters and digits 023456789acdefghjklmnpqrstuvwxyz"
goto :eof

:trim
if not defined ADDR goto :eof
if "!ADDR:~0,1!"==" " (
    set "ADDR=!ADDR:~1!"
    goto trim
)
if "!ADDR:~-1!"==" " (
    set "ADDR=!ADDR:~0,-1!"
    goto trim
)
goto :eof
