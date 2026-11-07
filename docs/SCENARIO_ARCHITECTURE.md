# Scenario architecture and implementation plan

Status: proposed 2026-11-07. This is the target architecture for turning the vertical slice into a data-driven, procedural and moddable game with an in-game Scenario Editor and Steam Workshop publishing. It supersedes the "minimal story plumbing" limits in [the Act I plan](ACT_I_EXPANSION_PLAN.md) for future work. Actionable phases live in [TODO.md](../TODO.md).

## 1. Goal

Leviathan becomes **an engine plus content**. Anything deliberate lives in data packs that can be edited by hand or in the Scenario Editor. Anything random is generated from designer-weighted pools and rules, and every generated choice can explain itself. The built-in campaign, player scenarios and Workshop items use the same pipeline.

The architecture succeeds when a designer can do the following without code:

1. Create a pack that depends on `core`.
2. Add a faction, three site types, an incident and a secondary arc with randomized child jobs.
3. Write "rich fleets attract pirates" as one rule.
4. Preview the galaxy across seeds and see why each site, quest and actor was placed.
5. Forecast incident pacing and economy over 50 simulated runs.
6. Playtest from any seed with an isolated save and a debug overlay.
7. Publish the pack, then let another player subscribe and play it.

## 2. Design pillars

1. **Generate the place, cast the story.** Designers write situations with roles, not placements. The engine generates a galaxy and casts roles onto suitable sites, actors and factions. Pins let designers fix a role where it matters.
2. **Quests are the state of the story.** Every non-trivial narrative thread is a quest instance with stages and outcomes. Triggers, map markers, journal entries and consequences attach to quests, not loose flags.
3. **Pressure, not scripts.** Like RimWorld's wealth-scaled threats, derived stats and pressures change what the director chooses. Designers shape the curve; the run supplies the specifics.
4. **The world remembers.** A chronicle records notable happenings. Casting prefers actors and sites with history, so a spared pirate can return with a grudge. The end-of-run Captain's Log is written from the chronicle.
5. **The world has its own plans.** Antagonists run *fronts*: quests with escalating portents that advance unless the player interferes.
6. **Explainable randomness.** Every generation and director decision records the rule, weights and alternatives behind it. The editor shows them, and the Forecast tool aggregates them.
7. **One pipeline, data only.** Core content is the `core` pack. Packs contain JSON, images, audio and text, never scripts. New mechanics are engine primitives that data composes.

### Non-goals

- Script mods or PCK loading from packs. This is a deliberate Workshop security boundary.
- Hand-placing every enemy, site or line of dialogue. Hand authoring is reserved for pins, key scenes and milestones.
- Full off-screen strategy simulation. Factions and fronts advance through clocks and simple rules, not autonomous fleets.
- Multiplayer and backward-compatible saves. Each phase may break saves.

## 3. Glossary

| Term | Meaning |
| --- | --- |
| Pack | A folder with `pack.json` plus definitions and assets. It is the unit of loading and Workshop publishing. |
| Def | An immutable definition with `type` and `id`, such as an equipment, quest, faction or scenario. |
| DefDatabase | The resolved, validated, compiled defs from every active pack. |
| Scenario | A recipe: mode, galaxy parameters, populations, quest pools, director profile, rules and pins. |
| Run document | Mutable state for one run. It is saved atomically. |
| Fact path | A read-only expression path into run state, such as `credits`, `stat.wealth` or `role.target.faction.standing`. |
| Stat | A derived value defined by a formula, such as wealth, fleet power or notoriety. |
| Pressure | A bounded meter with per-day dynamics and threshold hooks, such as swarm, escalation or morale. |
| Hook | A named runtime signal with a payload, such as `travel.arrived` or `battle.won`. |
| Effect | A registered state-change operation, such as `credits`, `start_quest`, `battle` or `chronicle`. |
| Quest | A def with roles, stages, transitions and outcomes. Kinds include primary, secondary, incident, front and background. |
| Casting | Binding quest roles to existing or newly spawned sites, actors, factions or ships. |
| Scene | A conversation or decision screen with nodes and options. |
| Director | The storyteller that admits incidents and quests based on a profile, tension and budget. |
| Chronicle | An append-only record of notable happenings. Expressions can query it. |

## 4. Runtime overview

```text
Packs (res://packs, user://packs, Workshop folders)
  -> PackLoader: manifests, dependency order, parse, inherit, patch
  -> Validator: schemas, references, formula compilation  -> Problems
  -> DefDatabase (immutable, content hash)
        |
        v
Instantiation (new run): scenario recipe + seed
  -> Galaxy generator stages -> world entities
  -> Casting of primary milestones and starting arcs
  -> Run document + frozen content snapshot
        |
        v
Play loop: UI command -> RunTransaction
  -> engine system mutates the working document
  -> hooks queue -> quests, rules and director react through effects
  -> validate -> atomic save -> swap -> UI refresh
```

Systems are GDScript engine code: travel, battle, trade, fleet, research, quests, director, factions, pressures, chronicle and text. They read definitions from `Content`, mutate only through `RunTransaction` and communicate through hooks.

## 5. Content packs and definitions

### 5.1 Layout

```text
packs/core/                    built-in engine content and base library
packs/leviathan/               built-in campaign scenario; depends on core
user://packs/<id>/             local authoring projects and editable copies
<Steam install folder>/        subscribed Workshop packs (read-only)

<pack>/
  pack.json
  preview.png                  Workshop and scenario browser image
  defs/**/*.json               any folder structure; type comes from each def
  art/ audio/                  pack-relative assets
  locale/<lang>.json           optional text overrides by def path (later)
```

### 5.2 Manifest

```json
{
  "id": "frontier_tales",
  "name": "Frontier Tales",
  "version": "1.2.0",
  "authors": ["Allumnium"],
  "kind": "content",
  "game_version": ">=0.5",
  "depends": [{"id": "core", "version": ">=1.0"}],
  "load_after": ["leviathan"],
  "tags": ["quests", "pirates"],
  "steam": {"published_file_id": ""}
}
```

`kind` is `content` for library additions or `scenario` when the pack also exposes playable scenarios. Both use the same loader.

### 5.3 Def files, IDs and references

A file is either one def or `{"defs": [...]}`. Every def has `type` and `id`. Qualified IDs are `pack:local`. An unqualified reference resolves first to the current pack, then to dependencies in declared order. Ambiguity is an error. Each def may include a `notes` field, which the validator ignores and the editor displays. This replaces JSON comments.

