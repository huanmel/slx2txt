# slxgen — Known Issues

Issues are registered here with status tracking. For planned improvements see
[`docs/roadmap.md`](roadmap.md). For layout algorithm background see
[`docs/algorithms.md`](algorithms.md).

---

## Template

```
## ISS-NNN: Title
**Status:** `open` | `mitigated` | `fixed`
**Severity:** `blocker` | `major` | `minor` | `cosmetic`
**Component:** file or layer affected
**Description:** What goes wrong.
**Reproduction:** Minimal YAML or steps to trigger.
**Root cause:** Why it happens.
**Workaround:** What you can do today.
**Fix:** What needs to change. Link to roadmap item if tracked.
```

---

## ISS-001: Default-transition dot overlaps the state above

**Status:** `fixed`  
**Severity:** `cosmetic`  
**Component:** `stateflow.py`, `elk_layout.py`

**Description:** The default-transition filled dot was rendered on top of the
bottom border of the state immediately above the default child. Additionally,
no `SourceEndPoint` or `MidPoint` was set, so Stateflow auto-placed the dot at
the canvas top-left and routed a long curved arrow to the destination.

**Root cause:** Dot was placed at `dot_y = y_destination - 20`, and ELK placed
siblings with a 20 px gap, so the state above ended exactly at `dot_y`. Without
`SourceEndPoint`/`MidPoint`, Stateflow used its own auto-routing heuristic.

**Fix applied:**

- `stateflow.py:_emit_sf_default_transition` now emits `SourceEndPoint` (20 px
  above destination top, centred horizontally) and `MidPoint` (midpoint of the
  straight vertical line), forcing a clean short arrow.
- `elk_layout.py`: `_NODE_SPACING = 30` (was 20) and `_DEFAULT_TRANS_OFFSET = 20`
  are now named constants — single place to tune chart appearance.
  Gap = 30 px, offset = 20 px → 10 px clearance above and below the dot.

**Note (Option B — deferred):** A more robust fix would compute the midpoint
of the actual gap from sibling positions, making the dot placement independent
of `_NODE_SPACING`. Documented in [`docs/layout_default_transition.md`](layout_default_transition.md).

---

## ISS-002: Default (init) state not placed first at root level

**Status:** `open`  
**Severity:** `minor`  
**Component:** `elk_layout.py` — `sf_to_elk_json`, root-level layout pass

**Description:** The state with `default: true` at the chart root is not
guaranteed to render at the top. In the HVAC chart, OFF (default) renders at
the bottom while SEMI_OFF and ON are above it.

**Root cause:** `elk.layered.layerConstraint = FIRST` is applied to default
children inside compound-node builds but is silently ignored by ELK for
compound root nodes when `elk.hierarchyHandling = SEPARATE_CHILDREN` is used.
ELK's cycle-breaker (`GREEDY_MODEL_ORDER`) then sees ON→OFF and SEMI_OFF→OFF
as forward edges and places OFF as a sink at the bottom.

**Workaround:** Use `role: init` explicitly — this adds a FIRST constraint
inside the compound build. For root-level states this still may not work.
Alternatively post-process positions to sort by `initial`.

**Fix — approaches to investigate:**

- Add a virtual priority edge from a dummy source node to the init state,
  forcing ELK to treat it as a source.
- Change `elk.layered.cycleBreaking.strategy` from `GREEDY_MODEL_ORDER` to
  `DEPTH_FIRST` or `INTERACTIVE`.
- Sort `root_children` by `default: true` first so `GREEDY_MODEL_ORDER`
  assigns it model-order 0 and reverses all back-edges pointing to it.
- Two-pass: fix init state at `y = container_top + padding` after first ELK
  pass, then re-run edge routing only.

See [`docs/layout_default_transition.md`](layout_default_transition.md) for full analysis.

---

## ISS-003: Long transition labels overflow the container box

**Status:** `open` (accepted limitation)  
**Severity:** `minor`  
**Component:** `stateflow.py` — transition label placement

**Description:** Stateflow center-anchors transition labels at `MidPoint`.
When a condition expression is long (e.g. 7 inputs ORed), the label extends
beyond the state bounding box in both directions. No truncation occurs in the
generated chart.

**Reproduction:** Any transition with a long `condition:` string, e.g.:
```yaml
condition: "blowerSpdReq > 0 || auto_press || defrost_press || dist_request
            || recirc_press || ac_press"
```

**Root cause:** Stateflow has no label width cap. The `MidPoint` determines
where the label anchor is, but does not clip the rendered text.

**Workaround:** Keep conditions short. For complex guards, factor into a named
predicate or local boolean computed in a `du:` action.

**Fix:** No fix possible at the generation layer without truncating labels.
The layout linter (`elk_validate()` — roadmap Priority 5) can detect and warn
about labels that exceed a width threshold. See [`docs/roadmap.md`](roadmap.md).

