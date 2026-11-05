# Completed work

Keep new entries brief: completion date, delivered behavior and focused verification. Historical reports are references, not standing retest requirements.

## 2026-11-05 - Standing Git workflow

- AGENTS.md now assigns periodic commits and pushes at completed, verified milestones to the agent, with standing user authorization. Preserve unrelated changes and published history; report blockers instead of guessing destinations or force-pushing.
- Preserved all 15 files of the older panel archive with verified manifest hashes alongside the different active panel pack; restored its manifest entries before committing.
- Configured the user-supplied origin, https://github.com/Allumnium/LeviathanProtocol.git, and fetched its master branch before publishing. The completed game changes retain their previously recorded focused verification; the workflow-only update required no game suites.

## 2026-11-05 - Two lab sizes and Large Plate

- Simplified physical labs to Lab (M), 1 RP/travel day, and Lab (XL), 3 RP/travel day. Removed the L lab, updated production labels and retained Research Methods/host bonuses. Predefined fits replace L labs with the user-approved Large Plate: +100 hull, mass 8, catalog price 160 credits. The science Survey retains cargo; Observatory retains its XL lab. No supplied large-plate artwork exists, so its art uses the intentional pink marker.
- Starting defensive/science output is now 1/1.25 RP per travel day; earlier opening timing measurements describe the previous fits. No pacing compensation or broad campaign retest was introduced. Existing current ownership is not automatically refitted.
- Isolated focused verification: research 183, refit 269 and research effects/matching 117 checks, zero failures. Native equipment checks passed 53 checks, including pointer fitting, Continue and actual output; reviewed Lab (M), Lab (XL) and Large Plate at 640x360, 1280x720 and 1920x1080. Expected certificate-store and existing shutdown resource diagnostics remain.

## 2026-11-05 - Meaningful research first pass

- Implemented the approved [20-card redesign](docs/RESEARCH_REDESIGN.md): meaningful laser, missile, carrier, repair, command and lab benefits; retained working behavior upgrades; simplified dependencies and visible tier names. Guided Munitions gives +25% missile range following the user's correction. Research Methods gives +20% then +40% total lab output alongside host bonuses. Shared 20/+20 RP progression and science flagship bonuses remain.
- Shared equipment capabilities drive effect applicability and deployed-fleet offers, including future variants. Saved offers survive refits; missing matches disable Choose without spending RP or rerolling. Lab III/Tactical Computers are normally available; Beam Lance/Bomber Bay are the only rare research equipment unlocks. Preserved ownership, finite reserves, equipment UIDs, hull boundaries and atomic choices/Continue.
- Isolated focused verification: 1,306 headless checks across redesign, choices, combat, carriers, science/research, abilities, refits and command; 93 native card checks; zero failures. Reviewed three/four-card and disabled-requirement layouts at 640x360, 1280x720 and 1920x1080. A bounded two-case opening playtest passed 24 checks with naturally earned offers and pointer selection: Research Methods raised defensive output 5 to 6 RP/day and science output 10.25 to 12.3 RP/day, retaining excess RP and the next 40 RP threshold.
- Expected malformed-effect rejection, certificate-store and existing shutdown resource diagnostics remain. No full baseline, campaign sweep, soak or performance profile was run.

## 2026-11-05 - Full research-line audit and redesign draft

- Audited all 20 offered research cards against active runtime consumers and equipment availability: nine active-effect cards, seven without a new combat/travel benefit and four equipment-access-only cards. Confirmed Siege II describes railgun penetration that is already baseline, and ordinary repair/carrier/mark equipment operates without its nominal research.
- Added [a complete redesign draft](docs/RESEARCH_REDESIGN.md) covering every line, proposed meaningful effects, prerequisite cleanup, tier naming, real exclusive paths, science output, equipment exceptions and offer relevance. Proposed Beam Lance/Bomber Bay as two rare unlocks whose cards also strengthen existing builds; asked the user to decide equipment access first.
- Verified 20/20 catalog coverage, category uniqueness, document/source links and whitespace. No runtime code, effect values, pacing or equipment availability changed; the subsequent approved implementation is recorded above. Documentation-only work did not rerun game suites.