Runtime identity never depends on array order. Station trade IDs, encounter node IDs and default loadouts become explicit fields.

### 5.4 Inheritance and patches

- `"parent": "core:station_base"` deep-merges the parent first. Objects merge, arrays replace and `null` removes a field. `"abstract": true` defs are templates and are never instantiated.
- A `patch` def changes another pack's def without copying it:

```json
{"type": "patch", "id": "pirate_tuning", "target": "core:pirate_raider",
 "set": {"cost": 14, "stats.hull": 120},
 "append": {"tags": ["late_game"]},
 "remove": {"tags": ["early_game"]}}
```

Paths can select array items by their `id`, such as `stages[escape].deadline`. Patches apply after all defs load, in pack order. When two packs set the same path, the editor reports a conflict warning.

### 5.5 Schemas are the single source of truth

Each def type has a schema file under `res://schemas/defs/<type>.schema.json`. These files use a JSON Schema subset with extension keywords:

- `x-ref`: the referenced def type, such as `"x-ref": "faction"`.
- `x-expr`: the expected result type and context, such as `{"type": "bool", "context": "site"}`.
- `x-text`: a player-facing template string that supports interpolation and grammar.
- `x-asset`: an image or audio path relative to the pack.
- `x-editor`: inspector hints, including widget, group, order and inline help.

One schema drives:

1. Load-time validation and Problems.
2. Automatically generated editor inspector forms and reference pickers.
3. Exported JSON Schema for VS Code. `tools/export_schemas.gd` writes `schemas/json/` and `.vscode/settings.json` maps `packs/**/defs/**/*.json` to the dispatching schema, which enables autocomplete and inline errors for hand editing.
4. Generated reference documentation for modders.

Engine behaviors that data composes, such as weapon types, effect operations, objective types and generator stages, register their parameter schemas in the same registry.

### 5.6 Load pipeline and Problems

The loader runs these steps:

1. Discover packs.
2. Order them topologically by dependencies, then by ID.
3. Parse JSON.
4. Resolve inheritance.
5. Apply patches.
6. Validate schemas.
7. Resolve references.
8. Compile formulas.
9. Run type-specific checks, such as reachable quest stages and objectives with a role.
10. Freeze the database and compute its content hash.

Each problem includes severity, pack, file, def ID, JSON path and message. Errors disable that pack and any pack that depends on it. Warnings load. `tools/validate_packs.gd` prints the same problems from the command line for CI and hand editing.

### 5.7 Assets

`core:art/...` addresses built-in `res://` assets. Pack assets load at runtime with `Image.load_from_file` and `AudioStreamOggVorbis.load_from_file` and are cached by content hash. Missing art keeps the existing visible missing-art marker.

### 5.8 Runs freeze their content

When a run starts, it writes `content.json` beside the save. This file contains the resolved defs used by the run, plus pack IDs, versions and hashes. A Workshop update cannot break an existing run. Assets are not copied; if a pack is removed, its art shows the missing-art marker. The run browser identifies runs whose packs have changed and starts new runs on the current versions.

## 6. Formula language

Conditions, weights, costs, budgets and text conditions use one safe expression language. It is compiled once at load time and type-checked. Godot's `Expression` class is not used because it can call engine methods, has no static checking and reports errors poorly.

```text
credits > 2000 and region.lawless >= 0.6
clamp(stat.wealth / 1500, 0.5, 3) * difficulty.threat
between(distance(this, role.origin), 250, 600)
history(role.captain, 'spared_by_player') > 0
if pressure.swarm > 50 then 2 else 1
```

- **Values:** numbers, strings, booleans, entity references, lists and `null`.
- **Operators:** `+ - * / % ^`, comparisons, `and or not`, `in`, `if ... then ... else`.
- **Paths:** these are read-only views supplied by the field's declared context. Examples include `this`, `role.<name>`, `site`, `fleet`, `stat.<id>`, `pressure.<id>`, `faction.<id>`, `quest.<id>`, `vars.<name>` and `day`.
- **Functions:** these come from a whitelist registry. Initial functions are `min`, `max`, `clamp`, `abs`, `floor`, `ceil`, `round`, `lerp`, `between`, `curve(id, x)`, `has_tag(e, tag)`, `distance(a, b)`, `count(type, condition)` (the condition is evaluated per candidate with `this` bound), `history(entity, tale)`, `recent(tale, days)`, `days_since(tale_or_hook)`, `quest_state(id)` and `standing(faction)`.
- **No side effects and no randomness.** Randomness belongs to the director, weighted pools, casting and the `roll` effect, which use named RNG streams.
- **Implementation:** lexer -> Pratt parser -> abstract syntax tree -> type checker against the context schema -> closure tree for evaluation. Errors report the column and field path, and the editor shows them live.

## 7. World state

### 7.1 Entities in the run document

| Entity | Key data |
| --- | --- |
| Galaxy | Shape, extent, regions (polygons, archetype and properties), hazards and zones |
| Site | ID, archetype, position, region, owner faction, tags, services, stock tables, `vars` and knowledge state |
| Faction | Def, standing toward the player, attention, strength, territory and relations |
| Actor | Archetype, generated name, faction, traits, home site, status and chronicle references |
| Fleet | Current ships, equipment UIDs, squadrons, loads, research, credits, fuel and missiles |
| Quest instance | Def, kind, role bindings, stage, objective progress, deadline, children and variables |
| Pressure | Value, rate cache and threshold crossings |
| Director | Story budget, tension history, cooldowns and decision log (ring buffer) |
| Chronicle | Tales: day, type, actors, sites, factions, quest, importance and data |

Designers add free-form `vars` and `tags` to global, site, actor, faction and quest scopes through effects. Existing story flags become global tags.

### 7.2 Stats

Stats are derived formulas that are cached per transaction and optionally smoothed:

```json
{"type": "stat", "id": "wealth", "label": "Wealth", "icon": "core:art/icons/wealth.png",
 "formula": "credits + fleet.market_value + cargo.value", "smoothing_days": 5}
```

Core stats include `wealth`, `fleet_power` (from the battle calibration in section 15), `notoriety`, `supply_days`, `morale` (Homeward) and `alien_awareness`. Smoothing prevents a single sale from causing a raid.

### 7.3 Pressures and clocks

