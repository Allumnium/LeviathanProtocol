# Campaign DAG generation

`CampaignGraph.generate(seed)` builds a versioned, JSON-safe graph with an anchorage and three eight-row acts. New runs store it in `GameState.campaign_dag` and the run checkpoint's `campaign_graph` field. Save loading restores the stored graph, validates its seed and topology, and never regenerates it. Historical checkpoints without this optional field retain their existing playable map.

Each node stores its stable index/ID, global row, act, local row, lane, normalized position, structural kind, combat index and optional elite marker. Edges contain source/target IDs. Structural kinds distinguish combat/noncombat rows, staging checkpoints and bosses; they do not yet activate port services, story events or boss mechanics.

Ordinary rows have 2–4 nodes. Lane paths are connected first, then selected cross-lane edges are added, capped at three exits. Narrow rows produce merges, and each act has two interior three-way forks. Row 7 converges at one staging node; row 8 contains the act boss. Bounded vertical jitter varies the layout without collapsing lane spacing. The final boss has no outgoing edge; every other node advances exactly one row.

Combat rows are Act I 1/3/5/8 and Acts II/III 1/2/4/5/8. All routes therefore contain 24 visits and exactly 14 combat rows, with combat indices 1–14. Optional elites occur only on separated combat rows; every incoming branch retains a direct non-elite choice. Boss/staging markers are never elites.

Generation validates row widths/cadence, node identities/geometry, edge degrees/direction, checkpoint identities, forks/merges and elite escape routes. A fixed lane pattern provides a known-valid fallback if a generated candidate fails. Adjacent-row edges plus complete incoming/outgoing coverage prove reachability from the unique start and forward access to each act boss.

## Integration boundary

Step 10 generated and froze the new topology separately. Steps 11–16 now activate it for new runs with typed nodes, previews, story, secured arrival dispatch and full traversal; see CAMPAIGN_MAP.md. Historical saves retain their stored legacy maps. Noncombat rows use their own dispatch and cannot become extra battles. Specialized boss fights remain later milestones.

## Verification

`test_campaign_graph.gd` checks 1,000 seeds, independent forward/reverse reachability, all-route min/max visit and combat counts, exact 4/5/5 act cadence, deterministic regeneration, topology diversity, all ordinary widths, fallback validity, corrupted edges/cadence, mandatory elites, checkpoint rejection and exact save/reload preservation. All 1,000 seeds produced distinct topologies without fallback. Resource/fleet changes leave the frozen graph unchanged.

Full isolated baseline validation (2026-10-26) passed with zero failures, including the 1,000 graph seeds, 864 encounter allocations, deterministic replay and 600 battle regressions. Logs: `.local/checks/cc0de0192ece4e088cb4d1a133a11446/`. `git diff --check` passed. The existing Windows certificate-store diagnostic remains separate from assertions.
