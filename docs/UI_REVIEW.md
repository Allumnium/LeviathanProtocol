# Step 30a: current UI review and requested corrections

## Current owner revision: general slots and reduced HUD (2026-10-28)

This supersedes older five-slot, dedicated-support, Port/Story and header-stat descriptions below. Fleet now has three general design selectors. Players combine researched science, combat, cargo, accommodation and mining equipment themselves; there are no bonus slots, singleton support ships or role-based equipment limits. Legacy support ships migrate into general families without losing identity, damage, passengers, cargo or accounting. Pending attempts retain membership; retries use current selected revisions.

Removed Port/Story controls, their service/narrative prose and automatic story popups. Story flags/gates and inhabited arrivals still progress underneath. The header shows resources and level, without Act/row or duplicate fleet statistics. Fleet Summary owns deployed/owned counts, hull percentage and damaged count. Construction orders, contextual Salvage/Reserve and shared typography/styles remain.

Native rendered checks at 640×360, 1280×720 and 1920×1080 pass; see [current fleet](ui-review/general-fleet.png). tests/test_general_fleet.gd checks mixed equipment, multiple support-capable copies, damaged/loaded legacy conversion, durable migration, in-flight withdrawal/retry, absent controls/popups and HUD values. Logs/captures: .local/unified-fleet/. TODO.md, AGENTS.md and the design plan owner revision define the remaining work. The original review below is historical where superseded by this revision. Verification: 30 existing regression suites pass across the baseline and affected reruns, plus the new general-fleet suite (31 total), including 600 battles, 1,000 graph/content seeds and three complete campaigns. Final logs are in .local/unified-fleet/. Known certificate-store/shutdown diagnostics remain separate from assertions.

Reviewed 2026-10-28. The current result follows the owner's preferences in [AGENTS.md](../AGENTS.md): Starhull, no hover tooltips except the conditional Ship Designer lock, no Tab/arrow UI cycling or focus boxes, three visible general design slots, contextual ship actions, a separate reserve modal, and credits covering construction-material shortages. Do not add features outside the requested milestones.

## Theme ownership

Mission Setup font-artifact fix (2026-10-28): Starhull's BMFont described every
glyph as a full 13px atlas row. The underscore occupies y=51 immediately above
the old lowercase-o UV at y=52, matching the stray bars above o in the reported
scaled text. Tightened all glyph rectangles to their actual ink and adjusted
offsets to preserve baseline/ink placement, letter advances and line height.
Blank glyphs now have zero-area UVs. The source PNG, shared theme font and integer
scaling policy are unchanged. This removes neighboring-texel exposure throughout
the UI rather than substituting a font or adding scene overrides.

`tests/test_bitmap_font.gd` checks imported UVs/metrics and renders all three
difficulties with the checkpoint warning at 640×360, 1240×835 and 1920×1080.
Native checks pass; screenshots/logs: `.local/mission-font/after/` and
`.local/mission-font/after.log`. Broader UI interaction checks are in
`.local/mission-font/ui.log`. Existing certificate/shutdown diagnostics remain.

`themes/ui_theme.tres` owns the UI font and reusable styles. Change **default_font** to change the body font everywhere; **default_font_size** sets its size. Labels, buttons, text inputs, popups, reports and dynamically created controls inherit it. There are no per-control font resources or fallback-font overrides. The branded main-menu heading is a separate **GameTitle** variation in that same theme, with adaptive fitting.

Reusable variations cover CompactButton, FramedButton, IconButton, TinyIconButton, ArchiveButton, ResearchButton, ContextPanel, ResearchPanel, LibraryRow, RoutePanel, CompactPanel/Frame/Popup, CrispPopup/Panel and CountBadge. Scene-specific panel style overrides and runtime copies of button styles were replaced by these variations. The builder's colored component outlines remain game-data visuals, not focus decorations.

Starhull's bitmap import permits integer scaling instead of fractional resampling (13px default, 26px for double size). Scalable replacement fonts follow the theme size normally. The first review's replacement system font and keyboard-focus treatment did not match the owner's preferences; they have been removed. UI navigation actions are unbound, ordinary controls reject keyboard focus, and focus style boxes are empty. Text fields retain caret/editing behavior; canvas/gameplay shortcuts and Escape still work.