```json
{"type": "pressure", "id": "swarm", "label": "Swarm", "min": 0, "max": 100, "initial": 0,
 "rate_per_day": "0.4 + 0.02 * stat.alien_awareness",
 "thresholds": [{"at": 50, "hook": "swarm.surging"}, {"at": 90, "hook": "swarm.overwhelming"}],
 "visible": "meter"}
```

Pressures replace the current Swarm Intensity code. Rules, director weights and threat formulas read them. A quest clock is a pressure scoped to one quest instance, which fronts use.

### 7.4 Knowledge

Each site and quest hook has a knowledge state: `unknown`, `rumored`, `charted` or `visited`. A rumor can reveal a site or quest hook with partial, and occasionally wrong, details, such as "pirates were sighted near Kessel." Arrival resolves the truth. This creates exploration and lets quests start from overheard information without long text.

## 8. Hooks, effects and transactions

### 8.1 Hooks

Engine hooks include:

- `run.started`, `day.passed`
- `travel.departed`, `travel.arrived`, `travel.zone_entered`, `travel.stranded`
- `battle.started`, `battle.won`, `battle.lost`, `battle.withdrawn`
- `ship.lost`, `ship.acquired`, `research.completed`, `trade.completed`
- `quest.started`, `quest.stage`, `quest.ended`
- `pressure.crossed`, `standing.changed`, `scene.choice`

Packs may emit custom hooks with `{"emit": "frontier_tales:beacon_lit"}`.

Hooks queue inside the current transaction. The engine processes them in FIFO order and delivers them first to engine systems, then to quest instances in start order, then to rules by priority and ID. A cascade limit of 64 hooks per transaction stops the cascade and records a Problem.

### 8.2 Effects

Effects use one-key objects so they are easy to read and write by hand. Values may be formulas.

```json
[{"credits": "-60"}, {"fuel": 40},
 {"standing": {"faction": "role.raiders.faction", "add": -10}},
 {"start_quest": {"id": "smuggling_job", "bind": {"from": "role.origin"}}},
 {"battle": {"encounter": "pirate_ambush", "budget": "threat_points * 0.8",
             "on_won": "stage:escape", "on_lost": "outcome:failure"}},
 {"chronicle": {"tale": "rescued_crew", "actors": ["role.captain"]}},
 {"if": "stat.notoriety > 40", "then": [{"pressure": {"id": "bounty", "add": 5}}]},
 {"roll": [{"weight": 3, "do": [{"fuel": 20}]}, {"weight": 1, "do": [{"hull_damage": 15}]}]}]
```

Initial operations are these:

- Resources: `credits`, `fuel`, `missiles`, `research_points`, `hull_damage`, `repair`, `add_ship`, `remove_ship` and `give_equipment`.
- State: `set_var`, `add_tag`, `remove_tag`, `standing`, `pressure`, `reveal`, `rumor` and `spawn_site`.
- Story: `start_quest`, `advance`, `end_quest`, `scene`, `battle`, `chronicle`, `emit`, `price_modifier`, `if` and `roll`.

Each operation registers a schema, validation, an applier and an explanation string.

### 8.3 RunTransaction

`RunTransaction` generalizes the current `proposal = hangar_snapshot(); mutate; _save_hangar; _apply_hangar` pattern:

```gdscript
var tx := Run.begin("travel.arrive")
TravelSystem.arrive(tx, site_id)       # mutates tx.doc, emits hooks
if not tx.commit():                    # hooks -> rules/quests/director -> validate -> atomic save
    show_error(tx.error)               # nothing changed in memory or on disk
```

- The working document is a deep copy. Profile it and add structural sharing only if needed.
- Continuous travel moves the fleet in a lightweight travel state between boundaries, as it does today. Day boundaries, arrivals, zone entries and stops are transactions, so hooks, director ticks and saves happen there instead of every frame.
- The `battle` effect commits a pending battle with its continuation: source quest or scene and the `on_won`, `on_lost` and `on_withdrawn` targets. Battle settlement is its own transaction. It emits the outcome hook and resumes the continuation.
- Commit validates schema invariants, writes through the existing `AtomicRunStore`, swaps the document and emits `Run.changed(sections)` for the UI.
- RNG draws use named streams keyed by `(seed, stream, scope, counter)` with FNV-1a 64-bit stable hashing, not Godot `hash()`, because Godot's hash is not guaranteed stable across engine versions. Counters persist in the document.

### 8.4 Run storage

```text
user://runs/<run_id>/run.json       AtomicRunStore envelope containing the run document
user://runs/<run_id>/content.json   frozen resolved defs + pack list/hashes (written once)
```

The run document has these sections: `meta` (format, version, scenario, mode, seed, packs, content hash), `rng`, `clock`, `galaxy`, `sites`, `factions`, `actors`, `fleet`, `travel`, `quests`, `pressures`, `director`, `chronicle` and `vars`. Load normalizes JSON numbers with the schema, which removes scattered `int()` casts. The main menu lists several runs. This replaces the current single checkpoint, `HangarCheckpoint`, the legacy `CampaignGraph` validation and `SwarmNavigation`.

## 9. Quests

### 9.1 Kinds

| Kind | Purpose | Admission |
| --- | --- | --- |
| `primary` | Scenario milestones that define the main thread | Guaranteed by the scenario's milestone windows |
| `secondary` | Optional arcs and jobs | Scenario pools at start, and director opportunities during play |
| `incident` | Short one- or two-stage situations | Director, rules or travel zones |
| `front` | Antagonist plans that advance by themselves | Scenario or rules; can spawn other quests |
| `background` | Invisible logic for designers | Scenario or rules |

### 9.2 Anatomy

