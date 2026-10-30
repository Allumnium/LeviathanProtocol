# Battle objectives and arenas — step 51

New campaigns alternate ordinary patrol and finite-wave fleet defense. Elites retain their stronger patrol roster. Step 52 adds the first-act pylon escort and Bastion Warden described in WARDEN.md; later bosses remain their dedicated milestones. The current required selection uses open space and a corridor. Convoys, interception, the complete combination matrix and drifting-field layouts remain optional 51a.

| Objective | Completion | Timing |
| --- | --- | --- |
| Patrol | Destroy every marked hostile | No deadline |
| Defense | Survive and destroy all three finite waves | Initial wave at departure; reinforcements at 6 and 12 simulation seconds |

The entire roster, including later waves, consumes one frozen threat budget. There is no recurring spawn or extra wave reward. Reinforcements enter at the announced right-side zone; amber chevrons mark that zone without consulting hidden actors. The battle HUD shows the current/total wave and countdown, then the remaining targets after the final arrivals. Pause freezes the timer; 2× advances the same fixed simulation ticks. Clearing a wave early cannot finish the encounter or trigger a final-kill cinematic. The live 64-combatant limit defers arrivals in wave order without deleting them. Timed waves initialize finite Support/Chrysalis reserves individually and never replenish earlier sources.

Open space retains normal movement. Corridor boundary lines mark a soft steering constraint applied equally to both factions; it does not damage or teleport ships. Announced asteroid encounters use open space. No exclusive research, extra ability or optional hazard is needed.

New departure contexts carry their complete frozen encounter plan. Checkpoints validate it against the node's original encounter. Old frozen encounters and pending contexts without the new layout retain their original behavior. Enemy rosters and wave timers restart on retry under the existing attempt policy; physical losses, expended persistent resources and collected finite ore remain spent. Victory credits, salvage and travel-day research use the existing single settlement. Waiting produces no research.

`tests/test_battle_encounters.gd` covers timing, premature victory/cinematics, unknown identities, ordered capacity deferral, late finite reserves, corridor steering, JSON state/event replay at 1/2/8 ticks per frame, six basic-Drone Auto battles, campaign generation/save validation, and the actual paused/2× controller through settlement/reload and duplicate-payment rejection. Native 640×360 captures: `docs/ui-review/encounters-640.png` and `encounter-controller-640.png`. Final native log: `.local/objectives/native-final.log`.

All 44 suites complete with zero assertion failures in `.local/objectives/baseline.log` (isolated run `.local/checks/c5c7b478d5144ea5995476813259a4ee/`). This includes nine opening Auto routes, four economy routes, and 600 legacy battle simulations. The UI review records 71 ms placement, 346 ms add, and 271 ms remove, below existing limits. The final wave-order/cinematic refinement is additionally checked by the affected `*-final.log` reruns under `.local/objectives/`. Existing Windows certificate-store and renderer shutdown diagnostics remain separate from gameplay assertions. Full-act bosses and full-campaign balance remain later required work.
