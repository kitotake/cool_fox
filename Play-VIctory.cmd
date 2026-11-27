@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "script_dir=%~dp0"
pushd "%script_dir%" >nul 2>&1
if errorlevel 1 (
  echo Could not enter the VIctory folder. 1>&2
  exit /b 1
)
if not "%~1"=="" if /i not "%~1"=="pareto-residency" if /i not "%~1"=="measure" if /i not "%~1"=="shaders" (
  echo Usage: Play-VIctory.cmd [pareto-residency^|measure^|shaders] 1>&2
  popd
  exit /b 2
)
if not defined VICTORY_GAME_DIR if exist "%~dp0..\GTA6.Xbox.v1.0.2.1\game_scarlett_master.exe" set "VICTORY_GAME_DIR=%~dp0..\GTA6.Xbox.v1.0.2.1"
if not defined VICTORY_GAME_DIR if exist "%~dp0..\gta6\game_scarlett_master.exe" set "VICTORY_GAME_DIR=%~dp0..\gta6"
if not exist "%VICTORY_GAME_DIR%\game_scarlett_master.exe" (
  echo Set VICTORY_GAME_DIR to your own dump folder containing game_scarlett_master.exe. 1>&2
  popd
  exit /b 2
)
set "runner=%~dp0victory-3d-rtx-pareto-residency.exe"
if not exist "%runner%" set "runner=%~dp0target\release\victory.exe"
if not exist "%runner%" (
  echo Extract the Windows release or run cargo build --release --locked -p victory. 1>&2
  popd
  exit /b 2
)
if not defined VICTORY_AMBIENT_AIR set "VICTORY_AMBIENT_AIR=1.5"
if not defined VICTORY_CACHE_DIR set "VICTORY_CACHE_DIR=%LOCALAPPDATA%\VIctory\cache-pareto"
if not defined VICTORY_DATA_DIR set "VICTORY_DATA_DIR=%LOCALAPPDATA%\VIctory\data-pareto"
if not defined VICTORY_PIPELINE_BOOK set "VICTORY_PIPELINE_BOOK=1"
if not defined VICTORY_TEXTURE_NO_WAIT set "VICTORY_TEXTURE_NO_WAIT=1"
if not defined VICTORY_RELAY set "VICTORY_RELAY=2"
if not defined VICTORY_WIDE_BACK set "VICTORY_WIDE_BACK=1"
if not defined VICTORY_CARD_REHASH_RUNS set "VICTORY_CARD_REHASH_RUNS=1"
if not defined VICTORY_JOIN_COPIES set "VICTORY_JOIN_COPIES=1"
if not defined VICTORY_INDIRECT_WINDOW set "VICTORY_INDIRECT_WINDOW=1"
if not defined VICTORY_RELAY_COPY set "VICTORY_RELAY_COPY=1"
if not defined VICTORY_CARD_STEPS set "VICTORY_CARD_STEPS=2"
if not defined VICTORY_INDIRECT_BATCH set "VICTORY_INDIRECT_BATCH=2"
if not defined VICTORY_MAP_THREADS set "VICTORY_MAP_THREADS=1"
if not defined VICTORY_CARD_AWAKE set "VICTORY_CARD_AWAKE=1"
if not defined VICTORY_SHOW_AFTER set "VICTORY_SHOW_AFTER=1"
if not defined VICTORY_AMBIENT set "VICTORY_AMBIENT=0.8"
if not defined VICTORY_THIN set "VICTORY_THIN=1"
if not defined VICTORY_JOIN_PARTS set "VICTORY_JOIN_PARTS=8"
if not defined VICTORY_UPLOAD_AHEAD set "VICTORY_UPLOAD_AHEAD=1"
if not defined VICTORY_LEVELS_ON_DEMAND set "VICTORY_LEVELS_ON_DEMAND=1"
if not defined VICTORY_CARD_BUFFERS_MIN_KB set "VICTORY_CARD_BUFFERS_MIN_KB=64"
if not defined VICTORY_LOG if not defined RUST_LOG set "VICTORY_LOG=warn"
if /i "%~1"=="shaders" goto shaders
if exist "%VICTORY_CACHE_DIR%\pipelines\known-pipelines.bin" (
  echo Warming previously used host pipelines...
  "%runner%" warm --used --jobs 2
  if errorlevel 1 (
    popd
    exit /b 1
  )
)
if /i "%~1"=="measure" goto measure
"%runner%" run "%VICTORY_GAME_DIR%\game_scarlett_master.exe" --console series-s --execute
set "run_error=%errorlevel%"
popd
exit /b %run_error%

:shaders
if not exist "%~dp0debugs" mkdir "%~dp0debugs"
if not exist "%~dp0debugs" (
  echo Could not create the debugs folder. 1>&2
  popd
  exit /b 1
)
set "VICTORY_LOG=info"
echo.>>"%~dp0debugs\shaders-precompile.log"
echo ===== %date% %time% =====>>"%~dp0debugs\shaders-precompile.log"
echo Precompiling shaders from "%VICTORY_GAME_DIR%"...
"%runner%" shaders "%VICTORY_GAME_DIR%" >>"%~dp0debugs\shaders-precompile.log" 2>&1
set "run_error=%errorlevel%"
>>"%~dp0debugs\shaders-precompile.log" echo Shader precompile exit code: %run_error%
echo Log saved to "%~dp0debugs\shaders-precompile.log"
popd
exit /b %run_error%

:measure
if not exist "%~dp0debugs" mkdir "%~dp0debugs"
if not exist "%~dp0debugs" (
  echo Could not create the debugs folder. 1>&2
  popd
  exit /b 1
)
set "VICTORY_LOG=info"
echo.>>"%~dp0debugs\victory-measure.log"
echo ===== %date% %time% =====>>"%~dp0debugs\victory-measure.log"
"%runner%" run "%VICTORY_GAME_DIR%\game_scarlett_master.exe" --console series-s --execute >>"%~dp0debugs\victory-measure.log" 2>&1
set "run_error=%errorlevel%"
popd
exit /b %run_error%