```json
{
  "type": "quest", "id": "smugglers_debt", "kind": "secondary",
  "group": "frontier_side_arcs", "tags": ["crime", "arc"],
  "title": "Debt at {role.origin.name}",
  "admission": {"when": "day >= 5 and standing(faction.syndicate) > -30", "unique": true, "cooldown_days": 30},
  "roles": {
    "origin": {"site": {"filter": "has_tag(this, 'station') and this.faction.kind == 'independent'",
                        "prefer": "-distance(this, fleet)"}, "exclusive": true},
    "destination": {"site": {"filter": "has_tag(this, 'station') and between(distance(this, role.origin), 250, 600)"}},
    "fixer": {"actor": {"filter": "this.archetype == 'smuggler_fixer'", "prefer": "history(this, 'met_player') * 5",
                        "spawn": {"archetype": "smuggler_fixer", "home": "role.origin"}}}
  },
  "children": {"group": "smuggling_jobs", "count": "2..4", "order": "sequence",
               "bind": {"from": "role.origin", "to": "role.destination", "contact": "role.fixer"}},
  "stages": [
    {"id": "meet", "journal": "Meet {role.fixer.name} at {role.origin.name}.",
     "objectives": [{"reach": "role.origin"}],
     "transitions": [{"on": "travel.arrived", "if": "site == role.origin", "do": [{"scene": "fixer_offer"}]}]},
    {"id": "jobs", "journal": "Run jobs for {role.fixer.name}.",
     "objectives": [{"children_completed": "2"}],
     "deadline": {"days": 40, "to": "outcome:failure"},
     "transitions": [{"if": "children.completed >= 2", "to": "stage:payoff"}]},
    {"id": "payoff", "objectives": [{"reach": "role.destination"}],
     "transitions": [{"on": "travel.arrived", "if": "site == role.destination", "to": "outcome:success"}]}
  ],
  "outcomes": {
    "success": {"do": [{"credits": "300 + 50 * children.completed"}, {"standing": {"faction": "syndicate", "add": 15}}],
                "establishes": ["syndicate_trusted"], "chronicle": "debt_paid"},
    "failure": {"do": [{"standing": {"faction": "syndicate", "add": -25}}],
                "establishes": ["syndicate_grudge:{role.fixer}"], "chronicle": "debt_defaulted"}
  }
}
```

### 9.3 Roles and casting

- **Role types:** `site`, `actor`, `faction`, `region` and `ship` (player ships, for internal politics).
- **Strategies in order:**
  1. `bind`: from the parent, scenario pin or hook payload.
  2. `filter` plus `prefer`: score the existing candidates. The best score wins by default; `pick: "weighted"` samples by score.
  3. `spawn`: create from an archetype under placement constraints relative to other roles, such as "near `role.origin`, in a lawless region, at least 200 NU from start."
- Roles are cast in dependency order, so later filters can read earlier roles. If a required role fails, the quest is not admitted and the explanation records why.
- `exclusive` reserves a site or actor while the quest is active, which prevents two stories from claiming the same fixer.
- **Callbacks:** the director adds a configurable bonus to candidates with chronicle history. This makes recurring characters emerge without authored sequels.

### 9.4 Stages, objectives and transitions

- `objectives` are player-facing and generate journal lines, map markers and progress. Initial types are `reach`, `defeat`, `deliver`, `survive_days`, `wait_until`, `children_completed` and `choose`.
- `transitions` contain the logic. A transition may listen to a hook with `on`, test a condition with `if`, run effects with `do` and move to a stage or outcome with `to`. The hook payload is exposed by name, such as `site`, `battle`, `ship` and `option`. Transitions without `on` are re-checked at the end of hook processing inside the same transaction until nothing changes, subject to the cascade limit.
- A deadline shows as a clock icon and makes failure explicit.
- Outcomes apply effects, write a chronicle tale and add `establishes` tags. Other quests can `require` or `exclude` these tags, which forms the quest web.

### 9.5 Arcs, slots and designer surprise

The request "one of five side arcs starts at station X and ends at Y, with Z random related mini quests" is expressed as follows:

- Five arc quests share `"group": "frontier_side_arcs"`.
- The scenario declares `"secondary": [{"group": "frontier_side_arcs", "pick": 1}]` and may pin a role, such as `"pin": {"origin": "haven_dock"}`.
- The arc's `children` group supplies Z jobs, cast relative to the arc's roles. A group is just the set of quests that share a `group` value, so any pack can add arcs or jobs to an existing group.

The designer controls structure, endpoints and tone. The generator controls which arc, which stations, which jobs and which actors. Pinning and regenerating in the editor let the designer decide how much surprise is allowed.

### 9.6 Fronts

A front is the antagonist's quest:

```json
{"type": "quest", "id": "warlord_rise", "kind": "front",
 "roles": {"warlord": {"actor": {"spawn": {"archetype": "pirate_warlord"}}},
           "haven": {"site": {"spawn": {"archetype": "pirate_haven", "region": "this.lawless > 0.6"}}}},
 "clock": {"max": 100, "rate_per_day": "0.6 + 0.2 * count('site', this.owner == role.warlord.faction)"},
 "portents": [
   {"at": 25, "do": [{"rumor": {"text": "Ships flying {role.warlord.name}'s colors were seen near {role.haven.region.name}."}}]},
   {"at": 60, "do": [{"start_quest": {"id": "warlord_blockade", "bind": {"warlord": "role.warlord"}}}]},
   {"at": 100, "do": [{"end_quest": "outcome:warlord_ascendant"}]}],
 "transitions": [{"on": "battle.won", "if": "battle.commander == role.warlord", "to": "outcome:warlord_slain"}]}
```

The Leviathan swarm, corporate cover-ups, military assembly and Homeward mutinies are all fronts. The map shows portents in the world instead of explaining them in text.

## 10. Scenes, text and voice

### 10.1 Scenes

Scenes generalize today's expedition events and keep the four-option limit:

```json
{"type": "scene", "id": "fixer_offer",
 "nodes": [
   {"id": "start", "speaker": "role.fixer", "art": "role.fixer.portrait",
    "text": [{"if": "has_tag(role.fixer, 'spared_by_player')", "text": "\"You let me live once. Let's both profit.\""},
             {"text": "\"{role.destination.name} pays well for discreet cargo.\""}],
    "options": [
      {"label": "Accept", "do": [{"advance": "jobs"}]},
      {"label": "Pay the debt ({vars.debt} cr)", "enabled_if": "credits >= vars.debt",
       "disabled": "Need {vars.debt} credits", "do": [{"credits": "-vars.debt"}, {"end_quest": "outcome:success"}]},
      {"label": "Decline", "do": [{"end_quest": "outcome:failure"}]}]}]}
```

A node may start a battle and continue to `on_won`, `on_lost` or `on_withdrawn` nodes. A scene opened by a quest inherits that quest's roles.

### 10.2 Templates and grammars

- Interpolation: `{role.origin.name}`, `{credits}` and `{days(stage.deadline)}`.
- Grammar expansion: `[pirate_ship_name]` expands a Tracery-style grammar def. Expansions use an RNG stream seeded by the entity ID, so a name stays stable.
- Variant lists use first match. Every player-facing field still follows the concise text rules in [AGENTS.md](../AGENTS.md).

