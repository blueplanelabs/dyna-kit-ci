#!/usr/bin/env python3
"""Patch SmalltalkCI's gtoolkit/run.sh so GToolkit --headful works under CI.

Based on the inline heredoc in dynaspace-os's build workflow. Applies Fixes 1/2/3
verbatim. Does NOT pin the GToolkit VM version: in the kit CI the image and VM
are user-provided (--image / --vm), so prepare_gt / prepare_vm are skipped and
the version is controlled by which VM zip the workflow downloads.

Usage: patch-smalltalkci.py <path-to-gtoolkit/run.sh>

Two bugs in SmalltalkCI's gtoolkit/run.sh when --headful is used in CI:

Bug 1: --headful (config_headless=false) never adds --interactive to the
GlamorousToolkit-cli invocation, so Bloc/Skia are never loaded.
Fix: add --interactive before the image path when ! is_headless.

Bug 2: --interactive makes Smalltalk isHeadless return false, so
load_project calls promptToProceed -> UIManager confirm:... which shows
a real dialog under Xvfb, gets no click, returns nil, and crashes with
mustBeBoolean. Fix: always call saveAndQuitImage directly (no dialog needed
in CI).
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
# Fix 1: set interactive_flag when ! is_headless; keep --no-quit only for
# local interactive use (not CI). On GitHub Actions is_github_build() is
# true, so --no-quit is skipped and the process exits naturally after eval.
c = c.replace(
    '  if ! is_travis_build && ! is_headless; then\n    vm_flags="--no-quit"\n',
    '  if ! is_headless; then\n    interactive_flag="--interactive"\n    if ! is_travis_build && ! is_github_build; then\n      vm_flags="--no-quit"\n    fi\n'
)
# Fix 1: pass interactive_flag to GlamorousToolkit-cli before the image
c = c.replace(
    'run_script "${resolved_vm}" "${resolved_image}" eval',
    'run_script "${resolved_vm}" ${interactive_flag} "${resolved_image}" eval'
)
# Fix 2: skip promptToProceed (returns nil under Xvfb) - always save and quit
c = c.replace(
    '    (smalltalkCI isHeadless or: [ smalltalkCI promptToProceed ])\n      ifTrue: [ smalltalkCI saveAndQuitImage ]',
    '    smalltalkCI saveAndQuitImage'
)
# Fix 3: after test: completes, SmalltalkCI>>shutdown: is a no-op when
# isHeadless=false (--interactive mode), so the CLI stays alive.
# Override shutdown: in-image to always call shutdownHeadless: before
# running tests, ensuring the process exits with the correct status.
c = c.replace(
    "    smalltalkCI test: '$(resolve_path \"${config_ston}\")'",
    "    SmalltalkCI class compile: 'shutdown: buildSuccessful self shutdownHeadless: buildSuccessful' classified: 'finalizing'.\n    smalltalkCI test: '$(resolve_path \"${config_ston}\")'"
)
assert c != original, f"Patch had no effect on {path} - SmalltalkCI version may have changed"
with open(path, 'w') as f:
    f.write(c)
print(f"Patched successfully: {path}")