---

## ISS-004: Back-edge transition arcs cut through sibling states

**Status:** `open` (accepted limitation)  
**Severity:** `minor`  
**Component:** `elk_layout.py` — edge routing

**Description:** ELK routes edges through the shortest path between nodes,
which may cross through sibling state boxes. Back-edges (cycles returning to
an earlier state) are particularly affected. Human-drawn charts route these
arcs around the outside via side junctions.

**Reproduction:** Any chart with a cycle, e.g. ON → OFF → ON.

**Root cause:** ELK's SPLINES routing can cross node boxes when the edge
topology creates a short path through them. Generating explicit junction nodes
as waypoints would force the arc around the outside, but junctions are not
currently emitted for non-decision routing.

**Workaround:** Accept the layout and manually adjust in the Stateflow editor
after generation.

**Fix:** Detect back-edges (cycle-breaking edges in the ELK graph) and
generate a routing junction at the chart boundary. High effort — deferred.
See roadmap Priority 5 (layout engine improvements).

---

## ISS-005: Variables with no `type:` field silently accepted

**Status:** `open`  
**Severity:** `minor`  
**Component:** `stateflow_sir.py` — `yaml_to_sir()`

**Description:** A variable declared without a `type:` key (e.g.
`{name: recirc_request}`) is accepted by the parser without error or warning.
At MATLAB codegen time the variable cannot be typed and may produce an
incorrectly formed data declaration.

**Reproduction:**
```yaml
outputs:
  - {name: recirc_request}   # no type field
```

**Root cause:** `yaml_to_sir()` does not require `type:` on variables. The
YAML parser silently produces `None` for the missing key.

**Workaround:** Always specify `type:`. For enum types defined in an SLDD,
use the enum type name as a string (e.g. `type: Recirc_e`).

**Fix:** Add a validator check (WARNING or ERROR) for variables missing `type:`.
Update the schema summary in `docs/workflow.md` to mark `type:` as required.

---

## ISS-006: sfLintChart incorrectly reports MultipleDefaultTrans for non-subchart compounds

**Status:** `fixed`  
**Severity:** `blocker`  
**Component:** `slxgen/matlab/sfLintChart.m`, `slxgen/matlab/slx_lint.m`

**Description:** `sfLintChart` reported `MultipleDefaultTrans` on charts with a
compound state (e.g. OFF containing OFF_IDLE and OFF_WAKE_PENDING) even when
exactly one default transition existed at each level.

**Reproduction:** Any chart with a non-subchart compound state that has a default
child and an inner default transition. Example: HVAC chart, OFF compound.

**Root cause (two bugs):**

1. `sfLintChart.m` used `transition.Path` to determine which container a
   transition belongs to. In Stateflow, **all non-subchart transitions are stored
   at chart level** regardless of the `Stateflow.Transition(parentState)` argument,
   so every transition had `Path = "Model/Chart"`. The checker conflated the inner
   default (OFF → OFF_IDLE) with the chart-level default (chart → OFF), counting
   two chart-level defaults.
2. `buildContainers` checked `any(strcmp(allPaths, s.Path))` where `s.Path` is the
   *parent's* path, not the state's own path — compound states were mis-identified.

**Fix applied:**

- Complete rewrite of `sfLintChart.m`: containment now determined from
  `t.Destination.Path == containerFullPath(c)` (not `t.Path`). `buildContainers`
  uses `[s.Path '/' s.Name]` as the state's own full path. `containerFullPath(c)`
  helper distinguishes Chart vs State path semantics.
- `slx_lint.m` updated to report `[h.Path '/' h.Name]` for State handles so the
  JSON output includes the full path.

---

## ISS-007: State.Position must be chart-absolute for non-subchart compound children

**Status:** `fixed`  
**Severity:** `blocker`  
**Component:** `slxgen/stateflow.py` — `_sf_states_to_matlab_lines`

**Description:** States inside a non-subchart compound (e.g. OFF_IDLE inside OFF)
were generated with parent-relative coordinates. Stateflow placed them outside the
parent's bounding box, re-parenting them to the chart level and corrupting the
visual hierarchy.

**Reproduction:** HVAC chart — OFF_IDLE and OFF_WAKE_PENDING appeared at chart
level instead of inside OFF.

**Root cause:** `_sf_states_to_matlab_lines` subtracted the parent offset (`elif
path_prefix` branch) before emitting `State.Position`. In Stateflow, `Position` is
**chart-absolute** for all non-subchart states at every depth — only direct children
of a subchart use subchart-relative coordinates.

**Fix applied:** Removed the `elif path_prefix` branch. Only states that are direct
children of a subchart (where `_subchart_path` is set) use subchart-relative coords;
all others use raw chart-absolute positions from the ELK layout.