## Findings and fixes

| Finding / severity | Reproduction and consequence | Current fix / verification |
| --- | --- | --- |
| Fleet cards hide four slots — major | Open Fleet at 640×360. Tall cards clip names against frames and force scrolling. | Five aligned 24px rows, inset names and previews; Port/Story share one row. All slots and services are checked inside the panel at 640×360, 1280×720 and 1920×1080. |
| Font/style overrides bypass the theme — major | Change the theme font: fallback fonts and per-control resources keep parts of the UI unchanged. | Inherited typography and named theme variations. An interaction test swaps the theme font and verifies multiple labels/buttons update together. |
| Focus outlines/navigation are unwanted — major | Click a control or use Tab/arrows: blue outlines appear and focus cycles. | Removed generated texture-button outlines and focus cycles; disabled default UI navigation actions, including popup-menu arrows. Text entry and game controls remain functional. |
| Hover-dependent information — major | Costs and restrictions appear only on hover. | Removed all hover tooltips except Ship Designer's lock. Construction shows a quantity-based order; repair keeps its clicked quote. Selected-hull Salvage executes immediately without confirmation, as requested. Restrictions/errors appear inline. Research and locked library choices have clicked reviews. |
| Repeated per-ship summary actions — moderate | Fleet summary repeats Reserve/Deploy/repair for every owned hull. | Summary shows totals and one Reserve button. Selecting exactly one visible hull shows small contextual actions beside it; no/group selection hides them. Actions track layout, pan/zoom and viewport bounds. |
| Reserved hulls still clutter formation — moderate | Reserve a ship: a dimmed, selectable hull remains on the board. | Reserves and historical inactive copies are absent from formation rendering, fitting, hit testing and group movement. A small, paged reserve modal lists them and restores eligible hulls through Deploy/Use Revision. |
| Unrequested material shop — major | Port services offer individual construction-material purchases. | Removed both the shop and standalone purchase API. Construction, repair and existing material-consuming upgrades use stock first, then charge shortages at the configured rates. Debt still permits zero-credit actions paid with stock. |
| Fleet add/remove stalls — major | Add/remove a hull with the map open; synchronous callbacks repeat expensive work. | Coalesce fleet/accounting refreshes once per transaction, reuse surviving preview nodes, skip hidden builder-stat rebuilding and omit invisible slot-cost widgets. No checkpoint validation or write guarantees were weakened. |
| Trapped library / broken Help — major | Dismiss the library and it reopens; long Help exceeds the popup. | Respect dismissal, focus search, show empty results; bounded Help scrolling with current instructions. Nested Escape cancels an inner confirmation first. |
| Silent save/travel/result failures — moderate | Save a blueprint, attempt unready travel or encounter a failed write. | SAVED acknowledgment, inline departure/retry/failure messages, priced-action write failure feedback, clear battle objectives and result actions. Continue uses validated checkpoint/backup recovery and explains failures. |

## Evidence

| Screen | Before | Current |
| --- | --- | --- |
| Fleet | [Original](ui-review/fleet-before.png), [rejected scrolling revision](ui-review/fleet-rejected-scroll.png) | [Selected hull/actions](ui-review/fleet-after.png), [reserve hidden](ui-review/fleet-reserved.png), [reserve modal](ui-review/reserve-modal.png) |
| Builder | [Before](ui-review/builder-before.png) | [After](ui-review/builder-after.png) |
| Help | [Before](ui-review/help-before.png) | [After](ui-review/help-after.png) |
| Port | [Before](ui-review/port-before.png) | [After: no material shop](ui-review/port-after.png) |
| Prices | Hover-only cost information was removed. | [Construction order](ui-review/construction-order.png), [640px order](ui-review/construction-review.png), [repair review](ui-review/repair-review.png) |

The complete rendered PNGs and control/font metadata are in `.local/ui-corrected-capture/{640x360,1280x720,1920x1080}/`. `tests/ui_review_capture.gd` reproduces these using actual viewport rendering.

## Interaction, performance and regression checks

Native Windows Godot **4.7.2 stable**, OpenGL 3.3 Compatibility, NVIDIA RTX 5060 Ti / driver 610.88. All launches isolate `APPDATA` and use test saves; the user's campaign and blueprints are not used.