## 2026-11-04 - Opening research card playtest

- Ran a bounded native opening on seed 7341 with normal starting fits, normal travel/reward RP, authored events and the actual opening battle; no RP injection, extra equipment or encounter suppression. Exercised the first naturally earned three/four-card offers, Continue and pointer selection. Twenty-two checks passed; reviewed native captures. This was two opening cases, not a campaign sweep or broad acceptance run.
- Defensive flagship: 5 RP/day; first choice after the opening victory at 142.74 NU / 3.568 travel days / 35.7 travel simulation seconds, with 17.842 travel RP plus the existing 4 RP victory reward. The battle lasted 19.27 combat seconds. Research flagship: 10.25 RP/day with its starting lab fit; first choice at 78.67 NU / 1.967 days / 19.67 travel simulation seconds, before the first signal.
- Seeded offers were Field Engineering / Laboratory II / Command I, plus Fleet Logistics I for the research flagship. Pointer-selecting Field Engineering raised cruise rate from 4 to 5 NU/s and advanced the shared threshold to 40 RP, retaining excess earnings.
- Found redundant access-only choices: Laboratory II and Command I provide no immediate benefit because their equipment is already available; source inspection confirmed the same issue for Applied Energy and Guided Munitions. Presented a concrete pool/effect decision to the user and left it open in TODO. No production code, balance, upgrade effects or pacing changed.

## 2026-11-04 - Research upgrade cards

- Replaced the research tree screen and focused projects with a shared research bar: 20 RP for the first choice, then +20 per chosen upgrade, carrying fractional/excess RP into subsequent choices. Three unique seeded eligible cards offer full names, one gameplay sentence and Choose. The Research Flagship adds a fourth card while retaining its +25% installed-lab output.
- Preserved backend prerequisites, story gates, exclusive branches and existing grants/effects. Cards disclose branch-lock consequences, and depleted pools offer remaining upgrades without duplicates/filler. Pending cards/order and RP are saved; readiness and choices commit atomically, failed saves roll back, and Continue/reopening cannot reroll an offer.
- Cards open over the current view, wait for existing windows, and pause travel while visible. Shared X defers the same cards and resumes previous travel; the header reopens them and shows exact RP/threshold, readable bar and daily output. Removed obsolete tree scripts and updated affected tests.
- Isolated focused verification: 555 headless checks (choice mechanics/readiness rollback, ranked labs, command capacity, research travel and expedition-state validation), plus 73 native card/header/input checks, zero failures. Reviewed three/four-card captures at 640x360, 1280x720 and 1920x1080 and next-bar header progress. Updated remaining test scripts compile; existing certificate-store and shutdown resource diagnostics remain. No full baseline, campaign sweep or soak.

## 2026-11-04 - Shared battle command frame

- Battle now uses the main screen's shared command header and authored side/footer panel component. Allied squadrons appear left, enemies grouped by name right, active abilities along the bottom and time controls above. Retained original hull/shield artwork, counts and losses; lists include reinforcements and enemy rows obey visibility. The footer remains visible without abilities.
- Camera framing uses the open central battlefield; pan, pointer-centered zoom, ability targeting and frame input boundaries remain functional. Embedded ability controls use one row inside the footer. The command frame hides for battle results.
- Isolated focused verification: 124 native research/ability/frame checks and 233 headless fleet/health checks, zero failures. Reviewed supported-resolution battle captures and the empty footer. Existing certificate-store and renderer/ObjectDB shutdown diagnostics remain; no broad baseline, performance rerun or soak.

## 2026-11-04 - Large-battle performance and fast-forward pacing (D5)

