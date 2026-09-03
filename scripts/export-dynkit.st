"export-dynkit.st  -  SmalltalkCI #postTesting phase. Shared, lives in dyna-kit-ci;
 kit-ci.yml copies it into the kit workspace before running smalltalkci.

 Convention: the kit repo defines  BaselineOf<X> class >> kit  returning a fully
 built DynOSKit (metadata + live objects). This script derives <X> from the
 #baseline key in .smalltalk.ston, calls that method, forces the version from the
 repo's VERSION file, exports the kit to $GITHUB_WORKSPACE/<name>-<version>.dynkit
 and verifies the STON round-trip. Any failure exits non-zero so the CI job fails."

Transcript := NonInteractiveTranscript stdout.
Transcript crShow: 'export-dynkit: starting'; cr.

[ | workspace stonSource idx baselineName builderClass kit versionString file reimported |

  workspace := (Smalltalk os environment
      at: 'GITHUB_WORKSPACE'
      ifAbsent: [ Transcript crShow: 'FATAL: GITHUB_WORKSPACE not set'; cr. Smalltalk exit: 1 ])
      asFileReference.

  "1. Baseline name from .smalltalk.ston (the same key SmalltalkCI loads from)."
  stonSource := (workspace / '.smalltalk.ston') exists
      ifTrue: [ (workspace / '.smalltalk.ston') contents ]
      ifFalse: [ Transcript crShow: 'FATAL: .smalltalk.ston not found'; cr. Smalltalk exit: 1 ].
  idx := stonSource indexOfSubCollection: '#baseline'.
  idx = 0 ifTrue: [
      Transcript crShow: 'FATAL: no #baseline key in .smalltalk.ston'; cr. Smalltalk exit: 1 ].
  baselineName := ((stonSource copyFrom: idx to: stonSource size) copyAfter: $') copyUpTo: $'.
  baselineName isEmpty ifTrue: [
      Transcript crShow: 'FATAL: could not parse #baseline value from .smalltalk.ston'; cr.
      Smalltalk exit: 1 ].
  Transcript crShow: '[1] baseline: ', baselineName; cr.

  "2. Convention: BaselineOf<X> class >> kit -> a fully built DynOSKit."
  builderClass := Smalltalk
      at: ('BaselineOf', baselineName) asSymbol
      ifAbsent: [ Transcript crShow: 'FATAL: BaselineOf', baselineName, ' is not in the image'; cr.
          Smalltalk exit: 1 ].
  (builderClass respondsTo: #kit) ifFalse: [
      Transcript crShow: 'FATAL: ', builderClass name, ' class does not implement #kit'; cr.
      Smalltalk exit: 1 ].
  kit := builderClass kit.
  (kit isKindOf: DynOSKit) ifFalse: [
      Transcript crShow: 'FATAL: ', builderClass name, ' kit did not return a DynOSKit (got ',
          kit class name, ')'; cr.
      Smalltalk exit: 1 ].

  "3. Version from the repo's VERSION file (keeps the .dynkit in step with the vX.Y.Z tag)."
  versionString := (workspace / 'VERSION') exists
      ifTrue: [ (workspace / 'VERSION') contents trimBoth ]
      ifFalse: [ Transcript crShow: 'FATAL: VERSION file not found'; cr. Smalltalk exit: 1 ].
  kit version: versionString.
  (kit name isNil or: [ kit name isEmpty ]) ifTrue: [
      Transcript crShow: 'FATAL: kit has no name - BaselineOf', baselineName,
          ' class >> kit must set name:'; cr.
      Smalltalk exit: 1 ].
  (kit organization isNil or: [ kit organization isEmpty ]) ifTrue: [
      Transcript crShow: 'FATAL: kit has no organization - BaselineOf', baselineName,
          ' class >> kit must set organization:'; cr.
      Smalltalk exit: 1 ].
  Transcript crShow: '[2] kit: ', kit gav, ' - ', kit liveObjects size printString, ' live object(s)'; cr.

  "4. Export to the workspace root."
  file := workspace / (kit name, '-', kit version, '.dynkit').
  kit exportTo: file.
  file exists ifFalse: [
      Transcript crShow: 'FATAL: export produced no file at ', file fullName; cr. Smalltalk exit: 1 ].
  Transcript crShow: '[3] exported: ', file fullName, ' (', file size printString, ' bytes)'; cr.

  "5. STON round-trip smoke test."
  reimported := DynOSKit fromFile: file.
  (reimported name = kit name
      and: [ reimported version = kit version
      and: [ reimported liveObjects size = kit liveObjects size ] ])
    ifFalse: [
      Transcript crShow: 'FATAL: round-trip mismatch - name=', reimported name printString,
          ' version=', reimported version printString,
          ' liveObjects=', reimported liveObjects size printString; cr.
      Smalltalk exit: 1 ].
  Transcript crShow: 'export-dynkit: SUCCESS - ', file fullName; cr ]

  on: Error
  do: [ :e |
      Transcript crShow: 'FATAL: export-dynkit raised ', e class name, ': ', e messageText; cr.
      Smalltalk exit: 1 ].
