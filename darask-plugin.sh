#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [[ ${1:-} == --help ]]; then
    cat <<'HELP'
Darask Paint iopaint Linux launcher
  --setup-only  Install/validate dependencies without starting the server.
  DARASK_DATA_DIR          Override this plugin's writable data directory.
  DARASK_TORCH_BACKEND     cpu (default) or cu128 (NVIDIA CUDA 12.8).
  DARASK_DOWNLOAD_MODEL    1: download default model; 0: skip (Diffusion only).
On NixOS use `nix run .`; this script also enters the Nix environment automatically.
HELP
    exit 0
fi

if [[ -f /etc/NIXOS && ${DARASK_NIX_ENV:-} != 1 ]]; then
    cd -- "$script_dir"
    exec nix run . -- "$@"
fi

setup_only=0
if [[ ${1:-} == --setup-only ]]; then
    setup_only=1
    shift
fi
backend=${DARASK_TORCH_BACKEND:-cpu}
case "$backend" in
    cpu|cu128) ;;
    *) echo 'DARASK_TORCH_BACKEND must be cpu or cu128' >&2; exit 1 ;;
esac
data_home=${XDG_DATA_HOME:-}
if [[ $data_home != /* ]]; then data_home="$HOME/.local/share"; fi
app_dir=${DARASK_DATA_DIR:-$data_home/darask-paint-iopaint}
mkdir -p -- "$app_dir"
app_dir=$(cd -- "$app_dir" && pwd)
exec 9>"$app_dir/launcher.lock"
if ! flock -n 9; then
    echo "This plugin is already running or being installed: $app_dir" >&2
    exit 1
fi

# Use Nix's interpreter, never a downloaded FHS-linked Python on NixOS.
python_bin=${DARASK_PYTHON:-python3.12}
export UV_PYTHON_DOWNLOADS=never
export UV_PYTHON_PREFERENCE=only-system
venv="$app_dir/env"
python="$venv/bin/python"
marker="$app_dir/.darask-linux-setup"
expected="$(sha256sum "$script_dir/darask-plugin.sh" | cut -d' ' -f1);python=$(command -v "$python_bin");backend=$backend"
constraints="$app_dir/torch-constraints.txt"
printf '%s
' 'torch==2.11.0' 'torchvision==0.26.0' 'torchaudio==2.11.0' > "$constraints"

if [[ ! -x $python || ! -x $venv/bin/iopaint || $(cat "$marker" 2>/dev/null || true) != "$expected" ]]; then
    rm -f -- "$marker"
    uv venv --clear --python "$python_bin" "$venv"
    uv pip install --python "$python" --torch-backend "$backend" -c "$constraints" \
        torch torchvision 'git+https://github.com/daraskme/IOpaint@2604eade438e29a066bd6c2416bdc253e6d00bf5'
    # v2.0.0-rc2 is distributed as iopaint-ng. Verify without importing torch twice.
    "$python" -I -c "from importlib.metadata import version; assert version('iopaint-ng') == '2.0.0rc2'"
    # Never fall back to unrestricted IOpaint mode.
    COLUMNS=300 NO_COLOR=1 "$venv/bin/iopaint" start --help > "$app_dir/plugin-help.txt"
    if ! grep -q -- '--darask-plugin-mode' "$app_dir/plugin-help.txt"; then
        echo 'IOpaint does not support --darask-plugin-mode; refusing to start.' >&2
        exit 1
    fi
    printf '%s' "$expected" > "$marker"
fi
if (( setup_only )); then exit 0; fi
device=cpu
if [[ $backend == cu128 ]]; then
    "$python" -I -c 'import torch; assert torch.cuda.is_available(), "CUDA is unavailable; check your driver or use DARASK_TORCH_BACKEND=cpu"'
    device=cuda
fi
echo "IOpaint ($device): http://127.0.0.1:8423 — Ctrl+C to stop"
exec "$venv/bin/iopaint" start --model lama --device "$device" \
    --host 127.0.0.1 --port 8423 --darask-plugin-mode
