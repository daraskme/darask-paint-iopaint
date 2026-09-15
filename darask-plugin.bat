@echo off
setlocal EnableDelayedExpansion
REM ============================================================
REM  darask-paint IOpaint plugin launcher
REM  Starts a local IOpaint (fork: daraskme/IOpaint) API server
REM  for darask-paint's "AI shuufuku (IOpaint)" menu.
REM
REM  - First run: installs uv, creates a Python env, installs
REM    PyTorch (CUDA 12.8 if an NVIDIA GPU is present, else CPU)
REM    and IOpaint PINNED to the %PINNED_TAG% tag (git install --
REM    requires git on PATH; NOT "latest", see below).
REM    The env is shared with IOPaint-OneClick.bat
REM    (%LOCALAPPDATA%\IOPaint) so nothing is installed twice.
REM  - Later runs: if the installed iopaint version doesn't match
REM    %PINNED_VERSION%, it is reinstalled to the pinned tag first.
REM    Warm starts skip the two slow "iopaint ..." probes (each one
REM    imports iopaint/torch) when the pinned dist-info is present and
REM    its RECORD file is unchanged since the last successful probe.
REM  - Server: http://127.0.0.1:8423 (local only, no browser UI
REM    is opened; darask-paint talks to /api/v1/inpaint).
REM  - Requires --darask-plugin-mode support (restricted: only
REM    /api/v1/health + /api/v1/inpaint, no web UI/CORS/model-switch).
REM    This script REFUSES to start if that isn't available --
REM    there is no unrestricted-mode fallback.
REM  - IMPORTANT: %PINNED_TAG% must exist as a pushed git tag on
REM    https://github.com/%REPO% before this script's install step
REM    can succeed. Push it once daraskme/IOpaint rc2 is cut.
REM  Close this window to stop the plugin.
REM ============================================================

set "REPO=daraskme/IOpaint"
set "PINNED_TAG=v2.0.0-rc2"
set "PINNED_VERSION=2.0.0rc2"
set "APPDIR=%LOCALAPPDATA%\IOPaint"
set "VENV=%APPDIR%\env"
set "IOPAINT_EXE=%VENV%\Scripts\iopaint.exe"
set "DISTINFO=%VENV%\Lib\site-packages\iopaint-%PINNED_VERSION%.dist-info"
set "PROBE_MARKER=%VENV%\darask-plugin-probe-ok.txt"
set "PLUGIN_HOST=127.0.0.1"
set "PLUGIN_PORT=8423"
set "PLUGIN_MODE_FLAG="

if exist "%IOPAINT_EXE%" goto :check_version
goto :first_time_setup

:check_version
REM Fast path (warm start): the installer writes exactly one
REM iopaint-<version>.dist-info, so its presence for %PINNED_VERSION% is
REM equivalent to "iopaint --version" without importing the package. The
REM --darask-plugin-mode probe result is reused only while that install's
REM RECORD file (rewritten by every (re)install) is byte-for-byte the same
REM size/timestamp it had when the probe last succeeded; anything else
REM falls through to the full checks below.
if not exist "%DISTINFO%\RECORD" goto :check_version_slow
set "RECORD_STAMP="
for %%f in ("%DISTINFO%\RECORD") do set "RECORD_STAMP=%%~tf %%~zf"
set "PROBE_STAMP="
if exist "%PROBE_MARKER%" set /p PROBE_STAMP=<"%PROBE_MARKER%"
if not "!RECORD_STAMP!"=="" if "!PROBE_STAMP!"=="!RECORD_STAMP!" (
    set "PLUGIN_MODE_FLAG=--darask-plugin-mode"
    goto :run
)

:check_version_slow
set "INSTALLED_VERSION="
for /f "usebackq delims=" %%v in (`"%IOPAINT_EXE%" --version 2^>nul`) do set "INSTALLED_VERSION=%%v"
if "!INSTALLED_VERSION!"=="%PINNED_VERSION%" goto :run
echo Installed IOpaint version is "!INSTALLED_VERSION!"; pinned version is %PINNED_VERSION%.
echo Updating to the pinned version...
echo.
goto :install_iopaint

:first_time_setup
echo === darask-paint IOpaint plugin: first-time setup ===
echo Install location: %APPDIR%
echo.

where git >nul 2>nul
if not errorlevel 1 goto :have_git
echo ERROR: git is required to install the pinned IOpaint version and was not
echo        found on PATH. Install it from https://git-scm.com/downloads and
echo        re-run this script.
goto :fail
:have_git

