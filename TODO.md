# Current slice TODO

Priority: finish the remaining D4 research work, then D5 fleet scale. Preserve the implemented travel/research/trade -> battle -> report/refit loop.

Current behavior: [docs/HANGAR.md](docs/HANGAR.md). Workflow: [AGENTS.md](AGENTS.md). Delivered work: [COMPLETED.md](COMPLETED.md).

## Publishing cleanup

- [ ] Push the committed cleanup work once a Git remote URL is supplied. No remote is configured; do not guess a destination or force-push.

## D4 - Research that you can feel

Research changes fleet behavior, not access to ordinary equipment. Keep the earned Prismatic Lasers, Siege I, Bastion II, Field Engineering and Civil Hospitality effects. Do not grant completed research/branches to make starting fits legal.

- [ ] Fewer random encounters: deferred until a random-encounter system exists; do not suppress authored/story encounters.
- [ ] Research raises the command limit as long-term fleet growth. Keep a few exclusive branch choices so runs differ.

## D5 - Scale to large fleets

- [ ] Support 20-30 fighters and 10-20 transports: raise the live battle-entity cap (currently 64 shared) and command budgets, profile 50-vs-40 battles at 5x, and cheapen distant AI if needed.
- [ ] Squadron-level battle HUD, health and reports; squadron-grouped Ships/Fleet views.

## Art dependency

- [ ] Recognizable derelict/distress/anomaly/gate and remaining equipment artwork is not supplied/approved yet. Preserve full names, effects and intentional pink missing-art markers; do not substitute unrelated ship/asteroid art or remove identifiers. Existing named map labels and fitted-equipment text fallbacks stay.

## Deferred reference, not active scope

The [older continuous-world expansion plan](docs/history/plans/CONTINUOUS_EXPEDITION_2026_11_04.md) preserves the former E01-E14 tasks, design contracts and unresolved work. It is archived, **not completed** and not a requirement for this slice. Procedural world cells/POIs, rescue/tow, seamless in-world combat, a new checkpoint format and broad performance/soak campaigns need an explicit scope decision before being resumed.

Keep [the story specification](docs/STORY_SPEC.md) as narrative reference; do not expand plot, branches, endings or Act II/III during D4/D5.
