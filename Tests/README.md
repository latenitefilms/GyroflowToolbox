# Engine integration and verification

Gyroflow Core is an unmodified Git dependency, pinned in
`Source/Frameworks/gyroflow/Cargo.toml` and `Cargo.lock`. There is no vendored Core
checkout. The Burn and CubeCL patches match the revisions used by Gyroflow 1.7;
Cargo requires these patches in the consuming application's manifest. Entries for
other backends do not enable them. OpenCV and CPU inference are not enabled.

Build with the installed FxPlug SDK under `/Library/Developer`. The deployment
target is macOS 13. `LLM Resources` contains references and test media only.

## Ownership and resources

- Rust owns parameter definitions, analysis sessions, Core keyframes, presets,
  saved defaults, lens setup and project updates.
- Objective-C handles FxPlug callbacks, host parameter access and native dialogs.
  A reusable Metal Core Image context converts host textures to bounded GRAY8
  frames. Analysis and rendering share the Rust crop/rotation rules, including
  the Inspector's Input Rotation setting.
- The renderer configures the bundled GMFlow weights and sandbox cache directory
  before starting FxPlug. A missing model produces an error; it never triggers a
  model download. The model hash and upstream licenses are in
  `Source/Gyroflow/Plugin/Resources/Models`.
- `build.rs` supplies a private Mach-O header alias for CubeCL's build-ID reader
  when linking the Rust cdylib. It uses the dylib's UUID, without changing Core or
  allowing arbitrary undefined symbols.
- A session owns its Core manager and analysis state. Cancellation is atomic;
  release is idempotent. Up to four sessions can run in one renderer process.
  Autosync measures up to three three-second windows; unused frames skip GPU
  conversion. Optical analysis retains upstream tracking measurements until the
  result is exported and the session is released.
- Analysis saves only its motion, offset or lens-delay result. It preserves the
  original project's animation and unrelated settings. A changed project or
  interrupted job is not overwritten. Named presets exclude source telemetry
  and offsets; saved defaults also exclude lens calibration and animation.

## Automated checks

Run Rust commands inside `Source/Frameworks/gyroflow` so rustup selects the pinned
toolchain:

```sh
cargo fmt --package gyroflow-toolbox --check
cargo test --locked
cargo clippy --locked --all-targets --no-deps -- -D warnings
cargo doc --locked --no-deps
```

From the repository root:

```sh
./Scripts/build_rust.sh
python3 Scripts/sync_parameters.py
./Scripts/test_compatibility.sh
./Scripts/test_metal.sh
./Scripts/test_analysis_image.sh
python3 Scripts/test_presets.py --clip 'LLM Resources/Test Clips/GoPro Hero 6.MP4'
python3 Scripts/test_analysis.py
python3 Scripts/test_analysis.py --gmflow
python3 Scripts/test_analysis.py --mode synchronize --seconds 8 --clip 'LLM Resources/Test Clips/GoPro Hero 6.MP4'
python3 Scripts/test_analysis.py --mode lens_delay --seconds 6 --clip 'LLM Resources/Test Clips/Sony a7sIII Tamron 28-200 zooming.MP4'
```

GPU tests require access to a physical Metal device. `test_analysis.py --library`
can select a development dylib without replacing the universal release library.
Its FFmpeg decoder is a test tool only; the application receives frames through
FxPlug. The script verifies model integrity, result persistence, Inspector
rotation, cancellation and repeated session release.

`test_media.py` imports the supplied camera fixtures without modifying them.
`test_media_render.py` renders their MP4 frames through the shipping Metal ABI.
The compatibility suite checks v1.3.5 archives, C layouts, parameter IDs, effect
UUIDs and published Motion channels.

The Motion parameter generator locates additive controls by their IDs. It never
adds XML comments and refuses to overwrite unrelated controls between them.

## Observed analysis results

Standalone checks on an Apple M1 Max produced the following results. Timings
include setup and test decoding and are not Final Cut Pro export benchmarks.
Peak RSS is process resident memory, not a measurement of all GPU allocations.

| Operation | Frames supplied | Elapsed | Peak RSS | Result |
| --- | ---: | ---: | ---: | --- |
| Synthetic optical KLT, no gyro | 30 | 0.50 s | 202 MiB | 29 measured frames |
| GoPro optical KLT | 90 | 1.30 s | 251 MiB | 89 measured frames |
| GoPro optical GMFlow | 36 | 17.41 s | 358 MiB | 35 measured frames |
| GoPro autosync KLT | 240 | 6.51 s | 300 MiB | 3 sync points |
| GoPro autosync GMFlow | 240 | 109.38 s | 562 MiB | 3 sync points |
| Sony zoom lens-delay KLT | 330 | 6.24 s | 346 MiB | 2 frames; correlation 0.997 |

Both trackers ran on Metal. GMFlow loaded the bundled weights. KLT remains the
default because it was substantially faster in these fixtures.

## Host and release verification

The following require testing in the actual host and distribution environment:

- Background-task progress, cancellation, undo/redo and saving/reopening a
  library after analysis. Confirm that a concurrent project import prevents the
  previous analysis from replacing it.
- Named preset recall, saved defaults across renderer restarts and branded
  dialogs in Final Cut Pro.
- Portrait clips on matching portrait timelines, different host image origins,
  and the existing full-source compound-clip workflow. Analyse at original speed
  and retime the outer compound clip; analysis rejects diverging time clocks.
- Long-clip memory behaviour, GPU allocation lifetime and Instruments profiling.
  The CLI Leaks attempt could not obtain the target process's task port; it did
  not establish a leak-free result.
- Execution on the minimum supported macOS and Intel hardware, signed sandbox
  behaviour, App Store validation and TestFlight installation. A universal
  unsigned build and deployment-load-command checks do not replace these tests.

Toolbox does not currently provide Gyroflow's tracked-point editor. Final Cut Pro
masks and object tracking do not supply Gyroflow track IDs. Changing optical
strength or per-frame correction currently requires running analysis again.
