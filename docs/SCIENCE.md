# Daily research production

RP after travel = (living deployed labs + 0.5) * planned travel days. Each lab produces 1 RP/day; zero labs still produce 0.5 RP/day. Every living lab counts, including multiple labs on one hull. Reserves and destroyed labs/hosts do not contribute at departure. Physical lab ranks remain defined, but the current production formula counts labs rather than multiplying by rank or legacy support bonuses.

Adjacent route time is 2-4 in-game days, determined by forward steps and lateral route length; longer forward journeys scale proportionally. This duration is separate from map animation and elapsed battle time. Departure freezes duration and lab membership. Completed combat/quiet journeys settle once, fund the chosen project and retain overflow. Waiting, retries, failed approaches, pickups and repeated arrivals produce nothing. Half-points survive project switches, completion, transaction replay and save/reload.

Science snapshots v2 record all living deployed labs. Historical rank/adjacency fields remain for compatibility/forgery validation; total_rp is legacy metadata, not the new production rate. Version 1 highest-lab snapshots still validate against their original physical deployments. Missing lab snapshots, altered physical rank/HP/adjacency and invalid journey days are rejected.

Combat analysis remains separate: the highest operational lab on a hull marks a visible hostile and grants its existing bounded combat bonus. Research timing never depends on this combat timer. Crew does not change daily RP.

Verification: tests/test_science.gd, test_research_focus.gd and test_research_ui.gd cover daily/baseline rates, multiple labs per hull, legacy snapshots, fractional RP, departure freezes, waiting/withdrawal, failed writes, completion/overflow, arrival deduplication and native UI/input. Current logs/captures: .local/research-tree/.
