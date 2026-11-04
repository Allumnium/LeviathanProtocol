# Leviathan: current development contract

## Read only what the task needs

- [TODO.md](TODO.md): active slice work (remaining D4, then D5).
- [docs/HANGAR.md](docs/HANGAR.md): current gameplay, UI and persistence.
- [tests/README.md](tests/README.md): focused verification.
- [COMPLETED.md](COMPLETED.md): concise delivery record.
- [docs/STORY_SPEC.md](docs/STORY_SPEC.md): narrative reference, not an implementation backlog.
- [docs/history/](docs/history/): archived plans and reports, **not current requirements**. Do not load them routinely or restore retired behavior from them.

## Workflow

- Put actionable plans in TODO.md before implementation. Move verified finished items into COMPLETED.md with a brief date/result; leave unfinished work and blockers open.
- Run only the smallest relevant tests with isolated APPDATA. Use focused native visual/interaction checks for UI; scene-tree text alone does not establish visibility.
- Full baselines, all campaign variants, long soaks and broad native acceptance require explicit user request. Ask before expanding coverage; do not rerun unchanged passing checks.
- Await asynchronous checks and require their completed summary, not just an exit code or timeout. Documentation-only changes need document/link checks, not game suites.
- Keep player-facing text concise, necessary and nonredundant. Prefer recognizable icons, meters and in-world feedback. Preserve names, costs, non-obvious consequences and actionable errors.
- Research descriptions/toasts use one short gameplay sentence, without duplicate effect numbers, prerequisites, path commentary or refitting boilerplate.

## Guardrails

- Preserve gameplay, source artwork, ownership and saves. No unsolicited systems, optional equipment, ECM/Phase, new boss phases or full Act II/III expansion.
- Runtime: GameState is `scripts/hangar_state.gd`; management uses `scenes/game_map.tscn` and `scripts/hangar_screen.gd`.
- Buy fully fitted ships; shipyard refits are free and atomic. No equipment stock, equipment buying/selling, drag-fitting, designer, materials, recipes, reserves or component health.
- Every predefined fit fills every mount. Most equipment starts available; only Beam Lance, Bomber Bay, Tactical Computer and Lab III require research. New Run has Foundation only and no forced branch; Continue preserves existing progress/loadouts.
- Hull is the only persistent health pool: zero is alive, strictly negative is destroyed. Flagship loss ends the run. Loads and finite carrier allowances follow equipment UIDs; repairs never recreate lost loads.
- Validate before mutation and commit related changes together. Failed saves leave live state unchanged and report an explicit retryable error. Current save: `user://expedition_run.json`, physical-hangar-v2 envelope via AtomicRunStore; never overwrite or guess conversions for legacy saves.
- Keep Starhull/crisp bitmap art and shared theme styles. No hover tooltips, Tab/arrow focus cycling or focus-outline boxes; text caret and gameplay/canvas shortcuts remain allowed. Preserve pan/zoom and use the shared X for windows.
