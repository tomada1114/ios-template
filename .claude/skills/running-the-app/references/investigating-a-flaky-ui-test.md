# Investigating a flaky UI test

How to find out why `just uitest` (or the launch test inside `just check` or
`just check-release`) fails some runs and passes others: keep the evidence, read it
from the result bundle, measure the machine the run shares, and turn a suspected race
into a repro. What the issue for a flake records is `triaging-issues` › What an issue
body must contain. The commands below were run against a kept bundle of this template's launch
test on the pinned Xcode 27.0; `xcrun xcresulttool help <subcommand>` is the authority when an Xcode
changes them.

## Keep the failing bundle

Each device family's run deletes its own bundle before it runs —
`build/LaunchUITests.xcresult` for an iPhone, `build/LaunchUITests-ipad.xcresult` for
the iPad leg — so the next run of the same family destroys the only evidence of the
last failure. Move a failing bundle out of `build/` the moment it fails,
to a directory outside the checkout that outlives the worktree (a worktree's gitignored
files go with it), under a name that says which run it was. Keep the passing bundles of
the same series too: the comparison below needs them.

## Read the bundle, not the log

- **Per test, across every bundle:** `xcrun xcresulttool get test-results tests --path
  <bundle> --compact` prints each test's result, duration, failure message with its
  source line, and the device (name, udid, OS). Run it over every bundle of the
  series, passing ones included, and compare. Grepping `xcodebuild` output instead
  misleads: it carries ANSI colour codes that break a pattern, and the raw log and the
  `xcbeautify` output differ.
- **The timeline:** `xcrun xcresulttool get test-results activities --path <bundle>
  --test-id <nodeIdentifier>` lists each step with its start time, so a wait that took
  seconds, or a tap that ran before something arrived, shows up as a gap.
- **What the screen held:** `xcrun xcresulttool export attachments --path <bundle>
  --output-path <dir> [--only-failures]` writes the failure-time UI hierarchy (`App UI
  hierarchy for …`, with every element's frame), the screen recording (`.mp4`), and a
  `Synthesized Event` attachment per tap, all named in its `manifest.json`. Pull frames
  from the recording around the failure with `ffmpeg -ss <seconds> -i <mp4> -frames:v 1
  <png>` (ffmpeg is not a pinned tool; install it if the host lacks it). A `Synthesized
  Event` is an NSKeyedArchive: `plutil -p <file>` shows `coordinate.x` and
  `coordinate.y` as references into `$objects`, which hold the tap point. A tap point
  outside the target's frame in the hierarchy means the tap was resolved against a
  layout that moved — a keyboard arriving after focus is the common case.
- **What the app printed:** `xcrun xcresulttool export diagnostics --path <bundle>
  --output-path <dir>` writes the test runner's output and the app's own stdout and
  stderr (`StandardOutputAndStandardError-<bundle-id>.txt`). UIKit's warnings land
  there, such as a navigation push it refused ("navigation stack will not be updated"),
  which point at an app defect rather than the test.

A test that fails at different steps in different runs is usually several defects.
Classify each failure from its bundle before running the test again.

## Measure the machine the run shares

A UI test's waits are wall-clock, so what else the Mac runs changes the result:

- Run nothing else beside a timing-sensitive run: another build, another test suite, or
  an agent session (a review or an implementation agent loads the Mac even when it runs
  no `xcodebuild`). A series run under someone else's load proves nothing either way.
- One simulator at a time; shut down every simulator you booted when you are done.
- A cold-booted simulator spends one to three minutes on its own post-boot work
  (wallpaper and widget extensions, scoring daemons), at 50-100% CPU or more per process,
  during which an XCUITest snapshot takes seconds and the test's waits time out.
  `just uitest-run` waits it out (`scripts/wait-simulator-settled.sh`); a test you run
  with `xcodebuild` directly does not. After a host reboot, Spotlight indexing and
  other host work add load of their own — check `uptime` before a timing run.
- Measure the device's own process tree (its `launchd_sim` and descendants, as that
  script does), not the host load average, which lags and names no process. `top -l 1`
  reports 0% CPU for every process (its first sample has no interval; use `-l 2`), and
  `ps -o pcpu` is a decaying average, not the current rate. What of this the issue
  records is in `triaging-issues`.

## From a suspected race to a fix

- Turn the suspicion into a deterministic repro before designing a fix: a temporary
  test that hammers the suspected window with a tight, bounded poll, plus temporary
  log lines in the app at the two events that race. A repro that fails every run is
  what a fix is judged against; a flake that stops appearing is not.
- Prove the fix with a prototype on that repro, under every arm the defect can take
  (with and without the sheet, cold and warm boot), before implementing it properly. A
  fix that passes only the arm it was written for is the usual way a race ships twice.
- A new series of runs counts only after something changed — the code, the device, or
  the load. Re-running the same thing until it passes is not a result, and a green run
  after red ones with nothing changed is not a fix.
- Remove the temporary test and log lines before the pull request, then
  `just generate`.
