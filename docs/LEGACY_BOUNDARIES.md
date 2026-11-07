# Retired code and shared combat data

The physical hangar is the only playable model. Old material construction, square/hex design libraries and archive readers are retired. P2e audited their references, then deleted `scripts/legacy/`, its isolated data/dependencies, the archive fixtures and `test_legacy_archives`. Legacy-save compatibility is outside the current contract. Existing user files and source artwork were not changed.

Earlier test/capture scripts under [history/pre_hangar_tests/](history/pre_hangar_tests/) and disconnected scenes under [history/retired_ui/](history/retired_ui/) are historical references. Godot excludes them from active imports. Their former resource paths are not runtime dependencies or current requirements.

`Ship`, `FleetShip`, `ShipPart`, `ShipStats`, recipes and pattern metadata retain active combat and focused regression callers. They are shared data structures, not a player construction system. `GameDefinitions` projects scoped content into the shared equipment/research/combat interfaces. The physical renderer skips square catalog initialization unless a shared fixture renders that representation.

`CampaignGraph`, `CampaignContent`, `SwarmNavigation` and `HangarCheckpoint` still support the current runtime and checkpoint validation. P3 replaces them with the run document and its systems; they were deliberately retained during the P2e reference audit. Current storage uses `SaveValidation` and `AtomicRunStore`.