### 10.3 Response lines

For flavor that should feel alive without bespoke scripting, packs provide lines keyed by concept:

```json
{"type": "line", "concept": "station_greeting", "speaker": "faction:syndicate",
 "when": "stat.notoriety > 60", "text": "\"Keep your guns cold, {fleet.flagship.name}.\""}
```

The engine selects the most specific match. Specificity is the number of satisfied criteria, and weight and recency break ties. This follows Valve-style dynamic dialogue rules. Station greetings, captain remarks, battle barks and log summaries use it, so adding a line makes it eligible automatically.

### 10.4 Chronicle and Captain's Log

`tale` defs declare a type, importance, scopes and a log template. Engine hooks write common tales, such as battles, losses, arrivals at new regions and quest outcomes. Quests write their own tales. Expressions query history for casting, conditions and text. The run ends with a Captain's Log: a short narrative assembled from the most important tales through response lines. A Log page during the run shows the same entries.

## 11. Rules: designer influence

A rule is either continuous (`while`) or one-shot (`on` and/or `when`, with `cooldown_days` and `max_times`).

```json
{"type": "rule", "id": "rich_targets", "while": "stat.wealth > 2000",
 "modify": [{"target": "encounter_unit_weight", "ids": ["pirate_raider", "pirate_gunship", "pirate_corvette"],
             "multiply": "1 + (stat.wealth - 2000) / 2000"},
            {"target": "quest_weight", "tags_any": ["pirate"], "multiply": 1.5}]}

{"type": "rule", "id": "bounty_hunters", "on": "travel.arrived",
 "when": "site.region.lawless > 0.5 and stat.notoriety > 40", "cooldown_days": 20,
 "do": [{"start_quest": {"id": "bounty_hunters_ambush"}}]}
```

- Modifier targets are registered engine knobs: `encounter_unit_weight`, `quest_weight`, `category_weight`, `price`, `fuel_rate`, `pressure_rate`, `threat_points`, `standing_drift`, `stock_weight` and `repair_cost`. Each declares how it stacks and its safety caps.
- Every active modifier appears in the debug overlay and Forecast with its source rule.
- Scenarios enable rules from libraries and add their own. Modes provide defaults.

## 12. Director

### 12.1 Profile

```json
{"type": "director_profile", "id": "measured",
 "progress": "days",
 "target_tension": {"points": [[0, 0.15], [20, 0.4], [45, 0.3], [70, 0.7], [90, 0.5]]},
 "tension": "0.4 * threats_active + 0.3 * (1 - fleet.hull_ratio) + 0.3 * recent('ship.lost', 10)",
 "budget_per_day": "1 + stat.wealth / 2000",
 "threat_points": "max(80, stat.fleet_power * 0.7 + stat.wealth * 0.02) * difficulty.threat",
 "gap_days": {"min": 2, "max_quiet": 7},
 "categories": {"threat": 1.0, "opportunity": 1.0, "mystery": 0.6, "social": 0.5, "relief": 0.8},
 "freshness": {"tag_half_life_days": 12, "repeat_penalty": 0.5},
 "callback_bonus": 1.6,
 "adaptation": null}
```

### 12.2 Daily decision

1. Advance pressures and front clocks, and accrue budget.
2. Respect `gap_days`. When the minimum gap has passed, the chance rises until `max_quiet` forces a decision.
3. Choose a category from the gap between target and actual tension. Below the target favors threat or mystery; above it favors relief or opportunity.
4. Collect candidates whose admission conditions pass and whose budget cost is affordable. Score them as base weight × category fit × freshness × callback bonus × rule modifiers. Cast only the top eight so that daily evaluation stays cheap.
5. Admit the winner, deduct its cost and log the decision with the runner-up scores.

Primary milestones declare windows such as `{"earliest": 15, "latest": 30, "quiet_before": 3}`. The director avoids large threats immediately before a milestone and forces the milestone at `latest`. Mercy is explicit. A profile can enable `adaptation` (RimWorld-style), but the director never silently eases difficulty.

### 12.3 Threat points and encounters

`threat_points` replaces the fixed `100 * 5^proximity` curve. Encounters spend it through data, as described in section 13.3. Difficulty presets and scenario multipliers are data.

### 12.4 Time

Expedition time currently advances only during travel. Fronts, deadlines and director ticks use the same day clock. Optional docked actions, such as Repair or Wait, can advance days explicitly. An incident admitted during travel stops the fleet at that boundary, as current zone events do.

## 13. Factions, actors and encounters

### 13.1 Factions

A faction def contains:

- Name grammar, kind (`human` or `alien`), color and icon.
- Standing thresholds: hostile, wary, neutral, friendly and allied, with effects on trade access, prices and encounter hostility.
- Territory preferences by region archetype and strength.
- Encounter pools, actor archetypes, fronts it can run and default relations.

Built-in factions follow [the story specification](STORY_SPEC.md): the player's company, the Colonial Military Authority, the Research Corporation, independents, pirates, the Leviathan and Chrysalis-linked swarms.

### 13.2 Actors

Actor archetypes contain a name grammar, faction, trait pool, portrait set and role tags. Generation creates key actors, such as faction leaders and station masters, and casting spawns others. Later, player captains become actors attached to ships with traits and loyalty. Homeward politics casts them into social incidents with roles such as `dissenter` or `loyalist`, using `ship` and `actor` roles.

### 13.3 Encounters and enemy units

- `enemy_unit` defs replace `AlienShip.ROLE_COSTS`, `TIER_*` and the fixed name list. They contain stats, rank tiers, cost, tags, behavior role and art.
- Human enemies use existing chassis and loadout defs. The cost is a formula over equipment value. This turns every player-facing chassis and loadout into enemy content.
- `encounter` defs replace `EncounterGenerator.TEMPLATES`. They contain a faction or pool, required units, waves, objective type, environment, reward formulas and a budget multiplier. The composer fills the budget from weighted pools that rules can modify, using a named RNG stream.
- The battle simulator maps factions onto its three sides: player, hostile and neutral. It gains a hostile owned-ship setup path so human fleets use the same fitted-ship stats as the player.

## 14. Galaxy generation

### 14.1 Parameters

