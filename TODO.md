# Current slice TODO

The current D4/D5 implementation is delivered. Open dependencies remain below; D4's random-encounter effect is deferred. Preserve the implemented travel/research/trade -> battle -> report/refit loop.

Current behavior: [docs/HANGAR.md](docs/HANGAR.md). Workflow: [AGENTS.md](AGENTS.md). Delivered work: [COMPLETED.md](COMPLETED.md).

## Fleet redesign - discussion before implementation

- [ ] Agree deployment selection granularity and persistence, then approve a bounded redesign slice. No battle setup or Fleet/Ships consolidation is implemented yet.

Recommended sequence:
1. Battle deployment: freeze combat, support, abilities and encounter timers; arrange allied squadrons in the mission's deployment area, preserving fog rules and pan/zoom; top-center Begin Combat commits deployment. Decide whether individual ships can also move and whether Continue returns to setup.
2. Fleet inspection: reuse the existing ship editor for equipment/mount details, per-mount refits, loads, individual repair/salvage and split/join actions inside Fleet. Preserve squadron defaults, overrides, purchases and station-service restrictions; remove Ships only after parity.
3. Management presentation: replace editable tactical placement with orderly escorts beside the flagship; battle setup becomes the formation editor. This is a presentation change, not a second ownership or loadout system.

## D4 - Research that you can feel

Research changes fleet behavior, not access to ordinary equipment. Keep the earned Prismatic Lasers, Siege I, Bastion I, Field Engineering and Civil Hospitality effects. Do not grant completed research/branches to make starting fits legal.

- [ ] Fewer random encounters: deferred until a random-encounter system exists; do not suppress authored/story encounters.

## Art dependency

- [ ] Recognizable derelict/distress/anomaly/gate and remaining equipment artwork is not supplied/approved yet. Preserve full names, effects and intentional pink missing-art markers; do not substitute unrelated ship/asteroid art or remove identifiers. Existing named map labels and fitted-equipment text fallbacks stay.

## Deferred reference, not active scope

The [older continuous-world expansion plan](docs/history/plans/CONTINUOUS_EXPEDITION_2026_11_04.md) preserves the former E01-E14 tasks, design contracts and unresolved work. It is archived, **not completed** and not a requirement for this slice. Procedural world cells/POIs, rescue/tow, seamless in-world combat, a new checkpoint format and broad performance/soak campaigns need an explicit scope decision before being resumed.

Keep [the story specification](docs/STORY_SPEC.md) as narrative reference; do not expand plot, branches, endings or Act II/III during D4/D5.