`tests/test_ui_review.gd` uses real Godot mouse/key dispatch through hit testing and embedded popup routing. It covers start/setup/settings, no Tab cycling, text-entry isolation, shared theme-font updates, all five slot bounds at three sizes, single/group/empty ship selection, Reserve/Deploy through the modal, repair/construction quotes, immediate selected-hull salvage, cancel/failed-write preservation, stock-only actions in debt, no material shop, research, travel preview, battle controls/retreat/report, Continue/backup recovery, corrupt loads, interrupted reserve recovery and terminal defeat.

## Owner-requested construction orders and salvage (2026-10-28)

Removed minus buttons from every shop slot. A single selected formation hull now
has Salvage beside Reserve. Salvage immediately dismantles that exact physical
hull without a confirmation; occupied/loaded ships and unavailable ports remain
guarded, and failed writes leave the hull/materials intact.

Construct Ships uses two columns: left preview, base per-ship material sprites and
full credit equivalent, then a high-level equipment summary; right quantity and
the actual order's required materials, stock used, shortage credit charges and total.
Both areas use existing material/credit sprites. Quantity starts at one and accepts
arrows or typed whole numbers; changing it reprices the entire order. The shared
top-right X dismisses the window and Construct is bottom center, with no Cancel
button. All fonts/styles inherit the shared theme. No scrolling is required at
640×360, 1280×720 or 1920×1080.

The whole order uses owned stock once, buys only shortages with credits and writes
all physical hulls, identities, inventory and funds in one checkpoint. There is no
per-order gameplay count cap; affordability and existing slot rules apply. Extra
Science/Civic copies enter reserve, preserving the active support hull. A submission
guard prevents repeated clicks from building the order twice.

`tests/test_construction_orders.gd` covers mixed stock/credit totals, failed batch
writes and retries, identity/reload, unaffordable/invalid quantities, support reserves,
real quantity-arrow/typing/Construct/X/Salvage input and layouts at all three sizes.
Native OpenGL screenshots are in `.local/construction-order/`; focused logs are
`orders-final.log` and `rendered.log` there. Baseline results are recorded in
`.local/construction-order/baseline.log`. Existing certificate and shutdown resource
diagnostics remain separate from gameplay assertions.

Construction follow-up validation: all 30 baseline suites passed, including 600
battle encounters, 1,000 graph seeds, 1,000 content seeds and three complete
campaigns. Final focused native construction checks also pass after the quantity
entry/submission and reserve-placement refinements. Logs:
`.local/construction-order/baseline.log`, `.local/construction-order/rendered.log`
and `.local/checks/ceb40b8a45dc4867add74f7dc774954a/`.

Before optimization, the isolated profile measured about **124 ms backend / 710 ms with UI** for adding a ship and **131 ms / 499 ms** for removal. Afterward the synchronous UI calls measured about **192/175 ms**. The native interaction check, including deferred refresh/render frames, measured about **342/287 ms** for add/remove and **72 ms** for a block placement. The performance guard is 600 ms for these test fleet edits; this is not a 60fps guarantee or a benchmark for arbitrarily large reserve fleets.

All 27 baseline suites pass across the baseline run and affected reruns, including **600 battle encounters**, **1000 graph seeds**, **1000 content seeds**, transaction failure/reload, passenger/debt, capacity, research and assembly. The capacity UI assertion now checks inline text after the coalesced render update instead of a tooltip. Logs: `.local/ui-corrections-baseline.log`, `.local/ui-corrections-test_fleet_capacity.log`, `.local/ui-corrections-test_ship_stats.log`, `.local/ui-corrections-test_recipes.log`, `.local/ui-wildcard-test_battle.log`, `.local/ui-final-verification.log`, `.local/wildcard-final-check.log`.

Browser/Playwright coverage was unavailable: no runnable web export, web export templates or working Playwright package were present. External desktop automation could enumerate the editor but not the separately launched review window. The recorded fallback is native GPU rendering and engine input dispatch, not external OS pointer coverage. Native launches still emit the environment's root-certificate error and known shutdown texture/ObjectDB resource warnings; these are recorded rather than suppressed. No script/runtime UI errors remain in the final interaction checks.

