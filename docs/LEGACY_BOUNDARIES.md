# Retired runtime and archive readers

The physical hangar is the only playable model. C2 removes the disconnected material `game_state.gd`, old formation board, builder starfield, lock/tab helper, upgrade panel, square design preview and unused save-design/help/victory windows. The active campaign, help and battle reports use the hangar UI.

Forty-six earlier test/capture scripts are preserved as `.gd.txt` under `docs/history/pre_hangar_tests/`. Godot does not import or run them. They describe square materials, old designer paths, reserves, family slots or the old GameState API. Port useful assertions to current tests when needed; do not restore their gameplay dependencies. The two shared stats/replay suites remain runnable alongside the physical-game suites.

## Compatibility boundary

`scripts/legacy/` holds the square checkpoint/progress, ledger, roster, passenger/cargo schemas and prototype slot library, alongside the existing hex readers. Historical class names remain for decoder dependencies. Pure legacy helpers reconstruct and validate the historical data in memory; no historical runtime or UI calls them to mutate a player run.

Read-only entry points:

| Data | Reader |
| --- | --- |
| `ship_designs.json` (unwrapped version 1) | `LegacySquareDesignLibrary` |
| `run_checkpoint.json` (checksummed versions 1/2) | `LegacySquareRunReader` / `RunCheckpoint.decode` |
| `hex_designs.json` | `LegacyHexDesignLibrary` |
| `slot_designs.json` | `SlotDesignLibrary` |

Readers do not expose save methods, convert into physical ships, resume old campaigns, promote staged files or overwrite archives. Checksummed readers can inspect the newest valid main/staged/backup generation. Invalid input leaves the last readable in-memory archive intact. The old checkpoint capture method and prototype slot-library writer are removed.

`tests/fixtures/legacy_square_run_v2.json` was captured from the original writer before removal: seed 1357, three square ships and 34 frozen encounters. It complements the frozen square and hex blueprint fixtures. Current archive tests verify original reads, malformed data, schema separation, recovery and byte preservation. Tests use isolated APPDATA.

## Shared code retained deliberately

`Ship`, `FleetShip`, `ShipPart`, `ShipStats`, recipes and pattern metadata still support the square decoder and shared combat regression fixtures. `GameDefinitions` still validates the original metadata used by the active equipment/research catalog. These are compatibility/shared DTOs, not an active construction system.

The generic save/command checks live in `SaveValidation`; current storage, campaign and combat code no longer imports the old run schemas for number/JSON validation. Active trade owns its casualty-fee constant. Square renderer/catalog initialization is lazy, used only when a historical DTO is actually rendered; physical chassis previews and battles skip it.

Player art and old user save files are unchanged. Optional gameplay remains deferred.
