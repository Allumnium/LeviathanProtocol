> Superseded October 31, 2026: the owner replaced grids, materials and recipes with chassis images and typed equipment slots. This document is historical. Active work is described in SLOT_DESIGNER.md and TODO.md.

# Hex recipe proposal

Discussion draft, October 30, 2026. This does not change active recipes, equipment balance, research or saved designs.

## The problem

The current hex recipes mostly preserve square recipes as axial parallelograms. They function, but they do not teach a coherent hex vocabulary. Several opposite research branches also share identical recipes, and automatic replacement of whole smaller components can unexpectedly change their identity while painting.

## Proposed vocabulary

Materials retain their existing roles: red = force/emission, blue = structure/containment, green = control/conversion, purple = people/services. Shape expresses how the component works; material placement distinguishes its identity.

- **Line:** compact linear machinery. Its long axis is a packing choice, with no firing/exhaust direction.
- **Compact triangle:** three mutually neighboring cells. Small, compact hardware.
- **Core and neighbors:** a central control/material cell with a recognizable surrounding arrangement. A partial arc is different from a full ring; changing the core material must have a consistent meaning.
- **Two joined clusters:** larger machinery, not simply a longer rectangle.
- **Full hex cluster:** major equipment with clear compact boundaries.

Suggested footprint sizes are 3 for basic components, 7 for a core with six neighbors, 13 for two seven-cell clusters sharing one cell, and 19 for a radius-two hex cluster. These are useful defaults, not a rule that every component must use the same sizes. Mixed four-cell recipes are useful early equipment too.

## Concrete starting examples

O = red Offense; D = blue Defense; T = green Tech; C = purple Civic.

| Equipment | Proposed materials / shape | Why it reads clearly |
|---|---|---|
| Laser | TOO in a straight line | Green identifies control; red identifies output, without functional facing |
| Mini Turret | Three O in a compact triangle | Same material investment, different footprint and behavior |
| Armor | Three D in a compact triangle | Compact solid structure; no four-square legacy recipe |
| Thruster | One T and two O in a compact triangle | A controlled output, distinct from the red-only weapons |
| Crew Quarters | Three C in a compact triangle | A small people/service component |
| Research Lab I | One C with three T in a compact fan | People operating instrumentation; four cells keeps an early lab attainable |
| Shield | One T core with six D neighbors | Containment visibly surrounds its controller |
| Passenger Cabin | Seven C in a complete hex cluster | A larger civic space, distinct from quarters |
| Cargo Hold | Four C and three D in a short capsule | Civic capacity with structural support; final color positions need authoring |

These describe candidate identities, not a finalized full catalog. Each exact colored layout must be checked against every rotation/reflection before acceptance. Two shapes that look different on paper can still be the same recipe after a hex rotation. Research exclusions may remain, but different equipment should have different recipes rather than relying on the player to resolve identical patterns.

The owner confirmed that equipment has no functional orientation. All rotations/reflections match the same identity and behavior; color asymmetry distinguishes recipes without defining a front or rear. Weapons aim automatically and thrusters provide ship-wide thrust. No facing arrows or equipment Rotate/Flip controls. Keep labels upright. Any future art must preserve this rule.

## Assembly recommendation

Avoid one-cell recipes for newly built equipment: a loose material should not instantly masquerade as a finished turret or armor component. Recognize/highlight a complete candidate, then let the player commit its equipment identity with the existing Assemble action. Once outlined and named, that component should stay stable when more material is placed nearby. Larger equipment should be built from loose materials or explicitly replace a selected component, rather than silently swallowing a smaller named component. Breaking an equipment group returns its surviving cells to loose material.

This is a proposed change to the current automatic assembly policy, not implemented behavior. If automatic assembly is retained, it should still avoid silently changing already named equipment and should never guess between identities.

## Construction regions and tuning

Recipe geometry and region geometry must be designed together. Some current draft regions are narrow parallelograms: a 4x2 region has eight cells but cannot fit the seven-cell hex cluster. Redesign region masks around the common motifs before switching recipes. A region should offer meaningful offensive, defensive and support choices; its shape should not accidentally force one role. Verify every intended tier against the five chassis, including an affordable early lab.

Revisit material prices and equipment stats alongside the changed cell counts. Three blue cells replacing four and seven-cell cabins replacing six are balance changes, not cosmetic conversions. Keep at least one cheap useful combat component and one cheap lab option.

## Saves and next implementation

The active 58 recipe/rank layouts remain unchanged for now. Approve a small opening set, author explicit axial colored-cell layouts, validate connectivity and all twelve symmetries, then review those examples in the Designer before expanding the catalog. Add a recipe revision/legacy-layout strategy before changing active definitions; never reinterpret an existing fitted component using a different shape. The outline/name presentation is already independent of final equipment art.
