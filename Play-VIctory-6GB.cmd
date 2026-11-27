@echo off
rem Launcher for 6 GB cards (GTX 1660 Super). Untested: it only sets existing
rem switches, then runs Play-VIctory.cmd (which keeps any value already set here,
rem since it only sets what is not defined).
setlocal EnableExtensions

rem Display size reported to the title. Without this the project reports 3840x2160.
rem Try 1280x720 if 1920x1080 is still too slow. Whether the title lowers its own
rem render size for this is not verified: compare fps with the measure command.
if not defined VICTORY_DISPLAY_MODE set "VICTORY_DISPLAY_MODE=1920x1080"

rem Keep host texture copies to 70 percent of the card budget (default 90).
if not defined VICTORY_TEXTURE_ROOM_PERCENT set "VICTORY_TEXTURE_ROOM_PERCENT=70"
rem Smaller texture upload per frame (MB) to limit memory spikes.
if not defined VICTORY_TEXTURE_STAGE_MB set "VICTORY_TEXTURE_STAGE_MB=32"
rem Hard cap on host texture copies (MB). Lower it if the driver spills to RAM.
if not defined VICTORY_TEXTURE_BUDGET_MB set "VICTORY_TEXTURE_BUDGET_MB=3000"
call "%~dp0Play-VIctory.cmd" %*
exit /b %errorlevel%
