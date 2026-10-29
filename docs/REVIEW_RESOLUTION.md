# Steps 1–29 review resolution

October 27, 2026. Addresses `REVIEW_STEPS_1_29.md` and block-placement stalls.

- **Support damage:** eligibility checks the fitted blueprint. Destroyed labs give no current science/analysis/capacity bonus, but surviving legal Science/Civic hulls can travel. Permanent tests cover Science victory and withdrawal, immediate reload, noncombat travel to a port and normal repair. Civic damage has a policy regression; live cargo/passenger equipment remains gated.
- **Reserve recovery:** after losing all deployed combat capability away from a port, emergency roster access can select an already-owned living blueprint and activate reserves. It cannot construct, repair, register a new revision, withdraw reserves or abandon loaded hulls. A real simulation defeat/reload regression covers historical-revision recovery.
- **Revision policy:** each regular family slot selects one physical blueprint revision. Older copies retain design, HP and identity as reserves. Reserve-modal USE REVISION can restore an old revision; copies of different revisions cannot deploy together under one slot. Selecting/registering a revision does not refit ships. Checkpoint validation checks the selected snapshot against registered fingerprints.
- **Preparation durability:** ship construction/shortage payments and build-area upgrades stage checkpoint changes before live state/signals. Failed writes preserve resources, fleet, roster/family counters and next ship ID. Immediate reload preserves exact costs once. Editor/library/formation save boundaries are documented in `ACCOUNTING.md`.
- **Debt:** owned-material-only construction and zero-credit reconstruction work with negative credits; repair UI uses the same rule.
- **Builder performance:** authorize the scan once, and derive candidate origins from matching loose material instead of scanning every empty grid position. Preserve pattern priority and row/column ordering. Transformation coverage checks every catalog rotation/flip, including recipes with holes; existing assembly/disassembly/history tests remain passing.

Continue/checkpoint UX, step 18 starter activation and provisional Gate C, casualty-before-validation ordering, loaded-capacity backend guards and diagnostic tracking have explicit open items in `TODO.md`. These are future activation requirements, not completed passenger/cargo features. The original source review remains unchanged.

## Validation

Full isolated `tests/run_baseline.ps1`: zero failures in all suites, including 600 combat encounters, 1,080 encounter allocations, 1,000 topology seeds, 1,000 content seeds and three placeholder campaign traversals. Logs: `.local/checks/9c57a8e7c30944789d38cff543dd52b4/` and `.local/fixes-baseline.log`.

Final targeted `test_review_fixes.gd` and `test_fleet_slots.gd`: zero failures, including additional transformed-origin and historical-revision UI checks. Logs: `.local/review-final.log`, `.local/slots-final.log`. `git diff --check` passed.

Headless sparse standalone designer profile: original full-grid matching path 255.62 ms; updated placement path averaged 3.55 ms over ten evaluations. The campaign-map regression averaged 47.05 ms over five evaluations with fleet/UI callbacks attached. These measure CPU evaluation in synthetic fixtures, not a complete rendered playtest. Local profile: `.local/profile_builder.gd`, `.local/profile-builder.log`.

The existing root-certificate diagnostic and ObjectDB shutdown warnings remain; they did not produce assertion failures. Tests used isolated saves, not player save files.
