# Crew and component adjacency

Step 25 activates Foundation Crew Quarters (`CC`). The catalog now has 13 patterns across 11 equipment types. Crew uses procedural placeholder art. Research purchases and the four-ship starter switch remain later checklist items.

`AdjacencyRules` tests orthogonal contact between occupied component cells. Diagonal contact does not count; multiple shared edges produce one link. Loose tiles are not recipients. Intact disconnected sections keep their actual local links. Destroyed sources and recipients are excluded; reconstructed units restore their links without accumulating bonuses.

Each Crew Quarters chooses up to three adjacent eligible components. Automatic selection follows stable physical component order. In the Ship Designer, open **ASSEMBLY → Crew links → Crew at x,y** to inspect or change recipients. Checked entries receive the bonus; hover highlights the recipient footprint. Deselect an entry before adding another when three are selected. **Automatic** resets the choice. Manual selection, including an empty selection, survives blueprint saves, physical construction, campaign reload and undo/redo. Target origins are stored relative to the source, so moving the whole blueprint preserves assignments. Removed or nonadjacent targets are ignored.

Crew grants +12% operating rate. Multiple Crew sources use the strongest bonus, not their sum. Different named ordinary bonuses share an additive +30% ceiling through `ordinary_rate`; later equipment and research must use that boundary. Sources do not amplify other Crew sources or recursively multiply bonuses.

- Weapons fire faster; damage per shot is unchanged. Ongoing cooldowns preserve their fractional progress when a source is destroyed.
- Engines gain acceleration and turning rate, weighted by the thrust of affected engines. Top speed is unchanged.
- Shields gain recharge rate, weighted by the capacity of affected generators. Their damage-interruption delay and maximum capacity are unchanged.
- Labs refresh combat analysis faster. RP remains governed by the frozen science snapshot and its separate 1.5 cap.
- Repair equipment has recipient eligibility hooks; its throughput integration belongs to the later repair-equipment milestones. Those components remain unavailable.

Combat damage refreshes component stats and mobility immediately. Blueprint and physical previews use the same stat calculation. Science support hooks share the same footprint-contact rule.

`tests/test_adjacency.gd` checks orthogonal versus diagonal contact, repeated edges, three-recipient limits, manual choice, source/recipient destruction, reconstruction, strongest Crew sources, ordinary caps, engine response, shield timing, cooldown changes, lab refresh without RP, JSON/translation, campaign checkpoint persistence and builder undo/redo. Native 640×360 automatic/manual menu captures are `.local/adjacency-menu.png` and `.local/adjacency-manual.png`. Existing certificate-store and shutdown-resource diagnostics remain separate from assertions.