- Added fine spatial queries for separation and scout cover, preserving the original eligible neighbors and separation sum order. Cached physical support/lab indexes invalidate on stat refresh, and enemy steering scans eligible anchors while retaining the same nearest-anchor result. Empty query results avoid repeated temporary allocations; exact silhouette sweeps still decide projectile hits after conservative bounds and per-step shape reuse.
- Removed redundant beam segments when fog is disabled, reduced subpixel exhaust detail and generated cached shield masks from alpha bytes. Source artwork/alpha, combat tick rate, hull/ownership, weapon cooldowns, research effects and finite carrier allowances remain intact.
- Fixed routine fast-forward clock loss at the old per-frame step cap. Work remains bounded to eight simulation steps per callback with at most one simulated second of catch-up; ordinary frames recover retained time, while extreme stalls remain bounded. Native profiling now distinguishes a fixed 60Hz frame workload from actual wall-clock pacing and writes the timing/backlog metrics to isolated JSON.
- Final fixed-budget native 50-vs-40 profile at 1280x720: 18.4ms median / 31.8ms p95 / 76.0ms worst, versus the earlier roughly 27/45/90ms reference. The final paced run advanced 8.47 combat seconds in 1.76 wall seconds (4.80x effective at the 5x setting), with 0.027 simulated seconds discarded by the bounded stall guard; another clean paced run measured 4.96x with effectively zero discarded time. Paced frames batch more ticks, so their frame percentiles are not comparable to fixed-budget results. This short workload does not establish universal 60fps or long-soak performance.
- Focused isolated verification: scale/query/cache/clock 233 checks, sprite collision 7,877, carriers 290, research-combat behavior 207, plus deterministic replay; zero failures. Final native profiling/mask checks passed in both modes (10 checks each); reviewed battle captures at supported resolutions. Corrected the carrier cap fixture to use the shared 192 limit. Expected malformed-effect rejection, certificate-store errors and existing shutdown resource diagnostics remain; no broad baseline or soak. Remaining D5 performance item moved out of TODO.

## 2026-11-04 - Original hull and shield bar artwork

- Restored the blue `ProgressLv` shield fill, matching background and both import sidecars from the archive to their original paths, verifying all four SHA-256 hashes before and after moving; removed restored entries from the archive manifest. Source artwork and import bytes are unchanged.
- Shared bar styling now insets the original orange hull/blue shield foregrounds inside full-width backgrounds, without tint substitutions. Battle squadron meters, management stat/condition bars and ship tiles retain visible empty tracks and borders, including full and zero values.
- Focused isolated verification: 56 stat/metadata checks and 19 native checks, zero failures/script errors. Reviewed empty/half/full examples, partial hull/shields in battle at 640x360/1280x720/1920x1080, and Ships/Fleet captures. Environment certificate-store and existing renderer shutdown diagnostics remain; no game baseline/profile rerun.

## 2026-11-04 - Large fleets and squadron readouts (D5 increment)

- Fleet Logistics III now grants a total +108 command bonus; even the Research Flagship's base budget supports 30 fighters and 20 transports. Initial command budgets, research costs/branches, fitted purchases and atomic persistence remain intact. All live spawn paths share a 192-combatant budget; authored enemy rosters and finite equipment UID allowances remain unchanged.
- Added squadron survivor counts and aggregate hull/shield meters in battle, named squadron grouping in Ships/Fleet, and compact squadron report rows with summed damage/deflection, explicit losses and surviving repair HP. Zero hull remains alive; destroyed hosts never add health. Result panels hide the squadron HUD, and three friendly squadron rows fit at 640x360.
- Profiled the requested short deterministic 50-vs-40 fight at the 5x setting. Distant idle-gun retry timing, range-bounded weapon queries, distance-first enemy targeting filters and skipping absent repair work reduced measured costs. Interception, nearby guns and explicit orders bypass idle retries; movement/tick/cooldown timing is retained and retry timers participate in replay snapshots.
- Verification: final large-fleet logic 23 checks; command research 82; battle outcomes 153; replay zero failures. Native grouped Ships/Fleet pointer selection passed at 640x360, 1280x720 and 1920x1080; final focused battle/report pass 23 checks, zero failures/script errors, with captures reviewed. Expected failed-save diagnostics, environment certificate-store errors and existing renderer/resource shutdown warnings remain. No broad baseline/soak.
- Remaining performance work is open in TODO: final native profile measured 102 frames / 8.47 simulated seconds, 2.94s wall time, 26.9ms median / 44.9ms p95 / 89.6ms worst frame. This is a short 5x fixed-step workload, not proof of stable real-time 5x or 60fps.

