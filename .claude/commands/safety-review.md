---
description: Review the current changes against the app's file-safety invariants
---

This app moves users' files to the Trash, so review the current changes (`git diff` against the main branch, or the files I name) against the invariants in CLAUDE.md:

1. Can any code path trash an item that was never warned about, or before `warnDays` have passed since `firstWarned`?
2. Can anything be trashed while notification permission is unavailable?
3. Is any file removed with something other than `FileManager.trashItem`?
4. Are hidden files and in-progress downloads still skipped?
5. Could a watched-folder setting reach `/`, the home folder, `~/Library` or a system folder?
6. Did `Sources/Core` gain an import other than `Foundation`?
7. Are there personal paths, names or identifiers in source, tests or docs?

For each problem, quote the file and line and explain a concrete failing scenario. Then check that `Tests/main.swift` covers both the "should act" and the "must not act" case for any behaviour that changed, and list any missing tests.
