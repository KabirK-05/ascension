# DesignSystem

Tokens and the small component set every feature tab is built from.
`docs/DESIGN_RULES.md` is the spec; this package is its implementation.

Depends on nothing — not `AscensionCore`. It is pure presentation.

## Tokens

Call sites name a meaning, never a raw value.

| Namespace | Holds |
|---|---|
| `Palette` | surfaces, text, the one accent, status, the 5-step consistency ramp |
| `Spacing` | the 4-point scale, plus `cardPadding`, `screenMargin`, `gridCellGap` |
| `Radius` | `card`, `control`, `cell` |
| `Typography` | roles built on system text styles, so Dynamic Type works unasked |

Surfaces and text are the system's own grouped colours, so both appearances are
correct by construction. Only the accent and the ramp are ours, and colour
means status, never theme (§2.4).

## Components

| Component | The one question it answers |
|---|---|
| `ValueRow` | What is this number right now? |
| `MetricRing` | How much of the target is left? |
| `StatCard` | — (a container; it answers nothing and says nothing) |
| `ConsistencyGrid` | Am I consistent? |

### The subtitle ban is enforced, not just documented

`LabelRule.isCompliant(_:)` is the mechanical form of §1.3: a noun, at most two
words, no sentence punctuation, 24 characters. Every component checks its own
label through it and trips an assertion in debug builds, so a subtitle fails in
the simulator rather than in review.

`StatCard` has no `subtitle`, `caption` or `footnote` parameter and no second
text slot of any kind. The generated-card pattern this project is designed
against cannot be expressed through it.

## Verifying a change

```
swiftlint lint --strict
xcodebuild -scheme DesignSystem -destination 'generic/platform=iOS Simulator' build
xcodebuild test -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`Screenshots/` holds the light and dark captures that went with the ASC-3 PR.
They are taken from a throwaway host app that imports this package; regenerate
them by building one rather than by adding a sample target here.