```json
"galaxy": {"preset": "medium", "shape": "spiral_arm", "radius": 1000,
           "regions": 14, "site_density": 1.0, "lawless": 0.4, "alien_presence": 0.3,
           "factions": ["military", "corporation", "independents", "pirates", "leviathan"],
           "fuel_margin": 1.3}
```

The Small, Medium, Large and Huge presets set radius, region count and site count, roughly 30, 70, 150 and 300 sites. Individual fields override a preset.

### 14.2 Stages

Each stage uses its own RNG stream, records explanations and can be previewed separately:

1. **Shape:** sample candidate points with Poisson disk sampling inside a shape mask (disc, spiral arm, band, clusters or corridor).
2. **Regions:** choose seeds, assign Voronoi cells and select region archetypes (core, frontier, nebula, lawless, alien space or void) by weighted rules.
3. **Territory:** grow faction claims from capitals across region adjacency.
4. **Sites:** place scenario pins and required sites first. Then fill site archetypes from region and faction tables with spacing rules.
5. **Supply:** build the fuel-range travel graph. Guarantee connectivity with a minimum spanning tree and insert depots or caches where gaps exceed the safe range multiplied by `fuel_margin`.
6. **Hazards:** create nebulae, belts and storms as zones with travel and battle effects.
7. **Names:** apply region, faction and site grammars and ensure unique names.
8. **Start:** apply the scenario start rule.
9. **Actors:** create key actors per faction and site.
10. **Story:** cast primary milestones and starting secondary pools.
11. **Validate:** check reachability, milestone feasibility and minimum services near the start. On failure, retry with the next sub-seed up to a limit, then report.

The generated galaxy is saved in the run document and never regenerated, so generator changes cannot break existing runs.

### 14.3 GalaxyView

`GalaxyView` replaces the current location-bound map drawing. It draws regions, territory borders, sites, routes, hazards, knowledge fog and quest markers, with culling and level of detail. The editor uses it with debug layers: stage overlays, the supply graph, explanations and casting highlights. Pan and zoom remain.

## 15. Balance tooling

- **Battle Bench** (`tools/battle_bench.gd`): run real headless battles across fleet and encounter compositions, then fit `fleet_power` and enemy unit costs so threat points mean the same thing everywhere.
- **Forecast** (`tools/forecast.gd`, also in the editor): simulate N seeds for D days with a bot policy. Travel follows objectives, and battles auto-resolve from the calibrated power estimate. The report covers incidents by category, tension against target, wealth and credits curves, losses, quest completion and rule activations. Saved reports become regression baselines.
- Both tools are opt-in. They run when balance or director data changes, not as default checks.

## 16. Scenarios and modes

```json
{"type": "scenario", "id": "leviathan_protocol", "mode": "leviathan",
 "title": "The Leviathan Protocol", "preview": "art/preview.png",
 "galaxy": {"preset": "medium", "shape": "spiral_arm", "lawless": 0.35, "alien_presence": 0.25},
 "start": {"site": {"archetype": "home_port", "region": "frontier"}, "fleet": "leviathan_charter", "credits": 700},
 "pins": {"meridian": {"archetype": "civilian_refuel_port", "near": "start", "distance": [180, 320]}},
 "primary": [{"quest": "act1_meridian", "window": {"earliest": 0, "latest": 12}},
             {"quest": "act1_broadcast", "after": "act1_meridian", "window": {"earliest": 4, "latest": 20}},
             {"quest": "act2_protocol", "after": "act1_broadcast"}],
 "secondary": [{"group": "frontier_side_arcs", "pick": 1}, {"group": "core:odd_jobs", "pick": "1..2"}],
 "fronts": ["leviathan_swarm", {"group": "core:human_fronts", "pick": 1}],
 "director": "measured", "rules": ["core:economy_default", "rich_targets"],
 "victory": "quest_state('act2_protocol') == 'success'", "defeat": "fleet.flagship_lost"}
```

| Mode | Shape of play | Defaults |
| --- | --- | --- |
| Leviathan | Authored milestones from the story specification, cast onto a generated frontier. Human and alien factions react to the Protocol. | Measured director, swarm front, story factions |
| Adventure | No main arc. An escalation pressure grows exponentially, and rules unlock harsher global effects at thresholds. Score or survival victory. | Escalating director, broad incident pools, score tales |
| Homeward | Cross a long, sparse corridor to reach home. Supply and fleet politics dominate. | Sparse director, social and supply pools, captains, mutiny front |

A mode is a def that supplies defaults: director, rules, fronts, victory and defeat conditions, and UI emphasis. A scenario selects a mode and overrides only what it needs. A Workshop scenario can be a recipe, which generates a new galaxy per seed, or a fixed edition, which pins a seed and may hand-pin most sites.

## 17. Scenario Editor

### 17.1 Principles

- **One editor.** The in-game editor is also the development tool. Writing to `res://packs/` is allowed only in unexported developer runs. Otherwise, the editor writes to `user://packs/`.
- **JSON stays first-class.** The editor writes formatted JSON in schema field order, preserves notes and reloads external edits by polling modification times. Hand editing in VS Code with exported schemas remains equally supported.
- **Undo and redo** use Godot's `UndoRedo`. Drafts autosave beside the pack.
- **Resolution.** On entry, the editor disables the 640x360 content scale and uses the native window size, with a 1280x720 minimum. It restores the game scale on exit.
- **UI rules still apply.** There are no hover tooltips or Tab/arrow focus cycling. Inline help appears in the inspector footer for the selected field. Windows use the shared X.

### 17.2 Layout

The layout has a project browser on the left, the active workspace in the center, a schema inspector on the right and Problems plus the generation or director log at the bottom. Selecting a problem navigates to the def and field.

### 17.3 Workspaces

| Workspace | Purpose |
| --- | --- |
| Pack | Manifest, dependencies, preview image, validation summary and publishing |
| Library | Every def type through schema-generated forms, with references, "used by" lists and inheritance/patch views |
| Scenario | Recipe form, mode defaults, pins and milestone timeline |
| Galaxy | Generate by seed, step through stages, inspect any site's explanation, pin or unpin, regenerate a stage and compare seeds |
| Quests | Quest list, stage graph (nodes are stages and edges are transitions), role casting preview against a chosen seed and scene editor |
| Story Lab | Load a seed, force-admit a quest, step hooks and days, inspect facts and transitions |
| Director | Draw target tension curves, edit category weights and run Forecast with charts |
| Text | Grammar tester, template preview with real casting and response-line matching inspector |
| Playtest | Launch the real game from a scenario and seed with an isolated save. The debug overlay shows facts, active modifiers, director decisions and jump-to-def links. |

