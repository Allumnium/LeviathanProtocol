# Core intermediates: first implementation

Milestone 56a adds six physical equipment types. ECM Suite and Phase Drive remain unfinished under 56b. No optional abilities, slot bonuses or material systems are activated.

| Item | Exact mount | Credits | Effect |
| --- | --- | ---: | --- |
| Ammunition Magazine | Tech M | 120 | +20% host weapon cycling per operational magazine; additive stacking, including bay launch cycling. |
| Railgun | Offense L | 240 | 24 damage, 500 range, 6s cycle. Projectile cannot be intercepted as a missile. Ignores Sentinel protection against unshielded hull; shields and boss protection still apply. |
| Flight Deck | Offense M | 190 | Six interceptor sorties per encounter; at most two active. Each has 12 weapon activations, shared between missile screening and attacks. |
| Torpedo Bomber Bay | Offense L | 280 | Four bomber sorties per encounter; at most two active. Each carries two interceptable torpedoes. |
| Command Uplink | Tech M | 140 | Automatically marks a visible target within 500 every 20s. +20% allied damage for 5s; strongest mark/analysis effect, without multiplying them. |
| Tactical Computer | Tech L | 220 | Each operational computer contributes one synchronization per 12s. Releases all host weapon cooldowns against a visible, unshielded target; also synchronizes bay launch timers. |

Prices, stats and current mount maps remain initial tuning. Magazines and computers support **all host weapons**, without adjacency or a target-count limit. Their copies stack as explicitly requested: two magazines give +40% cycling; two computers synchronize twice as often. They do not multiply damage or refill craft. Stacking tests use additional matching mounts in an in-memory future-chassis fixture: the supplied draft layouts currently have at most one Tech M and one Tech L mount per chassis.

Siege I/II, Carrier I/II and Command I/II are active research nodes with their existing prerequisites, prices and mutually exclusive branch rules. Purchase/fitting remains research-gated; acquisition is physical, at shipyards or through eligible battle loot. No new menu, modal, hover tooltip or keyboard focus navigation is added. Bay details show the allowance; battle status shows ready/active craft. Marked visible enemies have a small gold ring.

## Combat and conservation

Craft are targetable combat actors, not owned chassis or inventory rewards. Sorties expire after 25 seconds or when their payload is spent, the craft dies, or the host/bay is destroyed. Source loss prunes craft immediately during the damage/stat update. Point defense prioritizes hostile craft and intercepts bomber torpedoes; interceptors screen hostile missiles without destroying friendly ones. The global 64-live-combatant launch cap also applies. Failed/capped launches spend nothing.

Replacement allowances follow equipment UIDs in the existing per-encounter doctrine pool. Spent sorties survive retreat settlement, atomic save/reload, repairs and transfers. A different encounter starts a fresh allowance. Older pools without carrier fields remain readable. Bad capacities, overspending, invalid identities and future/mismatched UIDs are rejected. Pending battle restarts replay the original departure battle, not a partially damaged enemy roster with a refreshed fleet.

Host reports include damage dealt by its craft. Synchronization never overwrites a charging beam. Lost magazines remove their cycling contribution; lost computers stop synchronization; lost uplinks end their marks. The mark uses ordinary visibility/target-selection rules and does not expose hidden actors.

## Verification and limits

- `test_hangar_carriers.gd`: 143 checks, including physical purchases/fitting, exact mounts, finite payloads, interception/IFF, active/entity limits, source loss, reload/transfer conservation and an actual campaign battle UI. Native capture: `.local/carriers/battle.png`.
- `test_hangar_intermediates.gd`: 155 checks, including additive stacking on all weapon types, bay cycling, synchronization/source loss/shield counters, beam-charge safety, marking/visibility, railgun cover/shield behavior and research/purchase gates.
- Six actual Act II combats, two per siege/carrier/command loadout, reach natural victories in the recorded seed-642 fixtures. These are funded combat fixtures using real mounts, not naturally earned full-route builds or an equal-investment balance comparison.
- The full eleven-suite baseline passes, including the existing nine full-route campaign runs (126 battles), old archive readers and native UI checks. The full-route policies do not yet purchase these six items; pacing and broader doctrine balance remain milestones 61/67/70.

Known Windows certificate-store and renderer shutdown diagnostics are unchanged. Optional extras remain deferred.
