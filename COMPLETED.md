# Completed work

Keep new entries brief: completion date, delivered behavior and focused verification. Historical reports are references, not standing retest requirements.

## 2026-11-04 - Faster cruise research (D4 increment)

- Field Engineering now adds 25% cruise speed alongside its existing 25% fuel-per-distance reduction. Actual movement and both ETA displays share the researched rate; one short detail/toast sentence covers both benefits.
- Simulation-time repair/combat/idle clocks, journey distance-based fuel/research/income and authored encounter positions remain unchanged. Effects derive from existing earned research on Continue and start after the earning frame; no save fields, equipment, price or prerequisite changes.
- Focused isolated verification: travel research 237 headless / 239 native checks; default navigation 167 checks, all zero failures. Covered speed/frame invariance, fuel/event/arrival clipping, authored zone admission, mid-route unlocks, Continue, atomic rollback, both ETAs and three-resolution UI; reviewed native Map/research captures. Existing renderer shutdown warnings remain; no full baseline run.
- Random-encounter reduction remains deferred/open because the demo uses authored encounters, not a random-encounter system. Publishing remains blocked by the missing Git remote.

## 2026-11-04 - Incremental delivery permission

- Updated the personal Godot instructions to authorize automatic task-scoped staging, verified incremental commits and pushes to configured upstreams, without repeated approval. Preserve unrelated work; never force-push or guess a remote.
- Added the research-travel test's source UID sidecar after checking its format and uniqueness. Cleanup commits are local; publishing remains blocked in TODO until a remote URL is supplied.

## 2026-11-04 - Repository housekeeping

- Git-ignored `.godot/`, `*~` and `*.log`; removed 1,337 generated cache files from Git's index without deleting or changing their local contents. Source `.import` settings and script `.uid` sidecars remain versioned; archived backups remain versioned.
- Moved four root logs into ignored `.local/checks/historical-root-logs/` and documented `.local/checks/<task>/` for future outputs. Saved workspace Explorer exclusions for import sidecars/editor backups.
- Archived two disconnected broken builder scenes, obsolete help and two retired stock controls (seven files including UIDs) in [docs/history/retired_ui/](docs/history/retired_ui/), excluded by `.gdignore`. Preserved original bytes/layout and all active compatibility/test dependencies; kept the test-used save-design dialog.
- Verified ignore rules, cache preservation, relocated hashes and no active references to retired paths. Focused isolated headless checks completed: retained-scene/menu/management startup 17 checks; legacy archives 66 checks; zero failures/script errors. No full baselines or native acceptance run; no gameplay/UI behavior changed.

## 2026-11-04 - Unused resource archive

- Moved 405 unused tracked resources (sprites/textures, seven font alternatives, eleven audio tracks/cues, source packs and editor backups) plus 353 import sidecars into [unused_resources/](unused_resources/), preserving all file bytes. Original relative layout is retained except one preview filename shortened for Windows; [manifest.json](unused_resources/manifest.json) records exact original paths, sizes and SHA-256 hashes for restoration. A `.gdignore` excludes the archive from Godot imports/exports.
- Kept resources referenced by runtime, catalogs or runnable tests, including dynamically paired surface maps, bitmap font pages and font license metadata. Untracked editor files were left untouched.
- Verified all 758 moved files against source hashes and Git originals; retained assets are unchanged and active code/catalog/test references remain valid. Isolated native resource/startup check completed 516 checks with zero failures, loading retained resources and opening menu, Map, Fleet, Ships and Research; reviewed menu/Map/Ships captures. Test-only raw-font-image export warning and renderer shutdown diagnostics were emitted; no script/parse errors. No full suites run.

## 2026-11-04 - Documentation cleanup

- Archived 45 superseded documents plus five former-guidance/history snapshots under [docs/history/](docs/history/). Current slice/D4/D5 stay active; older E01-E14 work is deferred, not completed.
- Replaced conflicting instructions and accumulated hangar notes with compact current contracts; retained mount rules, ownership/save guards, UI preferences and focused test invocation. Story specification remains narrative reference.
- Verified every archive against its original (only banners/relative links changed), byte-preserved both NUL-containing old plans, retained all 81 prior open tasks in the historical plan, and introduced no broken local Markdown links. No game suites run; no gameplay, art or saves changed.

## Delivered before 2026-11-04

- U1-U4: meaningful-text/diegetic UI pass (remaining artwork approval stays in TODO).
- D1: fully fitted ship purchases, free shipyard refits, majority starting equipment access, four advanced research gates and Foundation-only starts.
- D2: atomic rewards/rescued ships and persistent fleet missile supply.
- D3: same-chassis squadrons, stances, group actions and formation movement.
- D4, partial: Prismatic Lasers, splitting missiles, shield pulses, reduced cruise fuel and distance-funded credits. Remaining research work stays in TODO.
- Godot preferences applied to project workflow and existing backlog; verified task preservation, new links and whitespace without game suites.

The [full prior completion record](docs/history/reports/COMPLETED_THROUGH_2026_11_04.md) preserves all 87 original completed entries, the workflow update and recorded acceptance results. It does not imply the remaining expansion plan is finished.
