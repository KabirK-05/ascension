# The bundled exercise library

`Sources/AscensionCore/Resources/ExerciseLibrary/` is generated, not hand-written.
Regenerate it with:

```
packages/AscensionCore/Tools/build-exercise-library.sh
```

## Source

[free-exercise-db](https://github.com/yuhonas/free-exercise-db) — **Unlicense**
(public domain), so no attribution is required and bundling is unrestricted. The
script pulls `dist/exercises.json` and `exercises/<id>/{0,1}.jpg` from `main`.

Spec §10 requires the data to be bundled with no runtime dependency, and nothing in
`ExerciseLibrary` ever touches the network.

## What is bundled, and what is not

`exercise-library-allowlist.txt` is the whole decision: **64 of the dataset's 876
exercises**, being the 17 the seeded program references plus the alternatives for each
of its movement patterns. The full dataset is ~1 MB of JSON and ~1,700 images for a
library a single user would never scroll; the slice is 72 KB of JSON and 128 images.

Only the seven fields the app shows survive the cut (`select_exercises.py`): id, name,
equipment, primary and secondary muscles, instructions, images. `force`, `level`,
`mechanic` and `category` are dropped — nothing reads them.

Images are resized to **480 px wide, quality 72**, which is the width the detail view
draws them at on an iPhone (two side by side, ~165 pt each) at 3x. Originals are
850 px and would triple the bundle for pixels no screen shows.

## Ids

The dataset's ids and `SeedExerciseId`'s do not line up — only four of the seventeen
match. `ExerciseLibraryMapping` reconciles them, because `SeedExerciseId` is a
contract (`docs/EXPORT_SCHEMA.md` §2.2, top-set logs, the Worker) and the dataset is
not. Adding a program exercise means adding its dataset id to both the allowlist and
that map.
