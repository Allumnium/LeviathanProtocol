# Step 30a: current UI review and requested corrections

Reviewed 2026-10-28. The current result follows the owner's preferences in [AGENTS.md](../AGENTS.md): Starhull, no hover tooltips except the conditional Ship Designer lock, no Tab/arrow UI cycling or focus boxes, five visible ship slots, contextual ship actions, a separate reserve modal, and credits covering construction-material shortages. Do not add features outside the requested milestones.

## Theme ownership

`themes/ui_theme.tres` owns the UI font and reusable styles. Change **default_font** to change the body font everywhere; **default_font_size** sets its size. Labels, buttons, text inputs, popups, reports and dynamically created controls inherit it. There are no per-control font resources or fallback-font overrides. The branded main-menu heading is a separate **GameTitle** variation in that same theme, with adaptive fitting.

Reusable variations cover CompactButton, FramedButton, IconButton, TinyIconButton, ArchiveButton, ResearchButton, ContextPanel, ResearchPanel, LibraryRow, RoutePanel, CompactPanel/Frame/Popup, CrispPopup/Panel and CountBadge. Scene-specific panel style overrides and runtime copies of button styles were replaced by these variations. The builder's colored component outlines remain game-data visuals, not focus decorations.

Starhull's bitmap import permits integer scaling instead of fractional resampling (13px default, 26px for double size). Scalable replacement fonts follow the theme size normally. The first review's replacement system font and keyboard-focus treatment did not match the owner's preferences; they have been removed. UI navigation actions are unbound, ordinary controls reject keyboard focus, and focus style boxes are empty. Text fields retain caret/editing behavior; canvas/gameplay shortcuts and Escape still work.

## Findings and fixes

| Finding / severity | Reproduction and consequence | Current fix / verification |
| --- | --- | --- |
| Fleet cards hide four slots — major | Open Fleet at 640×360. Tall cards clip names against frames and force scrolling. | Five aligned 24px rows, inset names and previews; Port/Story share one row. All slots and services are checked inside the panel at 640×360, 1280×720 and 1920×1080. |
| Font/style overrides bypass the theme — major | Change the theme font: fallback fonts and per-control resources keep parts of the UI unchanged. | Inherited typography and named theme variations. An interaction test swaps the theme font and verifies multiple labels/buttons update together. |
| Focus outlines/navigation are unwanted — major | Click a control or use Tab/arrows: blue outlines appear and focus cycles. | Removed generated texture-button outlines and focus cycles; disabled default UI navigation actions, including popup-menu arrows. Text entry and game controls remain functional. |
| Hover-dependent information — major | Costs and restrictions appear only on hover. | Removed all hover tooltips except Ship Designer's lock. Click construct/repair/dismantle for a visible quote/reason and explicit action; errors appear inline. Research has its clicked grant review; locked library choices offer Details. |
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
| Prices | Hover-only cost information was removed. | [Construction review](ui-review/construction-review.png), [repair review](ui-review/repair-review.png) |

The complete rendered PNGs and control/font metadata are in `.local/ui-corrected-capture/{640x360,1280x720,1920x1080}/`. `tests/ui_review_capture.gd` reproduces these using actual viewport rendering.

## Interaction, performance and regression checks

Native Windows Godot **4.7.2 stable**, OpenGL 3.3 Compatibility, NVIDIA RTX 5060 Ti / driver 610.88. All launches isolate `APPDATA` and use test saves; the user's campaign and blueprints are not used.

`tests/test_ui_review.gd` uses real Godot mouse/key dispatch through hit testing and embedded popup routing. It covers start/setup/settings, no Tab cycling, text-entry isolation, shared theme-font updates, all five slot bounds at three sizes, single/group/empty ship selection, Reserve/Deploy through the modal, repair/construction/dismantle quotes, cancel/failed-write preservation, stock-only actions in debt, no material shop, research, travel preview, battle controls/retreat/report, Continue/backup recovery, corrupt loads, interrupted reserve recovery and terminal defeat.

Before optimization, the isolated profile measured about **124 ms backend / 710 ms with UI** for adding a ship and **131 ms / 499 ms** for removal. Afterward the synchronous UI calls measured about **192/175 ms**. The native interaction check, including deferred refresh/render frames, measured about **342/287 ms** for add/remove and **72 ms** for a block placement. The performance guard is 600 ms for these test fleet edits; this is not a 60fps guarantee or a benchmark for arbitrarily large reserve fleets.

All 27 baseline suites pass across the baseline run and affected reruns, including **600 battle encounters**, **1000 graph seeds**, **1000 content seeds**, transaction failure/reload, passenger/debt, capacity, research and assembly. The capacity UI assertion now checks inline text after the coalesced render update instead of a tooltip. Logs: `.local/ui-corrections-baseline.log`, `.local/ui-corrections-test_fleet_capacity.log`, `.local/ui-corrections-test_ship_stats.log`, `.local/ui-corrections-test_recipes.log`, `.local/ui-wildcard-test_battle.log`, `.local/ui-final-verification.log`, `.local/wildcard-final-check.log`.

Browser/Playwright coverage was unavailable: no runnable web export, web export templates or working Playwright package were present. External desktop automation could enumerate the editor but not the separately launched review window. The recorded fallback is native GPU rendering and engine input dispatch, not external OS pointer coverage. Native launches still emit the environment's root-certificate error and known shutdown texture/ObjectDB resource warnings; these are recorded rather than suppressed. No script/runtime UI errors remain in the final interaction checks.

Later cargo UI and final polish remain in the existing milestones. No additional feature work is authorized by this review.
