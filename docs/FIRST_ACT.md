# First-act vertical slice / Gate F

Review date: October 30, 2026. Scope: required steps 50-54, with optional extras deferred.

## Research and guidance

New runs use Laboratory II / III prices of 12 / 24 RP. A living deployed lab still produces exactly 1 RP/day at every rank, plus the fleet's 0.5 RP/day baseline. One lab can fund Lab II after eight travel days; Lab III remains gated by the Warden. Other research prices remain unchanged pending the broader Act II pacing review in step 61. No battle-time farming or rank production multiplier was added.

Research pricing is versioned in run progress. Historical runs without the field keep their original 40 / 80 RP lab prices and ledger; a 35/40 partial project remains valid. Validation, allocation, compatibility purchases and the live tree use the same price rule. New costs apply to new runs, without silently refunding, discarding or completing existing projects.

The explicitly opened How to Play panel now covers adjacency, research, boarding/trade, Scan and optional mining. Scan/Seismic Cut targeting shows a short inline click instruction in the existing action bar. There are no new navigation buttons, automatic popups or hover tooltips. Equipment definitions replace the lab's obsolete section reference and vague crew description with concrete rules.

## Full-act checks

The Warden suite traverses all eight first-act journeys for seeds 42, 1357 and 12345, each with three starting Drones and again with a purchased Surveyor. Each route uses actual frozen encounters and visibility, Auto combat, real damage and paid repairs, real daily research and a reload after every arrival. Science routes construct a paid Lab II family revision at the row-four shipyard within normal capacity; historical hulls stay out of deployment. Each run reaches the teaching pylon, wins the Warden and opens capacity 42 exactly once.

| Seed | Starter-only credits at act end | One-lab / paid Lab II revision credits |
|---|---:|---:|
| 42 | 825 | 736 |
| 1357 | 825 | 716 |
| 12345 | 825 | 722 |

These are representative routes, not an exhaustive balance claim. The existing nine opening routes separately exercise Applied Energy and paid laser refits, including cargo fleets. Wider doctrine comparisons remain optional; the remaining campaign is still required work.

## Gate F review

| Concern | Required evidence |
|---|---|
| Persistence / economy | Atomic checkpoints, failed-save retries, immutable frozen encounters, replay-safe rewards, passenger losses/debt, cargo sale/refill and paid family revisions |
| Visibility / targeting | Shared player/Auto observations; radar stays coarse; hidden boss charge/beam changes produce identical pixels; pointer can separately target body and pylons |
| Finite ore | Asteroid mass conservation, extraction caps, durable pickup retry and replay; ore produces materials rather than RP |
| Progression | Six full-act Auto routes; researched and paid Lab II; Warden story gate and capacity unlock once; next-act routes available |
| Minimum resolution / clocks | Native 640x360 research tree, Scan, Cutter and Warden; real pointer input, pause and 2x controller checks; boss briefing and travel frame fit without scrolling |

All 45 baseline suites pass in .local/first-act/baseline.log (isolated saves: .local/checks/f3b7744952e1404f920c00d733be82ee/). Four native suites pass in .local/first-act/native-{research_ui,abilities,mining,warden}.log. Strengthened historical checkpoint/UI price assertions also pass in compat-research_focus.log and compat-research_ui.log. Minimum-size captures were visually inspected at .local/research-tree/captures/tree-640x360.png, .local/step39/scan-preview.png, .local/asteroids/mining-ui.png and docs/ui-review/warden-{controller,preview}-640.png. UI placement/add/remove measured 47/275/216 ms, below the existing guards. Known Windows certificate-store and engine shutdown diagnostics are tracked separately from gameplay assertions. Gate F covers the first act only; it is not a full-campaign MVP sign-off.
