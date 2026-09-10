#!/usr/bin/env python3
"""Patch SmalltalkCI's gtoolkit/run.sh so GToolkit --headful works under CI.

Mirrors the inline patch in dynaspace-os's build workflow
(.github/workflows/build-examples-release.yml, PR #22). Keep the two in sync.
Applies Fixes 1/2/3/5. Fix 4 there (pinning the GToolkit VM download URL) is
NOT applied here: in the kit CI the image and VM are user-provided
(--image / --vm), so prepare_gt / prepare_vm are skipped entirely and the VM
version is controlled by which zip the workflow downloads.

Usage: patch-smalltalkci.py <path-to-gtoolkit/run.sh>

Two bugs in SmalltalkCI's gtoolkit/run.sh when --headful is used in CI:

Bug 1: --headful (config_headless=false) never adds --interactive to the
GlamorousToolkit-cli invocation, so Bloc/Skia are never loaded.
Fix: add --interactive before the image path when ! is_headless - but only for
the TEST phase (gtoolkit::test_project). The LOAD phase only runs Metacello and
needs no world; moreover, since GT v1.1.555 (the Glutin -> Winit windowing
rework) an --interactive image under Xvfb never exits the process after
saveAndQuitImage, hanging the load phase until the job timeout. Keeping the load
phase headless avoids that entire class of hang.

Bug 2: --interactive makes Smalltalk isHeadless return false, so load_project
calls promptToProceed -> UIManager confirm:... which shows a real dialog under
Xvfb, gets no click, returns nil, and crashes with mustBeBoolean.
Fix: always call saveAndQuitImage directly (no dialog needed in CI).
"""
import sys

path = sys.argv[1]
with open(path) as f:
    original = f.read()
c = original
# Fix 1: add interactive_flag variable
c = c.replace(
    '  local vm_flags=""\n',
    '  local vm_flags=""\n  local interactive_flag=""\n'
)
# Fix 1: set interactive_flag when ! is_headless AND the caller asked for it
# (GT_INTERACTIVE, set only by the test phase; bash locals are visible in
# callees). Keep --no-quit only for local interactive use (not CI): on GitHub
# Actions is_github_build() is true, so --no-quit is skipped and the process
# exits naturally after eval.
c = c.replace(
    '  if ! is_travis_build && ! is_headless; then\n    vm_flags="--no-quit"\n',
    '  if ! is_headless && [ "${GT_INTERACTIVE:-}" = "true" ]; then\n    interactive_flag="--interactive"\n    if ! is_travis_build && ! is_github_build; then\n      vm_flags="--no-quit"\n    fi\n'
)
# Fix 1: the test phase is the only one that needs the interactive world
c = c.replace(
    'gtoolkit::test_project() {',
    'gtoolkit::test_project() {\n  local GT_INTERACTIVE=true'
)
# Fix 1: pass interactive_flag to GlamorousToolkit-cli before the image
c = c.replace(
    'run_script "${resolved_vm}" "${resolved_image}" eval',
    'run_script "${resolved_vm}" ${interactive_flag} "${resolved_image}" eval'
)
# Fix 5: even with Fix 3, the new-Winit GT (v1.1.555+) OS process never dies
# after the in-image exit when running --interactive under Xvfb: the suite
# finishes, smalltalkCI writes build_status.txt (its verdict), and the VM hangs
# until the step's timeout - swallowing the test exit code and burning idle
# minutes. Watch for the status file from the shell, put the VM down once the
# verdict is on disk, and swallow the kill-induced exit code so run.sh (set -e)
# reaches finalize, which reads the status file and exits with the real test
# result.
run_line = '  run_script "${resolved_vm}" ${interactive_flag} "${resolved_image}" eval ${vm_flags} "${script}"\n'
watchdog = (
    '  if [ "${GT_INTERACTIVE:-}" = "true" ]; then\n'
    '    (\n'
    '      while [ ! -f "${BUILD_STATUS_FILE}" ]; do sleep 5; done\n'
    '      sleep 30\n'
    '      echo "Build status file written but GT VM still alive (new-Winit Xvfb exit hang); killing it."\n'
    '      pkill -9 -f GlamorousToolkit-cli || true\n'
    '    ) &\n'
    '    local watchdog_pid=$!\n'
    '    local vm_status=0\n'
    + '    ' + run_line.strip() + ' || vm_status=$?\n'
    + '    kill "${watchdog_pid}" 2> /dev/null || true\n'
    '    if [ "${vm_status}" -ne 0 ] && [ ! -f "${BUILD_STATUS_FILE}" ]; then\n'
    '      return "${vm_status}"\n'
    '    fi\n'
    '    return 0\n'
    '  fi\n'
    + run_line
)
c = c.replace(run_line, watchdog)
assert 'watchdog_pid' in c, f"Fix 5 had no effect on {path} - run_script invocation may have changed"
# Fix 2: skip promptToProceed (returns nil under Xvfb) - always save and quit
c = c.replace(
    '    (smalltalkCI isHeadless or: [ smalltalkCI promptToProceed ])\n      ifTrue: [ smalltalkCI saveAndQuitImage ]',
    '    smalltalkCI saveAndQuitImage'
)
# Fix 3: after test: completes, SmalltalkCI>>shutdown: is a no-op when
# isHeadless=false (--interactive mode), so the CLI stays alive. Override
# shutdown: in-image to always call shutdownHeadless: before running tests,
# ensuring the process exits with the correct status.
c = c.replace(
    "    smalltalkCI test: '$(resolve_path \"${config_ston}\")'",
    "    SmalltalkCI class compile: 'shutdown: buildSuccessful self shutdownHeadless: buildSuccessful' classified: 'finalizing'.\n    smalltalkCI test: '$(resolve_path \"${config_ston}\")'"
)
assert c != original, f"Patch had no effect on {path} - SmalltalkCI version may have changed"
with open(path, 'w') as f:
    f.write(c)
print(f"Patched successfully: {path}")