The full stage graph is the only node-graph surface. Everything else uses forms and lists, because large node graphs slow down routine editing.

## 18. Packaging and Steam Workshop

- `WorkshopService` is an interface with a `LocalWorkshop` implementation, which copies to and from `user://packs`, and later a `SteamWorkshop` implementation using the GodotSteam GDExtension. Compatibility with Godot 4.7 must be verified before that phase.
- **Publish:** validate with zero errors -> build a playable copy without drafts or editor caches -> `CreateItem`, using the stored `published_file_id` when present -> `SetItemContent(folder)` -> `SetItemPreview` -> tags (kind, mode, size) -> `SubmitItemUpdate` -> handle the legal-agreement flag -> save the ID in `pack.json`.
- **Subscribe:** discover packs with `GetSubscribedItems` and `GetItemInstallInfo`. They are read-only sources. "Make editable copy" creates a new local pack ID.
- Runs freeze content (section 5.8), so updates never break a run in progress.
- Security: packs contain only data and assets. Archives and paths are sanitized. Packs cannot load scripts, PCKs or absolute paths.

## 19. Code organization and migration map

```text
scripts/core/       stable_hash.gd, rng_streams.gd, atomic_run_store.gd
scripts/content/    pack_manifest.gd, pack_loader.gd, def_database.gd, schema_registry.gd, def_validator.gd, patcher.gd, problems.gd
scripts/expr/       lexer.gd, parser.gd, type_checker.gd, evaluator.gd, functions.gd
scripts/run/        run_document.gd, run_transaction.gd, hooks.gd, fact_view.gd, effects/*.gd
scripts/world/      galaxy/*.gd (stages), sites.gd, factions.gd, actors.gd, stats.gd, pressures.gd
scripts/story/      quests.gd, casting.gd, scenes.gd, text_template.gd, grammar.gd, response_lines.gd, chronicle.gd, director.gd, rules.gd
scripts/encounters/ encounter_composer.gd
scripts/editor/     editor_root.gd, inspector/*.gd, workspaces/*.gd
scripts/workshop/   workshop_service.gd, local_workshop.gd, steam_workshop.gd
packs/core/, packs/leviathan/, schemas/defs/, schemas/json/ (generated), tools/
```

| Current | Fate |
| --- | --- |
| `data/*.json` | One-time conversion into `packs/core` and `packs/leviathan` defs (P1); then deleted |
| `game_definitions.gd`, `slot_catalog.gd`, `ship_loadouts.gd` | Thin views over `DefDatabase` (P1), then callers use `Content` directly (P2) |
| `hangar_research.gd` filters and rewrites, `research_rules.gd` whitelist | Research defs state their own availability and prerequisites; modifiers become registered knobs (P2) |
| `alien_ship.gd` costs and tiers, `encounter_generator.gd` templates and threat curve | `enemy_unit` and `encounter` defs (P2); threat points come from the director (P7) |
| `hangar_trade.gd`, `shared_support.gd`, `battle_abilities.gd` constants, `hangar_screen.gd` `_part_effect` text | Economy, support and ability defs; effect text generated from behaviors (P2) |
| `start_new_run` hardcoded fleet and credits | Scenario `start` block plus a fleet package def (P2/P6) |
| `hangar_state.gd` | Thin `GameState` facade over `Run`, `Content` and systems (P3) |
| `hangar_checkpoint.gd`, `campaign_graph.gd`, `campaign_content.gd`, `swarm_navigation.gd`, `run_score.gd` | Replaced by the run document, galaxy, pressures, stats and chronicle (P3) |
| `scripts/legacy/`, `test_legacy_archives.gd`, unused square or hex helpers | Audit references and delete unused code (P2), because legacy saves are out of scope |
| `expedition_events.gd` | Quests, scenes and rules (P4) |
| `expedition_state.gd`, `expedition_simulation.gd` | Travel system reading galaxy sites and zones from the run document (P3/P6) |
| `expedition_map.gd` | `GalaxyView` (P6) |
| `battle_simulation.gd` `Faction` enum | Side mapping from factions, plus hostile owned-ship setup (P7) |
| `main_menu.gd` | Scenario browser, run list and editor entry (P5/P6) |

## 20. Implementation phases

Each phase leaves the game playable, adds its editor surface when the editor exists, deletes the code it replaces and closes with focused tests. Sizes are relative: S is a few sessions, M is about a week of focused sessions and L is several weeks.

### P1 - Content foundation (L)

1. Add `StableHash` (FNV-1a 64-bit) and `RngStreams`.
2. Add a pack manifest and loader for `res://packs` and `user://packs`, with dependency ordering and Problems.
3. Add a schema registry, a validator for the JSON Schema subset and its extensions, inheritance and patch defs.
4. Add the formula language: lexer, Pratt parser, type checker, evaluator and function registry.
5. Add `DefDatabase` with typed lookups and a content hash, plus a `Content` autoload.
6. Convert `data/*.json` into defs. Point `GameDefinitions`, `SlotCatalog`, `ShipLoadouts`, `ExpeditionState` and `ExpeditionEvents` at `Content`, then delete `data/`.
7. Add `tools/validate_packs.gd` and `tools/export_schemas.gd`, plus the VS Code schema mapping.

Acceptance: current gameplay is unchanged. `core` and `leviathan` validate with zero problems. Broken fixture packs produce the expected Problems with paths. VS Code autocompletes and flags a def file. Formula tests cover precedence, typing errors and evaluation.

### P2 - One authority for content (M)

1. Move the hardcoded authorities in the migration map into defs: research availability, enemy units, encounter templates, trade fares, support constants, ability parameters, starting fleet package and equipment effect text.
2. Replace array-order identities with explicit IDs.
3. Replace generation `hash()` seeds with stable streams.
4. Audit and delete legacy readers and unused square or hex code.

Acceptance: searches find no gameplay constants listed in the migration map. A patch-only test pack can change an enemy cost, a trade fare and a starting credit amount. Focused research, encounter and trade tests pass.

### P3 - Run core (L)

