# Enemy roles — step 50

Newly frozen deployments enable distinct behavior for the five existing priced enemy roles. Old pending deployments without the mode retain their previous behavior and replay inputs. The behavior flag is validated in frozen encounters and departure contexts; reserves, launch counters and timers enter authoritative replay snapshots. No fleet-strength scaling, extra player slot, research grant or optional sensor/ability was added.

| Role | Working behavior | Limit/counter |
| --- | --- | --- |
| Scout | Flanks toward visible exposed labs, accommodation, holds or repair ships | Visible nearby armed escorts make a support target less exposed; hidden positions/loadouts are never consulted |
| Fighter | Chooses nearby visible targets and applies direct close-range pressure | Ordinary armor, weapons and movement |
| Sentinel | Positions near the front line; shields allies within 140 | Strongest-only 20% damage reduction, no invulnerability; source destruction removes it immediately |
| Support | Follows the front line and repairs a living ally within 150 | 1 HP/s, at most one repair source per target/tick, 10/18/26 HP reserve by frozen tier; no resurrection |
| Chrysalis | Follows behind the front line and incubates strike craft | 2/3/4 drones by tier, first at four seconds then every six; parent destruction stops unlaunched craft |

Chrysalis reserves are included in the role's existing frozen threat price. The 64-live-ship/craft/organ limit defers a launch without consuming its reserve; asteroid limits remain separate. Drones use stable parent/launch identities, ordinary movement/weapon/visibility rules, and craft/summon tags. Point defense already prioritizes these tags. Craft cannot supply their own Command Center coverage or Scan, add enemy salvage, or extend an ordinary parent/escort victory objective. Enemies and their finite reserves reset on retry under the existing attempt policy; victory rewards pay once and finite ore stays depleted.

Route previews describe the roles' flank/pressure/shield/repair/finite-drone behavior. Visible Sentinels have a thin shield-radius cue, active repairs have a green link only when both endpoints are visible, and drones use smaller existing Scout sprites. No tooltips, hidden links or loadout labels were introduced.

Implementation: `enemy_roles.gd`, shared battle simulation/renderer, frozen encounter/departure mode and checkpoint validation. `tests/test_enemy_roles.gd` covers exposed/escorted/hidden targeting, pressure/flanking, actual strongest-only damage mitigation, source loss, finite repair/no resurrection, finite launches/source death, cap deferral, no summon salvage/objective extension, fixed-clock JSON replay and old pending contexts. Evidence: `.local/enemy-roles/enemy_roles.log` and `native.log`; native 640×360 screenshot: `docs/ui-review/enemy-roles-640.png`.

The nine opening Auto routes and four economy scenarios still pass with these behaviors enabled (`.local/enemy-roles/opening_loop.log`, `economy_loop.log`). These are opening/basic-economy checks, not a full-campaign balance sign-off. Later enemy combinations, objectives, bosses and final doctrine tuning remain their required TODO steps.

Final integration evidence: all 43 suites pass in `.local/enemy-roles/baseline.log`, with final affected reruns under `.local/enemy-roles/final/`, including the 600-encounter battle suite. Optional backlog entries remain deferred.