## 2026-11-04 - Research command capacity (D4 increment)

- Shared Fleet Logistics I/II/III cost 20/60/120 RP and raise the research command bonus to +8/+24/+48 above the flagship base; higher tiers replace earlier bonuses. Existing exclusive combat branches remain exclusive. New Run retains Foundation only and base command capacity.
- Purchases, squadron purchases, rescues, deployment and checkpoint validation agree on earned capacity. Continue derives it from research without new save fields; failed research/purchase saves preserve RP, money, fleet, equipment, groups and completion feedback.
- Isolated focused verification: 82 headless logic checks and 38 native interaction/layout checks, zero failures/script errors. Reviewed research captures at 640x360, 1280x720 and 1920x1080 plus Fleet capacity/completion feedback. Environment certificate-store and existing renderer shutdown diagnostics remain; no full baseline run.
- Remaining D4 encounter reduction is deferred until random encounters exist. D5 fleet scale is next; publishing still awaits a Git remote URL.

## 2026-11-04 - Activated combat research (D4 increment)

- Disruption I grants the existing Ion Pulse: a living installed Ion Emitter interrupts a visible enemy's charge and suppresses shield recovery for four seconds, with a fleet-wide 24-second cooldown. Existing ability-bar targeting, optional Auto and Pause Aim work in physical battles; single-source fleets omit the redundant source picker.
- Cooldowns/effects use battle simulation time and restart with the encounter on Continue, like weapon cooldowns. No resource costs, save fields, fog/AI changes or deferred equipment grants. Physical replay snapshots include abilities; source/target loss removes suppression and its ring follows the target. Escort casting ranges use actual scaled mounts.
- Focused isolated verification: 74 native ability checks and 53 headless retained battle-UI checks, zero failures/script errors. Covered earned/unequipped gating, Continue, manual/Auto, range, interruption/recovery, source/target loss, replay, three-resolution layout, actual battle pointer casts, pause and 2x cooldown timing; reviewed native battle capture. Known renderer shutdown warnings remain; no full baseline run.

## 2026-11-04 - Faster cruise research (D4 increment)

- Field Engineering now adds 25% cruise speed alongside its existing 25% fuel-per-distance reduction. Actual movement and both ETA displays share the researched rate; one short detail/toast sentence covers both benefits.
- Simulation-time repair/combat/idle clocks, journey distance-based fuel/research/income and authored encounter positions remain unchanged. Effects derive from existing earned research on Continue and start after the earning frame; no save fields, equipment, price or prerequisite changes.
- Focused isolated verification: travel research 237 headless / 239 native checks; default navigation 167 checks, all zero failures. Covered speed/frame invariance, fuel/event/arrival clipping, authored zone admission, mid-route unlocks, Continue, atomic rollback, both ETAs and three-resolution UI; reviewed native Map/research captures. Existing renderer shutdown warnings remain; no full baseline run.
- Random-encounter reduction remains deferred/open because the demo uses authored encounters, not a random-encounter system. Publishing remains blocked by the missing Git remote.

## 2026-11-04 - Incremental delivery permission