1. Add `RunDocument`, `RunTransaction`, hooks, `FactView`, the effect registry, stats, pressures and the chronicle skeleton.
2. Add the `user://runs/<id>/` layout with content freezing and a multi-run list.
3. Split `hangar_state.gd` into a facade plus Fleet, Travel, Trade, Research and Battle-settlement systems that use transactions.
4. Convert Swarm Intensity into a pressure.
5. Delete `HangarCheckpoint`, the campaign graph, `SwarmNavigation` and `RunScore`.

Acceptance: the current loop works through travel, events, trade, battle, refit and resume. Failure injection at every commit leaves memory and disk unchanged. The same seed and command list produce an identical document. Pressure and stat formulas come from defs.

### P4 - Story engine (L)

1. Add quests (roles with `bind` and filter casting, stages, objectives, transitions, deadlines, children, outcomes, establishes/requires/excludes), scenes, templates, grammars, response lines and rules.
2. Add journal and map markers.
3. Re-express Act I, the frontier events and the departure/broadcast/defense beats as `leviathan` quests and scenes on the current authored map, using pinned roles.
4. Delete the expedition event code.

Acceptance: the existing Act I branches reproduce their outcomes, rewards and service closures. A test quest with children, a deadline and a callback passes state-machine tests. Rule `while` and `when` semantics are covered.

### P5 - Editor v1 (L)

1. Add the editor shell: resolution switching, pack browser, Problems, undo/redo, drafts and stable JSON writing.
2. Add schema-generated Library forms with reference pickers, formula fields, curves and positions.
3. Add the Quest workspace (stage graph and scene editor), Story Lab and Text tester.
4. Add Playtest with an isolated save and debug overlay.
5. Add main-menu entry.

Acceptance: from the main menu, create a pack, add an incident and a secondary quest with a scene and rule, playtest it and see it fire, without touching JSON. Use focused native interaction checks at 1280x720 and 1920x1080.

### P6 - Galaxy, scenarios and casting (L)

1. Add the scenario and mode defs and all galaxy stages with explanations, pins and validation and retry.
2. Add spawn casting with placement constraints, knowledge states and rumors.
3. Add `GalaxyView` for the game map and editor.
4. Add the Galaxy workspace and scenario browser.
5. Let the travel system use generated sites and zones.

Acceptance: 100 seeds per preset pass invariants: reachable sites, feasible milestones and start services. Leviathan Act I is cast onto generated galaxies and remains completable. Explanations exist for every site. Map pan, zoom and readability are checked natively.

### P7 - Director, factions, fronts and encounters (L)

1. Add director profiles, tension, budget, scoring, milestone windows, logs and threat points.
2. Add the encounter composer from defs.
3. Add faction standing, territory, attention and fronts.
4. Add human enemy fleets in battle.
5. Add the incident starter pool, Adventure mode and the Forecast tool and workspace.
6. Deliver the deferred D4 "fewer random encounters" research as a director modifier.

Acceptance: the same seed produces the same director log. Forecast reports stay within profile targets for the shipped profiles. A pirate fleet built from chassis and loadouts fights correctly. "Rich targets" demonstrably shifts the pirate unit mix in Forecast. Adventure escalation unlocks its global effects.

### P8 - Depth and the base library (L, ongoing)

1. Rebuild the Leviathan campaign: Act I polish, the Act II Protocol skeleton and the branch structure from the story specification.
2. Add Homeward mode, fleet captains as actors with traits and loyalty, and social incidents.
3. Add the Captain's Log and Log page.
4. Calibrate with the Battle Bench.
5. Grow the library to these targets: 40 incidents, 12 secondary arcs with job pools, 25 site archetypes, 7 factions, 6 fronts and 300 grammar entries.

### P9 - Packaging and Workshop (M)

1. Add `WorkshopService`, local install, export and import, read-only sources with editable copies, and run freezing in the run browser.
2. Add the GodotSteam integration, publishing workspace, tags, previews and the legal-agreement flow.

Acceptance: a pack published from one account installs on another, is playable and survives an update during a run.

### Milestones

| Milestone | After | Proof |
| --- | --- | --- |
| M1 Data-driven slice | P2 | The current game runs entirely from packs; a patch-only pack changes balance |
| M2 Story-engine slice | P4 | Act I runs on quests, scenes and rules |
| M3 Authoring slice | P5 | A new quest is built and played from the in-game editor |
| M4 Procedural slice | P7 | Generated galaxy, cast Leviathan Act I, director incidents, one randomized side arc, a front and Adventure mode |
| M5 Community slice | P9 | A scenario is published and played through the Workshop |

## 21. Testing strategy

- **New focused suites:** `test_expr`, `test_packs` (inheritance, patches, Problems), `test_run_transaction`, `test_hooks_effects`, `test_quests`, `test_casting`, `test_scenes_text`, `test_galaxy_gen` (invariants on fixed seeds), `test_director` (determinism and windows), `test_encounter_composer` and native editor interaction suites.
- **Golden seeds:** each preset has three fixed seeds whose generation summaries are stored as fixtures. Intentional generator changes update the fixtures in the same commit.
- **Content lint:** `tools/validate_packs.gd` must report zero errors for shipped packs before commit.
- Existing workflow rules still apply: isolated APPDATA, focused runs only, completion summaries required and broad runs only on request.

## 22. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Scope is very large | Phases stay playable and delete replaced code; milestones gate expansion |
| GDScript performance for formulas and casting | Compile once to closures, evaluate per day instead of per frame, cast only top candidates and profile in P4/P6 |
| Deep-copy transactions get slow | Measure in P3; add copy-on-write sections only if needed |
| Determinism drift | Stable hash, named streams, saved generation and determinism tests |
| Editor is cramped at the game's resolution | The editor switches to native resolution |
| Procedural stories feel generic | Callback casting, fronts, chronicle text, response lines and designer pins on key milestones |
| Workshop extension lags Godot 4.7 | Keep the `WorkshopService` abstraction; local packs work first |
| Content volume is the real bottleneck | P8 library targets; the editor and VS Code schemas make content cheap to write |

## 23. Decisions needed before P1

1. **Travel model:** keep continuous free flight with fuel range (recommended) or move to lanes.
2. **Time model:** time passes only during travel and explicit waits (recommended) or also while docked.
3. **Formula syntax:** use string formulas as above (recommended) or verbose structured JSON conditions.
4. **Human enemy fleets** use player chassis and loadouts (recommended).
5. **Phase order:** build the editor before procedural generation (recommended) or generate the galaxy first.
