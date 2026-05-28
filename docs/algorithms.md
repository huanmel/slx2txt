# slxgen — Pipeline Algorithm Reference

Step-by-step walkthrough of the generation pipeline with code-level detail.
Use this as a developer reference and for extracting copy-paste snippets.

For the high-level view see [`docs/architecture.md`](architecture.md).  
For known issues in specific steps see [`docs/issues.md`](issues.md).

---

- [slxgen — Pipeline Algorithm Reference](#slxgen--pipeline-algorithm-reference)
  - [Step 1 — Parse YAML → SIR](#step-1--parse-yaml--sir)
  - [Step 2 — Estimate leaf state sizes](#step-2--estimate-leaf-state-sizes)
  - [Step 3 — Build ELK graph JSON](#step-3--build-elk-graph-json)
  - [Step 4 — Run ELK layout](#step-4--run-elk-layout)
  - [Step 5 — Extract chart-absolute positions](#step-5--extract-chart-absolute-positions)
  - [Step 6 — Emit MATLAB code](#step-6--emit-matlab-code)

---

## Step 1 — Parse YAML → SIR

**Files:** `stateflow_sir.py`

```text
hvac_state.yaml
    → yaml.safe_load()
    → yaml_to_sir()        # normalize: nested dict → flat SIRModel
    → sir_validate()       # structural checks (errors abort, warnings continue)
    → SIRModel             # flat lists: sir.states, sir.transitions, sir.variables
    → sir_to_chart_dict()  # SIR → nested dict for codegen
```

The SIR dict structure (after `sir_to_chart_dict()`):

```python
{
    'name': 'HVAC_State',
    'states': {
        'OFF': {
            'default': True,
            'states': {
                'OFF_IDLE': {'default': True, 'en': '...'},
                'OFF_WAKE_PENDING': {'en': '...'},
            }
        },
        'SEMI_OFF': {'en': '...'},
        'ON': {'en': '...'},
    },
    'transitions': [
        {'from': 'OFF.OFF_IDLE', 'to': 'OFF.OFF_WAKE_PENDING',
         'condition': '...', 'order': '1'},
        ...
    ],
    'inputs': [...],
    'outputs': [...],
}
```

Key `SIRModel` properties:

- `sir.states` — flat list of `SIRState`, parent-before-child order
- `sir.transitions` — flat list of `SIRTransition`; `priority` is int (1 = highest)
- `sir.variables` — inputs + outputs + locals, each tagged with `.scope`

State IDs are fully-qualified dotted paths: `'OFF'`, `'OFF.OFF_IDLE'`,
`'ACTIVE.STARTUP.CONNECTING'`.

---

## Step 2 — Estimate leaf state sizes

**File:** `stateflow.py:_sf_state_size`

For each **leaf** state (no children), compute pixel dimensions before ELK
runs so that compound (parent) states can be accurately sized:

```python
label_lines = (
    1                        # state name
    + sum(
        1 + len(action.splitlines())   # "en:" keyword + action lines
        for action in [en, du, ex] if action
    )
)
height = _SF_HEADER_H + label_lines * _SF_LINE_H
width  = _SF_LEAF_W
```

Constants:

| Name | Value | Purpose |
| ---- | ----- | ------- |
| `_SF_LEAF_W` | 150 px | minimum leaf node width |
| `_SF_PX_PER_CHAR` | 7.5 px | char → px for adaptive width |
| `_SF_HEADER_H` | 22 px | title-bar overhead |
| `_SF_LINE_H` | 16 px | pixels per label line |

When `adaptive_leaf_width=True`, width is estimated from the longest label line:
`max(_SF_LEAF_W, longest_chars × _SF_PX_PER_CHAR + 20 px)`.

These sizes feed ELK so compound nodes are sized to fit their children.

---

## Step 3 — Build ELK graph JSON

**File:** `elk_layout.py:sf_to_elk_json`

`build_node(name, body, path_prefix)` recurses through the SIR state tree:

**Leaf node** — fixed size from Step 2:

```json
{ "id": "OFF.OFF_IDLE", "width": 150, "height": 80 }
```

**Compound node** — ELK computes size from children. Padding accounts for the
header text and a space for the default-transition dot:

```python
top_pad = _compound_header_h(body)      # name + en/du/ex lines × 16 px
if top_pad <= _COMPOUND_HEADER_MIN_H:   # 30 px minimum
    top_pad += _DEFAULT_TRANSITION_PAD  # +40 px for default-dot room
elk_node['layoutOptions']['elk.padding'] = (
    f'[top={top_pad}, right=20, bottom=20, left=20]'
)
```

**Layer constraints** applied to child nodes:

```python
# Initial (default) child → placed first (top of layer)
child['layoutOptions']['elk.layered.layerConstraint'] = 'FIRST'

# Sink / fault state → placed last, right column
child['layoutOptions']['elk.layered.layerConstraint'] = 'LAST'
child['layoutOptions']['elk.partitioning.partition'] = '1'
```

**Edges** — only non-default transitions become ELK edges. Default transitions
have no source state and are handled separately in Step 6:

```python
edge_id = f'EDGE||{src_path}||{dst_path}||{idx}'
edges.append({'id': edge_id, 'sources': [src_path], 'targets': [dst_path]})
```

---

## Step 4 — Run ELK layout

**File:** `elk_layout.py:run_elk`

Calls ELK Layered via a Node.js subprocess (`elk_runner.js`) with these
options applied at every level:

| Option | Value | Effect |
| ------ | ----- | ------ |
| `elk.algorithm` | `layered` | hierarchical layered layout |
| `elk.direction` | `DOWN` | vertical main axis (default) |
| `elk.layered.nodePlacement.strategy` | `LINEAR_SEGMENTS` | stable column alignment |
| `elk.edgeRouting` | `SPLINES` | curved transition arrows |
| `elk.spacing.nodeNode` | `20` | 20 px gap between sibling states |
| `elk.layered.spacing.nodeNodeBetweenLayers` | `20` | 20 px gap between layers |
| `elk.hierarchyHandling` | `SEPARATE_CHILDREN` | each compound laid out independently |

**Bottom-up multi-pass strategy** (`elk_layout_bottomup()`):

```text
1. Per-compound pass (deepest first, all states with children):
     each compound (subchart OR non-subchart) laid out independently
     resulting bounding box → fixed size for parent run
     subcharts: bounding box = collapsed label size (Stateflow convention)
     non-subchart compounds: bounding box = actual ELK-computed size

2. Chart-root pass:
     top-level states laid out with ALL compounds as fixed-size leaves
     cycle-breaking: DEPTH_FIRST (DFS from init state → init placed at top)
     cross-compound edge endpoints promoted to compound boundary

3. Edge routing offset (non-subchart compounds only):
     per-compound ELK gives compound-relative MidPoints
     offset by compound's chart-absolute position → chart-absolute

4. Coordinate merge (shallowest first):
     compound-relative positions → chart-global
     nested offsets chain correctly because parent is resolved first
```

**Why DEPTH_FIRST for the root pass:**
With `GREEDY_MODEL_ORDER`, the init/default compound state could still end up at
the bottom due to its participation in cycles. `DEPTH_FIRST` starts the DFS from
the first node in model order (the init state, listed first in the YAML) and
reverses back-edges from its descendants, making it a source in the layered DAG.

ELK output per node: `x`, `y`, `width`, `height` (relative to parent).  
ELK output per edge: `sections[0].startPoint`, `endPoint`, `bendPoints`.

---

## Step 5 — Extract chart-absolute positions

**File:** `elk_layout.py:elk_to_stateflow_layout`

Recursively accumulate parent offsets to get chart-absolute coordinates:

```python
def collect_positions(node, offset_x, offset_y):
    x = offset_x + node['x']
    y = offset_y + node['y']
    w, h = node['width'], node['height']
    positions[node['id']] = (int(x), int(y), int(w), int(h))
    for child in node.get('children', []):
        collect_positions(child, x, y)   # pass accumulated offset down

collect_positions(elk_result, 0, 0)
```

Result: `positions` dict.

```python
# key  = SIR dotted path
# value = (x, y, w, h) in chart-absolute pixels
positions = {
    'OFF':              (20, 216, 190, 180),
    'OFF.OFF_IDLE':     (40, 256, 150,  80),
    'OFF.OFF_WAKE_PENDING': (40, 356, 150, 80),
    'SEMI_OFF':         (20, 12,  150,  80),
    'ON':               (20, 112, 150,  84),
}
```

Edge routing is also extracted from `sections[0]`:

```python
mid_x      = section['startPoint']['x'] + (bendpoints or end) / 2
mid_y      = ...
src_oclock = angle_to_oclock(startPoint relative to source state)
dst_oclock = angle_to_oclock(endPoint relative to destination state)
```

---

## Step 6 — Emit MATLAB code

**File:** `stateflow.py:_sf_states_to_matlab_lines`

DFS walk of the state tree. For each state:

**1. Create state and set position:**

```python
# Non-subchart states at any depth: chart-absolute coords
lines.append(f"{var} = Stateflow.State(ch);")
lines.append(f"{var}.Position = [{x} {y} {w} {h}];")
lines.append(f"{var}.LabelString = '{label}';")

# Direct children of a subchart: subchart-relative
lines.append(f"{var}.Position = [{x - sc_x} {y - sc_y} {w} {h}];")
```

**2. If default child, emit default transition:**

```python
dot_x = x + w // 2          # centre of destination state (x, chart-absolute)
dot_y = max(y - 20, 0)      # 20 px above destination top  ← ISS-001
mid_y = (dot_y + y) // 2

lines += [
    f"t_{n} = Stateflow.Transition(ch);",
    f"t_{n}.Destination = {var};",
    f"t_{n}.DestinationOClock = 0;",          # enters at top-centre
    f"t_{n}.SourceEndPoint = [{dot_x} {dot_y}];",
    f"t_{n}.MidPoint = [{dot_x} {mid_y}];",  # straight vertical arrow
]
```

See [ISS-001](issues.md#iss-001-default-transition-dot-overlaps-the-state-above)
for the overlap bug and proposed fix.

**3. Regular transitions:**

```python
lines += [
    f"t_{n} = Stateflow.Transition(ch);",
    f"t_{n}.Source = {src_var};",
    f"t_{n}.Destination = {dst_var};",
    f"t_{n}.LabelString = '{label}';",
    f"t_{n}.MidPoint = [{mid_x} {mid_y}];",
    f"t_{n}.SourceOClock = {src_oclock};",
    f"t_{n}.DestinationOClock = {dst_oclock};",
]
# Labeled transitions: override MidPoint.x near the left margin
if label:
    lines.append(f"t_{n}.MidPoint = [10 {mid_y}];")
```

**Transition label format** (`LabelString`):

```text
[condition]{conditionAction}/transitionAction
```

Examples:

```matlab
% Condition only
t_1.LabelString = '[blower_PB]';

% Condition + transition action
t_2.LabelString = '[count(~linkOk)>tout]{dev_fault=FAULT_LINK;}/';

% No condition, transition action only
t_3.LabelString = '/output=1;';
```

**State label format** (`LabelString`):

```matlab
% Name + entry action
s_1.LabelString = sprintf('OFF_IDLE\nentry:\nhvac_pwr_state = HvacPwr_e.OFF;');

% Name + entry + during + exit
s_2.LabelString = sprintf('ACTIVE\nentry:\ninit();\nduring:\ntick();\nexit:\nclean();');
```
