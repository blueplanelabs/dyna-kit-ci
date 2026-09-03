"tangle-lepiter.st  -  SmalltalkCI #preTesting phase. Shared, lives in dyna-kit-ci;
 kit-ci.yml copies it into the kit workspace before running smalltalkci.

 Tangles the kit's Lepiter knowledge base so its <gtExample>s exist before the
 #testing phase. Analogous to steps 3-5 of dynaspace-os's
 evaluate-lepiter-snippets.st, minus the from-scratch LepiterLiterate load
 (already in the dynaspace-os release image) and the coverage-persist step.

 Fully guarded: a kit whose baseline has no #loadLepiter, whose lepiter/ is not
 registered, or whose database has no table of contents is a clean no-op - the
 case for a kit that still ships committed .class.st code and an empty lepiter/."

Transcript := NonInteractiveTranscript stdout.
Transcript crShow: 'tangle-lepiter: starting'; cr.

[ | workspace stonSource idx baselineName baselineClass repo lepiterDir db |

  workspace := (Smalltalk os environment
      at: 'GITHUB_WORKSPACE'
      ifAbsent: [ Transcript crShow: 'FATAL: GITHUB_WORKSPACE not set'; cr. Smalltalk exit: 1 ])
      asFileReference.

  "1. Baseline name from .smalltalk.ston (same key SmalltalkCI loads from)."
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
  Transcript crShow: 'tangle-lepiter: baseline ', baselineName; cr.

  "2. Baseline class + its own #loadLepiter (registers <repo>/lepiter, enforces the db name)."
  baselineClass := Smalltalk
      at: ('BaselineOf', baselineName) asSymbol
      ifAbsent: [ Transcript crShow: 'FATAL: BaselineOf', baselineName, ' is not in the image'; cr.
          Smalltalk exit: 1 ].
  (baselineClass respondsTo: #loadLepiter) ifFalse: [
      Transcript crShow: 'tangle-lepiter: BaselineOf', baselineName,
          ' has no loadLepiter - nothing to tangle'; cr.
      ^ nil ].
  baselineClass loadLepiter.

  "3. Locate the kit's lepiter/ directory via the repo that owns the baseline package."
  repo := IceRepository registry
      detect: [ :r | [ r includesPackageNamed: baselineClass package name ] on: Error do: [ :e | false ] ]
      ifNone: [ Transcript crShow: 'tangle-lepiter: repo not in Iceberg registry - skipping tangle'; cr.
          ^ nil ].
  lepiterDir := repo repositoryDirectory / 'lepiter'.

  "4. Locate the registered database by its store directory (name-independent)."
  db := LeDatabasesRegistry default currentLoadedDefaultLogicalDatabase databases
      detect: [ :d | d localStoreRootDirectory asFileReference fullName = lepiterDir asFileReference fullName ]
      ifNone: [ Transcript crShow: 'tangle-lepiter: no database registered for ', lepiterDir fullName,
          ' - skipping tangle'; cr.
          ^ nil ].
  Transcript crShow: 'tangle-lepiter: database ', db databaseName printString; cr.

  "5. Tangle from the table of contents (no ToC -> nothing to traverse)."
  db tableOfContents
      ifNil: [ Transcript crShow: 'tangle-lepiter: database has no table of contents - skipping tangle'; cr ]
      ifNotNil: [
          [ db processKnowledge.
            Transcript crShow: 'tangle-lepiter: processKnowledge complete'; cr ]
            on: Error
            do: [ :e |
                Transcript crShow: 'tangle-lepiter: WARNING processKnowledge raised ',
                    e class name, ': ', e messageText; cr.
                e return ] ].

  Transcript crShow: 'tangle-lepiter: done'; cr ]

  on: Error
  do: [ :e |
      Transcript crShow: 'FATAL: tangle-lepiter raised ', e class name, ': ', e messageText; cr.
      Smalltalk exit: 1 ].
