# Entity targeting and victory

BattleSimulation registers actors by stable ID. Faction controls friendly fire and hostility; tags describe combatants, neutral objects, hazards, drops, decoys and summons. Targetability is independent of objective membership. Manual attack orders can select neutral actors through the same weapon and damage path as hostile ships. Automatic targeting normally selects hostile actors only.

Frozen encounters declare required target IDs. Historical encounters without this optional field derive their original ship objectives without rerolling stats. Unknown required IDs fail closed. An explicit objective may include an otherwise optional actor; ordinary summons are not automatically required.

The battle checkbox **Destroy all neutral targets** defaults off on a new run. Changes save atomically with the run and revert if persistence fails. Enabled, it adds living, targetable neutral-tagged actors to the victory requirement, excluding drops, decoys and summons. Player Auto prioritizes hostile threats, then clears eligible neutrals. Turning it off restores the declared encounter objective. Neutral destruction adds no enemy salvage or separate victory reward.

Once objectives are complete, new weapon fire stops and relevant shots already in flight resolve before the result. A surviving optional escort cannot keep firing indefinitely to prevent victory. Defeat and an active withdrawal still take precedence.

`add_neutral_target` supplies stationary test actors rendered as circles. Moving asteroids, collisions, fragmentation, ore extraction and persistent mineral fields remain later implementation steps. Current generated encounters do not yet contain asteroid fields.

`tests/test_entity_objectives.gd` checks shared damage, manual orders, neutral Auto policy, objective validation, default/optional victory, exclusions and save compatibility. The battle scene suite checks that the actual checkbox changes both simulation and saved settings.
