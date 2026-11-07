# Leviathan: current development contract

## Read only what the task needs

- [TODO.md](TODO.md): active scenario architecture work (remaining P2e, then P3).
- [THOUGHTS.md](THOUGHTS.md): dated questions, concerns, UX/gameplay observations, imaginative improvement ideas and potentially valuable refactors; proposals are not implementation authorization.
- [THOUGHTS_ARCHIVE.md](THOUGHTS_ARCHIVE.md): resolved thoughts and their outcomes; consult only when relevant, not as an active backlog.
- [docs/HANGAR.md](docs/HANGAR.md): current gameplay, UI and persistence.
- [docs/SCENARIO_ARCHITECTURE.md](docs/SCENARIO_ARCHITECTURE.md): target architecture for content packs, procedural scenarios, the director, the Scenario Editor and Workshop; phases in TODO.md.
- [tests/README.md](tests/README.md): focused verification.
- [COMPLETED.md](COMPLETED.md): concise delivery record.
- [docs/STORY_SPEC.md](docs/STORY_SPEC.md): narrative reference, not an implementation backlog.
- [docs/history/](docs/history/): archived plans and reports, **not current requirements**. Do not load them routinely or restore retired behavior from them.
- [unused_resources/](unused_resources/): archived assets, excluded from Godot by `.gdignore`. Do not reference these from active code; its manifest records restoration paths.

## Workflow

- Put actionable plans in TODO.md before implementation. Move verified finished items into COMPLETED.md with a brief date/result; leave unfinished work and blockers open.
- During Godot project work, create or append to THOUGHTS.md as useful observations arise. Record questions, concerns, potential bad UX/gameplay, imaginative improvements and valuable refactors with context and possible next steps. Distinguish observations from proposals. When resolved, move the entry to THOUGHTS_ARCHIVE.md, preserving its original date/context and adding the resolution date/outcome; remove it from active thoughts. For partial resolutions, archive the resolved part and leave the open remainder in THOUGHTS.md. Preserve existing archive entries and avoid duplicates. Keep approved actionable work in TODO.md; neither thoughts file authorizes speculative changes.
- Commit completed, verified work periodically at coherent milestones, and push those commits to the configured remote branch without waiting for the user to ask. This is standing authorization for routine commits and pushes. Preserve unrelated user changes; do not force-push, rewrite published history or guess a remote destination. If no remote is configured or pushing is blocked, keep local commits, record the blocker in TODO.md and request the missing information.
- Run only the smallest relevant tests with isolated APPDATA. Use focused native visual/interaction checks for UI; scene-tree text alone does not establish visibility.
- Full baselines, all campaign variants, long soaks and broad native acceptance require explicit user request. Ask before expanding coverage; do not rerun unchanged passing checks.
- Await asynchronous checks and require their completed summary, not just an exit code or timeout. Documentation-only changes need document/link checks, not game suites.
- Keep player-facing text concise, necessary and nonredundant. Prefer recognizable icons, meters and in-world feedback. Preserve names, costs, non-obvious consequences and actionable errors.
- Research descriptions/toasts use one short gameplay sentence, without duplicate effect numbers, prerequisites, path commentary or refitting boilerplate.

## Guardrails

- Preserve gameplay, source artwork, ownership and saves. No unsolicited systems, optional equipment, ECM/Phase, new boss phases.
- Runtime: GameState is `scripts/hangar_state.gd`; management uses `scenes/game_map.tscn` and `scripts/hangar_screen.gd`.
- Hull is the only persistent health pool: zero is alive, strictly negative is destroyed. Flagship loss ends the run. Loads follow equipment UIDs; repairs never recreate lost loads. Repair Drone Hangars heal continuously; Flight Deck/Bomber Bay and carrier research are retired.
- Disregard backwards compatibility and don't worry about legacy saves in any regard.
-No hover tooltips, Tab/arrow focus cycling or focus-outline boxes; text caret and gameplay/canvas shortcuts remain allowed. Preserve pan/zoom and use the shared X for windows.