- Updated the personal Godot instructions to authorize automatic task-scoped staging, verified incremental commits and pushes to configured upstreams, without repeated approval. Preserve unrelated work; never force-push or guess a remote.
- Added the research-travel test's source UID sidecar after checking its format and uniqueness. Cleanup commits are local; publishing remains blocked in TODO until a remote URL is supplied.

## 2026-11-04 - Repository housekeeping

- Git-ignored `.godot/`, `*~` and `*.log`; removed 1,337 generated cache files from Git's index without deleting or changing their local contents. Source `.import` settings and script `.uid` sidecars remain versioned; archived backups remain versioned.
- Moved four root logs into ignored `.local/checks/historical-root-logs/` and documented `.local/checks/<task>/` for future outputs. Saved workspace Explorer exclusions for import sidecars/editor backups.
- Archived two disconnected broken builder scenes, obsolete help and two retired stock controls (seven files including UIDs) in [docs/history/retired_ui/](docs/history/retired_ui/), excluded by `.gdignore`. Preserved original bytes/layout and all active compatibility/test dependencies; kept the test-used save-design dialog.
- Verified ignore rules, cache preservation, relocated hashes and no active references to retired paths. Focused isolated headless checks completed: retained-scene/menu/management startup 17 checks; legacy archives 66 checks; zero failures/script errors. No full baselines or native acceptance run; no gameplay/UI behavior changed.

## 2026-11-04 - Unused resource archive

- Moved 405 unused tracked resources (sprites/textures, seven font alternatives, eleven audio tracks/cues, source packs and editor backups) plus 353 import sidecars into [unused_resources/](unused_resources/), preserving all file bytes. Original relative layout is retained except one preview filename shortened for Windows; [manifest.json](unused_resources/manifest.json) records exact original paths, sizes and SHA-256 hashes for restoration. A `.gdignore` excludes the archive from Godot imports/exports.
- Kept resources referenced by runtime, catalogs or runnable tests, including dynamically paired surface maps, bitmap font pages and font license metadata. Untracked editor files were left untouched.
- Verified all 758 moved files against source hashes and Git originals; retained assets are unchanged and active code/catalog/test references remain valid. Isolated native resource/startup check completed 516 checks with zero failures, loading retained resources and opening menu, Map, Fleet, Ships and Research; reviewed menu/Map/Ships captures. Test-only raw-font-image export warning and renderer shutdown diagnostics were emitted; no script/parse errors. No full suites run.

## 2026-11-04 - Documentation cleanup

- Archived 45 superseded documents plus five former-guidance/history snapshots under [docs/history/](docs/history/). Current slice/D4/D5 stay active; older E01-E14 work is deferred, not completed.
- Replaced conflicting instructions and accumulated hangar notes with compact current contracts; retained mount rules, ownership/save guards, UI preferences and focused test invocation. Story specification remains narrative reference.
- Verified every archive against its original (only banners/relative links changed), byte-preserved both NUL-containing old plans, retained all 81 prior open tasks in the historical plan, and introduced no broken local Markdown links. No game suites run; no gameplay, art or saves changed.

## Delivered before 2026-11-04

- U1-U4: meaningful-text/diegetic UI pass (remaining artwork approval stays in TODO).
- D1: fully fitted ship purchases, free shipyard refits, majority starting equipment access, four advanced research gates and Foundation-only starts.
- D2: atomic rewards/rescued ships and persistent fleet missile supply.
- D3: same-chassis squadrons, stances, group actions and formation movement.
- D4, partial: Prismatic Lasers, splitting missiles, shield pulses, reduced cruise fuel and distance-funded credits. Remaining research work stays in TODO.
- Godot preferences applied to project workflow and existing backlog; verified task preservation, new links and whitespace without game suites.

The [full prior completion record](docs/history/reports/COMPLETED_THROUGH_2026_11_04.md) preserves all 87 original completed entries, the workflow update and recorded acceptance results. It does not imply the remaining expansion plan is finished.