where uv >nul 2>nul
if not errorlevel 1 goto :have_uv
echo [1/4] Installing uv package manager...
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
where uv >nul 2>nul
if errorlevel 1 (
    echo ERROR: uv installation failed. Install it manually from https://docs.astral.sh/uv/
    goto :fail
)
:have_uv

echo [2/4] Creating Python environment...
if not exist "%APPDIR%" mkdir "%APPDIR%"
uv venv "%VENV%" --python 3.12
if errorlevel 1 goto :fail

where nvidia-smi >nul 2>nul
if errorlevel 1 goto :torch_cpu
echo [3/4] NVIDIA GPU detected - installing PyTorch with CUDA 12.8...
echo       NOTE: needs a driver supporting CUDA 12.8+ (Blackwell/Ada/Ampere are fine).
uv pip install --python "%VENV%" torch torchvision --torch-backend=cu128
if errorlevel 1 (
    echo ERROR: CUDA PyTorch install failed. Update your NVIDIA driver and retry.
    goto :fail
)
goto :torch_done
:torch_cpu
echo [3/4] No NVIDIA GPU detected - installing CPU PyTorch...
uv pip install --python "%VENV%" torch torchvision --torch-backend=cpu
if errorlevel 1 goto :fail
:torch_done

echo [4/4] Installing IOpaint %PINNED_TAG% (pinned -- not "latest")...
goto :install_iopaint

:install_iopaint
REM Pinned to a specific tag on purpose: --darask-plugin-mode's safety
REM properties (CORS off, restricted routes, fixed model, DNS-rebinding
REM guard) are a security boundary, so this launcher must not silently
REM pick up whatever the newest tag happens to be.
uv pip install --python "%VENV%" "git+https://github.com/%REPO%@%PINNED_TAG%"
if errorlevel 1 (
    echo ERROR: failed to install %REPO%@%PINNED_TAG%.
    echo        Make sure that tag has been pushed to GitHub and that git is
    echo        on PATH, then re-run this script.
    goto :fail
)

echo.
echo Setup finished successfully.
echo.

:run
where nvidia-smi >nul 2>nul
if errorlevel 1 (set "DEVICE=cpu") else (set "DEVICE=cuda")

if not "!PLUGIN_MODE_FLAG!"=="" goto :probe_done

REM --darask-plugin-mode is required, not optional: sanity-check that the
REM pinned install actually has it before starting (belt-and-suspenders --
REM the version pin above should already guarantee this). COLUMNS is
REM widened for the probe because typer/rich truncates long option names
REM (mid-string, e.g. "--darask-plugin-...") when --help's output isn't a
REM real console (as is the case once piped into findstr), which would
REM otherwise make this check always miss even on a supporting install.
set "PLUGIN_MODE_FLAG="
set "COLUMNS=300"
"%IOPAINT_EXE%" start --help 2>nul | findstr /C:"--darask-plugin-mode" >nul
if not errorlevel 1 set "PLUGIN_MODE_FLAG=--darask-plugin-mode"
set "COLUMNS="
if "!PLUGIN_MODE_FLAG!"=="" (
    echo ERROR: installed IOpaint ^(pinned %PINNED_TAG%^) does not expose
    echo        --darask-plugin-mode. This launcher refuses to start in the
    echo        unrestricted normal mode, since that would expose the web UI,
    echo        CORS and model-switching APIs on this port.
    echo        Delete "%VENV%" and re-run this script to reinstall from
    echo        scratch, or report this at https://github.com/%REPO%/issues.
    goto :fail
)
if exist "%DISTINFO%\RECORD" (
    for %%f in ("%DISTINFO%\RECORD") do >"%PROBE_MARKER%" echo %%~tf %%~zf
)
:probe_done

echo Starting darask-paint IOpaint plugin (device: !DEVICE!).
echo Server: http://%PLUGIN_HOST%:%PLUGIN_PORT%  (darask-paint: "AI shuufuku (IOpaint)" menu)
echo The first run downloads the LaMa model (~200MB).
echo Close this window to stop the plugin.
"%IOPAINT_EXE%" start --model lama --device !DEVICE! --host %PLUGIN_HOST% --port %PLUGIN_PORT% !PLUGIN_MODE_FLAG!
goto :eof

:fail
echo.
echo Setup failed. See the messages above for details.
pause
exit /b 1
