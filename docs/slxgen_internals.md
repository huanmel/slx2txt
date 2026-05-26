# slxgen Internals

**Package:** `slxgen`  
**Target toolchain:** MATLAB / Simulink / Stateflow R2024a

---

- [slxgen Internals](#slxgen-internals)
  - [1. Overview](#1-overview)
  - [2. Processing pipeline](#2-processing-pipeline)
    - [2.1 ELK layout (bottom-up)](#21-elk-layout-bottom-up)
    - [2.2 Positions dict](#22-positions-dict)
    - [2.3 Sink-state repositioning (optional)](#23-sink-state-repositioning-optional)
    - [2.4 Edge routing](#24-edge-routing)
    - [2.5 Transition ordering](#25-transition-ordering)
  - [3. State Position coordinate rules](#3-state-position-coordinate-rules)
    - [3.1 The single unified rule](#31-the-single-unified-rule)
    - [3.2 OR decomposition (exclusive states, default)](#32-or-decomposition-exclusive-states-default)
    - [3.3 AND decomposition (PARALLEL\_AND regions)](#33-and-decomposition-parallel_and-regions)
    - [3.4 Concrete example (Ex1\_StMach — STARTUP subchart)](#34-concrete-example-ex1_stmach--startup-subchart)
    - [3.5 Why Stateflow needs subchart-absolute coordinates](#35-why-stateflow-needs-subchart-absolute-coordinates)
    - [3.6 Implementation in stateflow.py](#36-implementation-in-stateflowpy)
  - [4. Sink role system](#4-sink-role-system)
  - [5. Available elk\_options](#5-available-elk_options)
    - [Recommended configurations](#recommended-configurations)
  - [5. Sink-state concept](#5-sink-state-concept)
  - [6. Known limitations (deferred)](#6-known-limitations-deferred)


## 1. Overview

`slxgen` converts a YAML state-machine description into a MATLAB script that builds a Stateflow chart programmatically. It uses **ELK** (Eclipse Layout Kernel) to compute state positions and transition routing before emitting MATLAB. The generated script is self-contained and reproducible.

Pipeline entry point: `sf_yaml_to_matlab(yaml_path, output_path, elk_options)`.

---

## 2. Processing pipeline

```text
YAML file
  └─► yaml_to_sir()              stateflow_sir.py   — parse + validate to SIR
  └─► sir_to_chart_dict()        stateflow_sir.py   — flatten to chart dict
  └─► elk_layout_bottomup()      elk_layout.py      — bottom-up per-subchart ELK layout
        for each subchart (deepest first):
          └─► sf_to_elk_json()   elk_layout.py      — build ELK graph for subchart
          └─► elk_layout()       elk_layout.py      — run ELK (Node.js subprocess)
          └─► collect positions/edges (subchart-relative)
        chart-root ELK run (subcharts as fixed-size leaves)
        convert subchart-relative → chart-global
  └─► stateflow_dict_to_matlab() stateflow.py       — emit MATLAB .m script
```

### 2.1 ELK layout (bottom-up)

`elk_layout_bottomup()` runs ELK in multiple passes:

1. **Per-subchart pass** (deepest subcharts first): each subchart is laid out independently, with only its own children as ELK nodes. This prevents chart-level topology from distorting subchart internal layout. The resulting bounding box becomes a fixed size for the parent ELK run.
2. **Chart-root pass**: top-level states are laid out with all subcharts treated as fixed-size leaf nodes.
3. **Coordinate merge**: subchart-relative positions are converted to chart-global by adding the subchart's chart-global offset (shallowest subcharts first, so nested subchart offsets chain correctly).

Within each run, states are layered top-to-bottom (DOWN direction by default). Init states go to the first layer; sink states get `layerConstraint=LAST`. ELK uses `GREEDY_MODEL_ORDER` cycle breaking and `LINEAR_SEGMENTS` node placement.

Subchart nodes are treated as **opaque leaf nodes** at the parent level: their footprint in the parent-level ELK run is computed from their own label/actions content (same formula as a leaf state), not from their internal bounding box. This matches how Stateflow renders a collapsed subchart box. The `__subchart_leaf_size__` option can override this with an explicit fixed size when needed.

The `sf_to_elk_json()` function accepts a `fixed_sizes` dict; any state path found there is emitted as a fixed-size ELK leaf regardless of its children. Subchart ELK runs pass `_orig_idx` in each transition dict so edge IDs use the original YAML transition index, matching the IDs stateflow.py looks up.

### 2.2 Positions dict

`elk_to_stateflow_layout()` returns a flat `positions` dict:

```python
positions: dict[str, tuple[int, int, int, int]]
# key: dotted state path  e.g. "ACTIVE.STARTUP.READY.LINK_MON"
# value: (global_x, global_y, width, height)  — all in absolute canvas pixels
```

Coordinates are **global** (accumulated by summing ELK parent offsets during tree traversal). The conversion to Stateflow-relative coordinates happens later in `stateflow.py`.

### 2.3 Sink-state repositioning (optional)

After ELK runs, states with `role: sink` (or names containing `FAULT`/`ERROR`) can be repositioned within their compound parent. ELK places them at the last layer; the right-column convention requires post-processing. Disabled by default — enable with `__sink_placement__: right` (or `left`, `top`, `bottom`, `auto`).

### 2.4 Edge routing

All non-sink transitions use float OClock values derived from ELK's exact boundary attachment point (arc-distance on perimeter, 0–12 clock face). After sink repositioning, transition geometry to sink states is recomputed using final positions, giving accurate OClock 3 → 9 (right-exit, left-entry) horizontal routing.

### 2.5 Transition ordering

ELK's `LINEAR_SEGMENTS` node placement uses edge model order as a tiebreaker for horizontal positioning. To preserve correct layout, transitions are passed to ELK in their **original YAML order**. For MATLAB emission, transitions are sorted by `(from-path, order)` so Stateflow assigns `ExecutionOrder` in the correct sequence. The `tr_idx` (original index) is preserved to match the `EDGE||src||dst||{idx}` IDs that ELK uses.

---

## 3. State Position coordinate rules

Stateflow's `State.Position = [x y w h]` uses different coordinate origins depending on context. Understanding this is essential when generating `.m` scripts programmatically.

### 3.1 The single unified rule

```text
if the state is a descendant of a subchart (IsSubchart=true):
    Position = [global_x - subchart_x,  global_y - subchart_y,  w,  h]

else (state is at chart level, no enclosing subchart):
    Position = [global_x - parent_x,  global_y - parent_y,  w,  h]
```

A subchart defines a **new coordinate origin** for every descendant, regardless of nesting depth or decomposition type. Chart-level states (not inside any subchart) use the direct parent as origin.

### 3.2 OR decomposition (exclusive states, default)

States inside an OR parent that is **not** a subchart use the parent's top-left corner as origin.

```text
ACTIVE  [chart level, no subchart parent]
  STARTUP  subchart — IsSubchart=true
    Position = [global(STARTUP) - global(ACTIVE), ...]  →  parent-relative
  STANDBY  subchart
    Position = [global(STANDBY) - global(ACTIVE), ...]  →  parent-relative

  Inside STARTUP subchart:
    INIT         Position = [global(INIT)         - global(STARTUP), ...]  →  subchart-absolute
    CONNECTING   Position = [global(CONNECTING)   - global(STARTUP), ...]
    FAULT_ACTIVE Position = [global(FAULT_ACTIVE) - global(STARTUP), ...]
```

### 3.3 AND decomposition (PARALLEL_AND regions)

The decomposition type (OR vs AND) does **not** change the coordinate rule. The enclosing subchart — or its absence — is the only factor.

```text
Inside STARTUP subchart:
  READY  [PARALLEL_AND, inside STARTUP subchart]
    Position = [global(READY)    - global(STARTUP), ...]  →  subchart-absolute

  LINK_MON  [child of READY AND, inside STARTUP subchart]
    Position = [global(LINK_MON) - global(STARTUP), ...]  →  STILL subchart-absolute
                                                              NOT READY-relative

  LINK_HEALTHY  [grandchild of READY AND, inside STARTUP subchart]
    Position = [global(LINK_HEALTHY) - global(STARTUP), ...]  →  STILL subchart-absolute
```

`LINK_HEALTHY` is visually nested three levels deep (STARTUP → READY → LINK_MON → LINK_HEALTHY), but its `Position` is measured from STARTUP's origin, not from LINK_MON's.

### 3.4 Concrete example (Ex1_StMach — STARTUP subchart)

| State         | ELK global (x, y) | Origin subtracted | Emitted Position    |
| ------------- | ----------------- | ----------------- | ------------------- |
| STARTUP       | (20, 70)          | ACTIVE (0, 0)     | `[20 70 501 780]`   |
| INIT          | (77, 174)         | STARTUP (20, 70)  | `[57 104 150 80]`   |
| READY         | (50, 374)         | STARTUP (20, 70)  | `[30 304 440 346]`  |
| LINK_MON      | (70, 430)         | STARTUP (20, 70)  | `[50 360 190 270]`  |
| LINK_HEALTHY  | (90, 500)         | STARTUP (20, 70)  | `[70 430 150 80]`   |
| LINK_DEGRADED | (90, 600)         | STARTUP (20, 70)  | `[70 530 150 80]`   |
| DATA_CTRL     | (281, 430)        | STARTUP (20, 70)  | `[261 360 190 270]` |
| FULL_RATE     | (301, 500)        | STARTUP (20, 70)  | `[281 430 150 80]`  |

STARTUP uses ACTIVE as origin (ACTIVE is a chart-level parent, not a subchart) because STARTUP itself *is* the subchart boundary. All states below STARTUP use STARTUP's origin regardless of depth.

### 3.5 Why Stateflow needs subchart-absolute coordinates

Stateflow determines which parent a state belongs to by checking whether the state's `Position` (treated as subchart-absolute) falls inside each candidate parent's bounding box. If `LINK_HEALTHY` were emitted as `[20 70 150 80]` (LINK_MON-relative), Stateflow would evaluate those coordinates against the STARTUP bounding box, find the point (20, 70) outside READY (which occupies [30..470, 304..650] in STARTUP space), and reparent `LINK_HEALTHY` to STARTUP — the wrong level.

### 3.6 Implementation in stateflow.py

`_sf_states_to_matlab_lines` tracks the nearest enclosing subchart path via the `_subchart_path` parameter:

```python
if _subchart_path and _subchart_path in positions:
    px, py = positions[_subchart_path][:2]   # subchart-absolute
elif path_prefix and path_prefix in positions:
    px, py = positions[path_prefix][:2]      # parent-relative (chart level)
else:
    px, py = 0, 0

State.Position = [x - px, y - py, w, h]
```

When recursing into children, `_subchart_path` is updated only when the current state has `subchart: true`; otherwise it is passed down unchanged, so all descendants of a subchart share the same origin.

---

## 4. Sink role system

Any state can be designated a **sink** — a state that collects many incoming transitions from siblings and benefits from right-column placement. Three mechanisms are available, applied in priority order:

1. **Explicit annotation** — set `role: sink` in the YAML state body. The legacy aliases `role: fault` and `role: error` are accepted as synonyms and map to the same `'sink'` canonical role internally.
2. **Keyword detection** — state names containing `FAULT` or `ERROR` are treated as sinks automatically (heuristic fallback, no annotation needed).
3. **Topological auto-detection** — pass `__auto_sink__: N` in `elk_options` to promote any pure-sink state (no outgoing transitions to siblings) with ≥ N incoming transitions to sink role, regardless of name or annotation.

The canonical role string returned by `_state_role()` is always `'sink'` (never `'fault'`). The aliases exist only in the YAML author interface.

```python
# elk_layout.py
_SINK_ROLE_ALIASES = frozenset({'sink', 'fault', 'error'})  # accepted in YAML role: field
_SINK_KEYWORDS     = ('FAULT', 'ERROR')                     # keyword fallback on state name
```

---

## 5. Available elk_options

Pass as `elk_options` dict to `sf_yaml_to_matlab()`:

| Option | Default | Description |
| --- | --- | --- |
| `__sink_bus_junctions__` | `false` | Route sink transitions through a vertical junction bus spine |
| `__orthogonal_junctions__` | `false` | Strict H/V spine routing (requires `sink_bus_junctions=true`) |
| `__direction__` | `DOWN` | ELK layout direction for normal states |
| `__max_label_width__` | `150` | Pixel cap for transition label width estimation |
| `__label_substitution__` | `true` | Replace long labels with short identifiers for ELK sizing |
| `__bare_transitions__` | `false` | Skip all transition geometry — Stateflow auto-routes |
| `__sink_placement__` | `none` | Where to place sink states after ELK: `right`, `left`, `top`, `bottom`, `auto`, or `none` |
| `__auto_sink__` | off | Integer N >= 1: auto-promote pure-sink states with >= N incoming sibling transitions |
| `__subchart_leaf_size__` | off | `WxH` (e.g. `200x150`) or `true` (= `200x150`) → override the subchart footprint used in the parent-level ELK run with a fixed size. Rarely needed: the default already uses label-content sizing (leaf footprint). |

### Recommended configurations

**Default — pure ELK arc routing:**

```python
sf_yaml_to_matlab(yaml_path, elk_options={})
```

Produces curved arcs with precise float OClock entry/exit points derived from ELK boundary coordinates. No post-processing. Suitable for all charts.

**Optional — sink right-column repositioning:**

```python
sf_yaml_to_matlab(yaml_path, elk_options={'__sink_placement__': 'right'})
```

States with `role: fault` (or names containing `FAULT`/`ERROR`) are moved to a right column within their parent after ELK runs. Useful when fault states collect many incoming transitions.

**Experimental — fault-bus junction spine:**

```python
sf_yaml_to_matlab(yaml_path, elk_options={
    '__sink_bus_junctions__': 'true',
    '__orthogonal_junctions__': 'true',
})
```

Produces a vertical junction spine to the left of each sink state. Known issue: source states positioned below the gateway junction produce an upward fan arc instead of a straight horizontal. Deferred.

---

## 5. Sink-state concept

The "sink state" concept is topological, not semantic: any state that collects many incoming transitions from sibling states benefits from right-column placement. The `role: fault` YAML annotation is the declaration mechanism, but the concept generalises to any exception or consolidation state.

---

## 6. Known limitations (deferred)

- **State box sizing** is estimated from character counts; multi-line action text can produce slightly undersized boxes. Manual `width`/`height` overrides in the YAML are the workaround.
- **Transition label placement** uses a fixed left-margin offset (`_ELK_LABEL_MID_X`) for ELK-routed transitions; this prevents overflow but may cause overlap in dense charts.
- **Junction bus below-gateway edge case**: when a source state is positioned below the gateway junction, the fan connector creates an upward arc instead of a straight horizontal. Functional but not perfectly orthogonal.
