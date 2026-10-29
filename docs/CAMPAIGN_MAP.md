# Active campaign map — steps 11–16 / Gate B

New runs now use the three-act, 24-row DAG. Historical saves retain their stored legacy map and frozen encounters; loading never changes their topology or pending deployment. The optional `campaign_active` checkpoint flag distinguishes the formats. Legacy regression fixtures explicitly request the compatibility layout with the third `start_new_run` argument; the main menu and normal API default to the new campaign.

## Nodes, goods and preparation

`CampaignContent` adds frozen content to the structural graph. Nodes explicitly store type, inhabited status, goods grade/unit value, services, story IDs and any fixed material reward. Runtime types include patrol, optional elite, boss approach, port, salvage, survey, signal, staging and the starting anchorage. Salvage grants a previewed fixed six-material bundle; surveys/signals currently provide safe noncombat stops rather than surprise fights or RP.

All lanes on Act I row 4 and Acts II/III row 3 are ports. Every row-7 staging checkpoint is also a full port, guaranteeing preparation on every legal route. Haven and Act I ports offer Basic goods (3 credits/unit); Acts II/III ports offer Uncommon/Rare goods (6/10). Uninhabited nodes cannot dispatch an arrival or provide port services. Repair and construction require a secured port in the active campaign. Select a hull in Formation to repair/reserve it; manage hidden reserves through the Reserve modal. Owned construction materials are used first and credits pay shortages on demand; ports do not sell individual materials.

Passenger/cargo systems remain later steps. Arrival currently pays zero ticket/cargo income because no operational accommodation or holds exist. `commit_port_service` supplies atomic, replay-safe, zero-payout offload/disembark hooks for those later systems. The port panel does not expose nonfunctional passenger/cargo purchases.

## Frozen encounters and truthful previews

Only declared combat/boss rows freeze enemy rosters. Proximity uses the actual global row; reward progression uses the 1–14 combat index. Patrol, elite and boss-approach multipliers remain 1/1.4/1.8. Boss approaches currently use guardian formations and the ordinary eliminate-marked-hostiles objective, without claiming organs, waves, timers or final boss mechanics that arrive in later milestones.

The map shows the current act's routes and node shapes, visited route highlighting and a persistent legend. Securing an act boss immediately reveals the next act's first fork, keeping it selectable. Other future act routes stay hidden until that transition; their themes/bosses are available from the current-location preview. Reachable previews include frozen enemy roles, truthful contact-count bands, objective, threat, material weights, credits, inhabited/goods information and travel conditions. Asteroid/mining information is separate from alien contacts. Inspecting an unreachable node cannot enable travel. Drag/zoom and tooltips remain available.

The 640×360 layout uses a scrollable preview and an explicit Travel button. A short transition precedes dispatch. Noncombat travel returns to the workspace; combat travel opens the real battle controller. Full traversal is exactly 24 visits and 14 objective battles.

## Story delivery and arrivals

Haven, Relay Outpost, Refuge Dock and Last Light deliver the expedition's signal-network and corrupted-ark story. Staging nodes also deliver boss briefs; the final secured approach delivers the ending. Delivery flags are written with secured progression, independently of research branches. Panels can be skipped, and delivered text remains available in the Story Archive. Read/seen flags persist; the ending precedes the campaign-completion dialog.

Only a secured inhabited destination may dispatch an `arrival` identity. Opening or reopening the Port panel is read-only. Noncombat progression/reward, story flags and inhabited arrival are committed atomically. Victory settlement includes its own progression/story/arrival work; failed approaches stay at the prior node and cannot pay arrivals. Replays acknowledge the same identity rather than creating a new payment. A failed write leaves noncombat progression and rewards retryable.

## Edge forecasts

Frozen edge records contain hazard type, duration, seed and mining potential. Charted debris/ion/gravity records retain 20–40-second forecasts and a safe alternative at their fork. Their `active` flag is false in this milestone: the UI explicitly describes safe passage, and transit grants no extra battle, hidden damage or RP. Amber identifies charted conditions, not an active combat encounter. Actual hazard simulation, Scan, extraction and ore fields remain the scheduled environment/mining work.

## Gate B verification

`test_campaign_traversal.gd` validates typed content and port coverage across 1,000 seeds, then traverses three complete campaigns with reload at every row, first-battle withdrawal/retry, exact frozen encounter preservation, one-time secured arrivals, free service replay, branch-independent story, final reveal/ending, failed noncombat writes and minimum-resolution UI bounds. It also drives the real Travel button through its transition into the battle scene and settles that selected node through the real controller.

`test_campaign_graph.gd` independently verifies every possible route's cadence and reachability across 1,000 topologies. Existing definition, metadata, atomic transaction, encounter independence, objective, retry, replay and 600-battle regressions remain required. Native OpenGL captures were inspected for the story, map and port panels at 640×360; unsupported bitmap symbols and a clipped Travel button were corrected. Captures are local QA artifacts under `.local/campaign-*.png`.

Gate B covers the active map/progression flow with guardian-formation boss placeholders. Full specialized boss fights, passenger/cargo economics, hazardous transit and mining are not claimed complete by this gate.

Final validation (2026-10-26): the full isolated baseline passed with zero assertion failures, including 1,000 geometry seeds, 1,000 content seeds, 1,080 encounter allocations, three complete campaigns, replay and 600 battle regressions. Logs: `.local/checks/8307670a31424fa798c765c3dbc61da7/`. A subsequent act-transition visibility fix and regression passed the focused campaign suite in `.local/traversal-final.log`. Native 640×360 captures were re-inspected after the layout/font changes. `git diff --check` passed. The existing certificate-store diagnostic and Godot shutdown ObjectDB/resource warnings remain separate from assertion results; all saves used isolated test data.
