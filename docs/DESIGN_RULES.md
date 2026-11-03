# Ascension — Design Rules

**These are hard constraints, not suggestions.** Every PR that touches UI is reviewed
against this file. A reviewer may reject a PR by citing a rule number alone.

The goal: this app should look like Apple shipped it, not like an LLM generated it.
The failure mode we are actively designing against is **explanatory clutter** — the
card with a title, an icon, a number, and a grey sentence underneath explaining the
number. That sentence is the enemy.

---

## 1. The subtitle ban (the most important rule)

**1.1** No subtitle, caption, helper, description, or explanatory text under any
title, number, card header, or section header. Ever. If a number needs a sentence to
explain it, the number is wrong or the label is wrong — fix those instead.

**1.2** Banned copy patterns. Do not write these, in any casing or phrasing:
- "Here's your…", "Your daily…", "Track your…", "Keep it up!", "Nice work!"
- "Based on your…", "We noticed…", "Let's…", "Tap to…", "Swipe to…"
- Any sentence whose only job is to describe the UI element it sits inside.
- Any motivational copy. The user is an adult with a goal; the data motivates.

**1.3** A label is a **noun**, at most two words, and never repeats what the value
already says. `Protein` above `148/150 g` — not `Protein Intake` and never
`Protein Intake — you're almost at your goal`.

**1.4** Empty states are a **control**, not a paragraph. An empty food diary shows the
quick-add staples, not "No meals logged yet. Add your first meal to get started."

---

## 2. Subtraction test (apply to every element you add)

**2.1** Before adding any element, remove it mentally. If the screen still answers its
one question, **it does not ship**. Every screen answers exactly one question:
- Today → *What do I do today?*
- Train → *Am I on program?*
- Eat → *How much protein is left?*
- Trends → *Is it working?*

**2.2** No element exists to fill space. White space is the design.

**2.3** No icon next to a label that already says the same thing. No icon purely for
decoration. SF Symbols are for **actions** and for **status that has no words**.

**2.4** One accent colour per screen, maximum. Colour means *status*, never *theme*.

---

## 3. Numbers are the hero

**3.1** The largest type on any card is the **value**, not the label. Labels are
secondary: smaller, lower contrast, never bold.

**3.2** Units are inline and small (`73.6 kg`, `148 g`, `7h42`), never on their own line.

**3.3** One font-weight change per card, maximum. Hierarchy comes from **size and
colour**, not from four weights stacked.

**3.4** Never show a precision the data doesn't have. Weight to 0.1 kg. Readiness is an
integer. No `73.60 kg`, no `82.4%`.

---

## 4. Native-first

**4.1** SF Pro only (system font). SF Symbols only. No custom fonts, no icon packs,
no illustrations, no mascots, no gradients-as-branding.

**4.2** Dark mode first; verify light mode before merge. Both must look deliberate.

**4.3** System materials and standard components (`List`, `Form`, `NavigationStack`,
`.ultraThinMaterial`) unless there is a documented reason not to. Respect Dynamic Type
at all sizes, and VoiceOver labels on every interactive element.

**4.4** Motion: numbers animate, screens do not bounce. No spring overshoot, no
confetti, no celebratory animation. Transitions are the system's own.

---

## 5. Density

**5.1** Today fits on one screen at the default Dynamic Type size with no scrolling for
the primary answer. Secondary detail may scroll below the fold.

**5.2** Maximum 5 cards on Today. If a sixth is needed, something else is wrong.

**5.3** Tapping a number goes to its detail. That is the disclosure mechanism — not an
expander, not a tooltip, not an info button.

---

## 6. The consistency grid (Today)

A GitHub-contributions-style grid, because the user reads one instantly.

**6.1** One cell per day, trailing **17 weeks** (7 rows × 17 columns fits iPhone width
at the default type size without scrolling). Not a full year — it would not fit.

**6.2** Intensity is **0–4**, one point for each daily win:
1. Session: trained as planned, **or** a planned rest day with no session.
2. Protein ≥ 140 g.
3. Steps ≥ 10,000.
4. Sleep ≥ 7.5 h.

**6.3** No legend. No axis labels. No month labels. No "4 of 4 goals met today"
subtitle. Month boundaries, if shown at all, are a 1px tick — not text.

**6.4** Tapping a cell reveals that day's four values. That is the only affordance.

**6.5** Colour ramp is a single hue at 5 steps (including empty). Empty cells are a
near-background fill, never a border.

---

## 7. Mandatory process

**7.1** Before building or restyling any screen, search **Mobbin MCP** for reference
flows (spec §4) and record in the PR which references informed the layout. Adapt
patterns — layout, hierarchy, density, interaction. Never copy brand assets, copy
text, or proprietary iconography.

**7.2** Every UI PR includes a screenshot in **both** light and dark mode.

**7.3** Every UI PR body answers, in one line each:
- What single question does this screen answer?
- What did you remove?

A PR that removed nothing gets scrutiny.