Later cargo UI and final polish remain in the existing milestones. No additional feature work is authorized by this review.

## Research owner revision - October 28, 2026

Replaced the grant-review/instant-purchase UI with Research Categories, a connected pannable/zoomable node canvas, and right-panel effects/progress plus Set Research Focus. Prerequisite ancestors remain visible across categories. Removed View Grants, node modals, unsupported triangle glyphs, next labels and duplicate RP balances, including Fleet's Victory RP line. The unspent balance is now in the resource header. Research-specific panel widths preserve readable Starhull text and a visible focus action; large trees pan rather than shrink automatically. Selected-project progress/cost remains in details. The default canvas font and button styles inherit the shared theme; no local font resources or tooltips were added.

Native Godot pointer tests at 640x360, 1280x720 and 1920x1080 cover category selection, node selection without a modal, background dragging, wheel zoom and focus/header bounds. Captures are in .local/research-focus/captures; research-foundation.png and research-science.png preserve the 1920x1080 evidence here in docs/ui-review. This is native GPU rendering and Godot input dispatch; no browser/Playwright coverage is claimed.

Research focus, partial progress, switching/reload, completion/overflow, old-save defaults, prerequisites, failed focus/reward writes and reward deduplication pass tests/test_research_focus.gd. Forward map-row distance times frozen deployed lab productivity funds projects on completed combat and quiet journeys; elapsed battle time earns nothing. Logs: .local/research-focus/focus.log, ui.log and render.log. Existing certificate-store and shutdown resource diagnostics remain separate from assertions.

Full regression: all 33 suites report zero failures in .local/research-focus/baseline.log and .local/checks/5703fc4abf004d669be9c469944a6f2d/, including 600 battle cases, 1,000 topology seeds and 1,000 content seeds. Final expanded focus and native pointer tests passed after the baseline. Whitespace checks passed. The baseline PowerShell wrapper returned exit 1 after native certificate-store stderr, while each Godot suite completed with zero assertion failures and the runner reached its final log-path output.

## Latest owner revision: unified tree and days

This supersedes the category-filter and distance-unit research presentation recorded above. Foundation is assumed/hidden. All available technologies share one pannable/zoomable canvas with categories as connected major branches. Complete nodes draw a green check above their name; partial nodes display current / required RP in that space. The right panel uses only the selected name, unlock names/essential numbers, requirements when blocked, cost/progress and Set Focus/Focused. Category controls and explanatory research prose are removed.

The left panel now shows lab count, +0.5 baseline, RP/day and the selected route's days/arrival RP. Every living deployed lab counts, including multiple labs per hull. Production is (labs + 0.5) * planned travel days at one RP/day per lab; adjacent routes vary from two to four days by route length. Fractional RP persists through bank/project accounting, ledger replay and checkpoint reload. The map animation and battle duration do not change the frozen award. Current owner preferences are in AGENTS.md and the current behavior in RESEARCH.md/SCIENCE.md; remaining TODO pacing uses days and calls for retuning the old research costs.

Native tests cover 640x360, 1280x720 and 1920x1080, actual node/focus/pan/wheel input, checks/half-RP markers, production updates after route selection and viewport containment. A transient wrapped-label minimum expanded the workspace during review; initializing label width fixed it and bounds assertions now cover that regression. Captures/logs are in .local/research-tree/. No browser input coverage is claimed. Earlier validation logs remain historical; the current run and final focused reruns are recorded below when complete.

**Latest research verification:** All 33 isolated suites pass across .local/research-tree/baseline-final.log (18 suites) and the 15 remaining test_*-output.log files in .local/research-tree/. This includes 600 battle encounters, 1,000 topology seeds, 1,000 content seeds, three complete campaigns, ledger/reload checks and native UI input. The transaction replay fixture was updated to replay its actual RP/duration details. Final focus/half-point checks pass in focus-final.log, the complete 45-node detached-tree hierarchy passes in ui-final.log, and native 640x360/1280x720/1920x1080 rendering/input passes in render-final.log. Evidence: docs/ui-review/research-unified.png and research-overview.png. Whitespace checks pass. Existing certificate-store and shutdown-resource diagnostics remain separate from assertions; no browser/Playwright coverage is claimed.
