# VIctory on an RX 7900 XTX

## Run the codec_d Windows build

Download and extract the Windows x64 ZIP from the [private releases](https://github.com/codec-d/cool_fox/releases/latest). Open PowerShell in the extracted folder and point the launcher at your own complete Xbox dump.

```powershell
$env:VICTORY_GAME_DIR = 'D:\Games\MyDump'
.\Play-VIctory.cmd pareto-residency
```

The launcher selects Series S and the RTX-tested residency settings. It looks for a game dump in the adjacent `GTA6.Xbox.v1.0.2.1` or `gta6` folder; set `VICTORY_GAME_DIR` for another location. Cache and save data go under `%LOCALAPPDATA%\VIctory\cache-pareto` and `%LOCALAPPDATA%\VIctory\data-pareto`; set `VICTORY_CACHE_DIR` or `VICTORY_DATA_DIR` to use other locations outside the checkout. Windows x64, an AVX2 CPU, and a Direct3D 12 GPU with shader model 6.6 and mesh shader support are required.

The first launch records the title pipelines it uses. On later launches, the
launcher prewarms those pipelines with two worker processes before starting the
game, which can reduce cold-pipeline stalls. This does not guarantee a higher
steady-state frame rate; the warm-up is skipped until a run has recorded a
pipeline book.

For a one-off performance log, run `Play-VIctory.cmd measure`. It enables
info-level frame timings and appends the output to `debugs\victory-measure.log`
without changing the game's graphics settings.

To precompile the shaders found in your configured game dump and save the
report, run `Play-VIctory.cmd shaders`. It creates `debugs` when needed and
appends the output to `debugs\shaders-precompile.log`. This can take several
minutes; the compiled shaders are stored in the configured cache.

To compare two runs on the same scene, run `scripts\bench.ps1`. It starts
`Play-VIctory.cmd measure`, keeps only what that run appended to
`debugs\victory-measure.log`, samples memory while the title runs and writes
`log.txt`, `system.csv` and `summary.txt` under `bench-results\` (median/p95/p99
ms per frame, preparing against GPU wait, dropped draws, pipelines being made,
memory-pressure events). `-Set VICTORY_JOIN_PARTS=4` changes one setting for a
run; `-Analyze debugs\victory-measure.log` sums up the last session of an
existing log. It does not change the game's settings or the engine.

To build from this checkout, install the pinned Rust toolchain and the MSVC C++ build tools with a Windows SDK, then run `cargo build --release --locked -p victory`. The same launcher finds `target\release\victory.exe`. The sections below describe the upstream AMD fork and its separate launcher.

A fork of [VIctory](https://github.com/Marvisak/VIctory), a compatibility layer
that runs an Xbox Series title natively on Windows from files the user supplies.
This one is about **speed on AMD RDNA 3**: the world at 30 frames a second on
one PC, without giving up the picture. It is not there yet.

**This repository contains no game files, code or assets.** You need your own
copy of the game. It is not affiliated with or endorsed by the game's developer
or publisher.

## Where it stands (2026-11-25)

Tested on one machine only: Windows 11, Intel i9-12900K, 64 GB RAM, Radeon
RX 7900 XTX, 1440p, the Series X profile.

| | |
|---|---|
| Menus, videos, loading screens | 30 fps |
| Prologue, indoors | 50-75 ms a frame (13-20 fps) |
| First mission with the boat | 46-53 ms (19-22 fps) |
| Street chase with many cars and people | 100-165 ms (6-10 fps), single frames far longer |
| Outdoors on foot, the camp | 60-90 ms |
| Flying | 42-57 ms |
| Longest session so far | 41 minutes, no crash |
| Memory | 40-46 GB of private memory: **64 GB of RAM recommended** |

It started at 280 ms a frame in the same scenes two days earlier.

What is known to be wrong:

- Trees, plants and far buildings flicker outdoors in some places.
- Rooms with little direct light are too dark without `-RayTracing`.
- Textures of what just came into view appear late while the title streams.
- The first run with a new driver or a new build stutters while the driver makes
  pipelines (`victory warm` makes them ahead).
- Recording a frame in the world makes the title's own watchdog end it.

## How to run it

You need Windows 10/11 x64, a CPU with AVX2, a Direct3D 12 GPU with shader
model 6.6 and mesh shaders, Rust (the toolchain is pinned), the MSVC build
tools, and your own dump of the title.

```powershell
git clone https://github.com/avatarmanz/VIctory-7900XTX
cd VIctory-7900XTX
copy victory.example.toml victory.toml      # then set your paths, outside this folder
cargo build --locked --profile diag -p victory --features diagnostics
scripts\play.ps1 -Exe <path of your copy's executable>
```

`scripts\play.ps1 -Safe` leaves out the newest, faster ways; try it first when
something is wrong. `-RayTracing` turns the title's ray-traced indirect light on.

Before the first run, ahead of time (both can be stopped and go on later):

```powershell
target\diag\victory.exe shaders <the shader archives>   # every shader translated, minutes
target\diag\victory.exe warm --used                     # pipelines earlier runs drew with, for a new driver or build
```

Commands, debugging switches and upstream's own description:
[docs/README-fxceless.md](docs/README-fxceless.md). Every `VICTORY_...` switch is
described in a comment where it is read.

## Command reference

### Start from PowerShell

Open PowerShell in the repository folder.

```powershell
# Enter the checkout
Set-Location 'C:\..\..\..\..\cool_fox'

# Normal Pareto launch
.\Play-VIctory.cmd pareto-residency

# Launch and append frame timings to debug\victory-measure.log
.\Play-VIctory.cmd measure

# Install the Git hooks used by this repository
cargo xtask install-hooks
```

`pareto-residency` is the default recommended settings profile. The argument
`measure` enables info-level logging but otherwise keeps the same graphics
settings.

### Choose game, cache and save folders

```powershell
$env:VICTORY_GAME_DIR = 'D:\Games\MyDump'
$env:VICTORY_CACHE_DIR = 'D:\VIctory\cache'
$env:VICTORY_DATA_DIR = 'D:\VIctory\data'

# Optional: use a particular configuration file
$env:VICTORY_CONFIG = 'D:\VIctory\victory.toml'
```

The game executable must be
`game_scarlett_master.exe`. The launcher can find dumps below the adjacent
`GTA6.Xbox.v1.0.2.1` or `gta6` folders.

### Build

```powershell
# Standard release build
cargo build --release --locked -p victory

# Diagnostics build with frame capture and replay support
cargo build --profile diag --locked -p victory --features diagnostics

# Run both in sequence
cargo build --release --locked -p victory
cargo build --profile diag --locked -p victory --features diagnostics
```

The binaries are generated at:

```text
target\release\victory.exe
target\diag\victory.exe
```

### Run a title directly

```powershell
# Release build, Series X
.\target\release\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-x

# Release build, Series S
.\target\release\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-s

# Diagnostics build
.\target\diag\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-s

# Bind and inspect the executable without starting the title
.\target\release\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --console series-s

# Pass arguments to the title
.\target\release\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --execute -- --some-title-option
```

`--unimplemented zero` replaces unimplemented calls with zero. `--strict`
disables host pass-through. `trap` is the default behavior for
unimplemented calls.

```powershell
.\target\release\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-s --unimplemented zero
.\target\release\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-s --strict
```

The same title can be started from `cargo run`, which builds or uses the
current development state and then launches the executable:

```powershell
cargo run -p victory -- run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-s
cargo run -p victory --features diagnostics --profile diag -- run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-s
```

### Run through the PowerShell launcher

```powershell
# Normal settings
.\scripts\play.ps1 -Exe 'D:\Games\MyDump\game_scarlett_master.exe'

# Safer settings, without the newest performance paths
.\scripts\play.ps1 -Safe -Exe 'D:\Games\MyDump\game_scarlett_master.exe'

# Enable ray-traced indirect light
.\scripts\play.ps1 -RayTracing -Exe 'D:\Games\MyDump\game_scarlett_master.exe'

# Use the release binary instead of the diagnostics binary
.\scripts\play.ps1 -Build release -Exe 'D:\Games\MyDump\game_scarlett_master.exe'

# Override additional environment settings
.\scripts\play.ps1 -Exe 'D:\Games\MyDump\game_scarlett_master.exe' -More @{
    VICTORY_PANEL = '1'
    VICTORY_GPU_TIMING = '1'
}
```

### Configuration and inspection commands

```powershell
# Show resolved paths and validate configuration
victory config
cargo run -p victory -- config

# Inspect PE headers and imports
victory inspect 'D:\Games\MyDump\game_scarlett_master.exe'
victory inspect 'D:\Games\MyDump\game_scarlett_master.exe' --imports --exports

# Census imports in folders or files
victory census 'D:\Games\MyDump'
victory census 'D:\Games\MyDump' --missing
victory census 'D:\Games\MyDump' --strict --missing

# Show import-library exports
victory lib-exports 'C:\SDK\lib\my-import-library.lib'
victory lib-exports 'C:\SDK\lib\my-import-library.lib' --list

# Inspect shader containers
victory shader-info 'D:\Games\MyDump'
victory shader-info 'D:\Games\MyDump' --verbose --disasm
```

Use `target\release\victory.exe` or `target\diag\victory.exe` in place of
`victory` when the binary is not added to `PATH`.

### Shader commands

```powershell
# Translate and report shader support
victory translate 'D:\Games\MyDump'

# Translate with validation
victory translate 'D:\Games\MyDump' --validate --jobs 8

# Emit host pipelines too
victory translate 'D:\Games\MyDump' --validate --pipelines --jobs 8

# Print one result per program
victory translate 'D:\Games\MyDump' --validate --list

# Precompile every discovered shader into the shader cache
victory shaders 'D:\Games\MyDump' --jobs 8

# Precompile the configured game dump and save a report under debugs\
.\Play-VIctory.cmd shaders

# Translate only the shader hashes found in a run log
victory translate 'D:\Games\MyDump' --warm 'D:\Logs\victory-measure.log' --jobs 8

# Precompile every shader container in an alternative folder
target\diag\victory.exe shaders 'D:\Games\ShaderArchives'
```

### Pipeline warm-up commands

```powershell
# Warm only pipelines used by earlier runs
target\release\victory.exe warm --used --jobs 2

# Warm all known pipelines
target\release\victory.exe warm --jobs 8

# Recreate entries that were made previously
target\release\victory.exe warm --again --jobs 8

# Limit the number of pipelines processed
target\release\victory.exe warm --used --limit 500
```

The normal launcher runs `warm --used --jobs 2` automatically as soon as a
pipeline book exists.

### Tests and repository checks

```powershell
# Run the complete test suite
cargo test --workspace --locked

# Run only a crate
cargo test -p victory-core --locked
cargo test -p victory-gpu --lib --locked
cargo test -p victory-shader --lib --locked

# Run shader tests with a specific DXIL validator
$env:VICTORY_DXIL = 'C:\tools\dxc\bin\x64\dxil.dll'
cargo test -p victory-shader --lib --locked -- --test-threads=1

# Lints, like CI
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings

# Asset-policy and repository checks
cargo xtask policy
cargo xtask install-hooks

# Format Rust source
cargo fmt --all

# Check formatting without changing files
cargo fmt --all -- --check
```

### Capture and replay diagnostics

Capture only with a diagnostics build:

```powershell
$env:VICTORY_RECORD = 'D:\VIctory\captures'
$env:VICTORY_RECORD_AT = '60'
$env:VICTORY_RECORD_FRAMES = '3'

target\diag\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-s
```

Replay a capture:

```powershell
# Replay the folder or its last capture
target\diag\victory.exe replay 'D:\VIctory\captures'

# Use five loops and detailed command timing
target\diag\victory.exe replay 'D:\VIctory\captures' --loops 5 --timing detailed

# Compare the unchanged frame with experiments
target\diag\victory.exe replay 'D:\VIctory\captures' --compare --skip-clamps --skip-hash-passes

# Replay a specific part
target\diag\victory.exe replay 'D:\VIctory\captures' --only 40..80

# Save the replay image elsewhere
target\diag\victory.exe replay 'D:\VIctory\captures' --image 'D:\VIctory\replay.png'

# Find a changing pixel
target\diag\victory.exe replay 'D:\VIctory\captures' --pixel 1234,567

# Move buffers to system memory or VRAM
target\diag\victory.exe replay 'D:\VIctory\captures' --buffers sysmem
target\diag\victory.exe replay 'D:\VIctory\captures' --buffers vram
```

Additional replay experiments and their explanations are listed in
[docs/replay.md](docs/replay.md).

### Useful diagnostic environment variables

```powershell
$env:VICTORY_LOG = 'victory_loader=trace,info'
$env:VICTORY_D3D12_DEBUG = '1'
$env:VICTORY_D3D12_GBV = '1'
$env:VICTORY_D3D12_DRED = '1'
$env:VICTORY_GPU_TIMING = '1'
$env:VICTORY_PANEL = '1'
$env:VICTORY_CAPTURE = 'D:\VIctory\frames'
$env:VICTORY_CAPTURE_FRAMES = '30,31,32'
$env:VICTORY_STACKS = '20,60'
$env:VICTORY_D3D12_WARP = '1'

target\diag\victory.exe run 'D:\Games\MyDump\game_scarlett_master.exe' --execute --console series-s
```

Remove a diagnostic override before the next session:

```powershell
Remove-Item Env:VICTORY_D3D12_DEBUG
Remove-Item Env:VICTORY_D3D12_GBV
Remove-Item Env:VICTORY_D3D12_DRED
Remove-Item Env:VICTORY_GPU_TIMING
Remove-Item Env:VICTORY_PANEL
```

## What is different here

In short; the reasons and the measurements are in [docs/findings.md](docs/findings.md).

- **List calls are written down, not carried out, on the title's threads**
  (`VICTORY_THIN`): eight threads of ours translate them.
- **Submissions are prepared by a thread of ours and joined**
  (`VICTORY_ASYNC_SUBMIT`, `VICTORY_JOIN_PARTS`), with what can be spread over
  threads spread: refreshes, compares (AVX2), descriptor records, landings.
- **What shaders wrote comes back beside the write guards**, by the dwords that
  changed, on a thread of its own (`VICTORY_RELAY`, `VICTORY_LAND`).
- **Buffer fills that need bytes still on the card are done on the card**
  (`VICTORY_CARD_STEPS`) instead of waiting for it.
- **The title's writes are caught more cheaply**: one view opened at a fault,
  blocks that rest, places in the title's code that look before they write.
- **Textures go up on a copy queue of their own** and a slot shows one only after
  its upload ran, which also ended a device loss that came every 15 minutes or so.
- **Boats float**: textures that shaders write and the title's CPU reads go back
  to title memory (from fxceless and Geckomacabre, on by default here).
- **Frame record and replay** with per-pass times and shader variants compared
  turn by turn ([docs/replay.md](docs/replay.md)).

## Credits

This is a tree of other people's work with more on top. The history is kept, and
commits taken from elsewhere name the commit and its author.

- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and its
  contributors: the loader, the runtime services, the Direct3D 12 back end and
  the shader recompiler.
- **[fxceless/victory-fork](https://github.com/fxceless/victory-fork)**: the fork
  this one started from, and the people whose pull requests it carries.
- **[DexNom/VIctory](https://github.com/DexNom/VIctory)**: ray tracing fixes,
  cube gradients, sparse textures.
- **[Belobug/VIctory-Belobug-AMD](https://github.com/Belobug/VIctory-Belobug-AMD)**:
  the ambient light idea, pipeline workers, and work by romainhedouin.
- **[FQY55kai/ZJOU-VICTORY](https://github.com/FQY55kai/ZJOU-VICTORY)**.
- **[myokex/victory-amd](https://github.com/myokex/victory-amd)**: the guard over
  every view of a page (with Spexivus, joroyt and tightfall), and Joshua Odom's
  reads into title memory.
- **Geckomacabre** and **cxy0072019-sketch**: the texture read-back.
- **[XCL](https://github.com/ivall/xcl)** (GPL-2.0-only) was read for how the same
  title behaves under another layer; no code of it is here.
- This fork's changes were made with [Claude Code](https://claude.com/claude-code).

## License

GPL-3.0-or-later, as VIctory. See [LICENSE](LICENSE); the one file that is not
covered is named in [docs/asset-policy.md](docs/asset-policy.md).

## Mesure locale rapide

Depuis ce dossier:

```powershell
Set-Location 'C:\..\..\..\..\cool_fox'
.\Play-VIctory.cmd measure
```
