# slxgen

Python library for generating Stateflow charts from YAML specifications, and
for inspecting existing Simulink/Stateflow models. Both directions are
supported: YAML → `.slx` (generation) and `.slx` → text / JSON / PNG (inspection).

---

## Quick start

```python
from slxgen import run_pipeline

run_pipeline(
    'my_chart.yaml',
    model_name='MyCtrl',
    run_matlab=True,   # False = write .m script only, no MATLAB needed
)
```

See [`example/model_gen/quick_start.py`](example/model_gen/quick_start.py) for
a working example with all options.

**Environment:** activate the `py311_slxgen` conda environment for
`matlab.engine` support (MATLAB build + sfLint steps).

**Recommended one-time MATLAB setup** for fast iteration:

```matlab
% In the MATLAB Command Window — do this once:
matlab.engine.shareEngine('slxgen')
```

After that every `run_pipeline(..., run_matlab=True)` call connects in <1 s
instead of starting a cold engine.

---

## Documentation map

| Document | Purpose | Open it when… |
| -------- | ------- | -------------- |
| [`docs/workflow.md`](docs/workflow.md) | Edit-validate-generate loop, MATLAB session setup, tool commands | Starting a new model or iterating on an existing one |
| [`docs/architecture.md`](docs/architecture.md) | Pipeline layers, two tool modes, all entry points | Understanding how the code is organised |
| [`docs/algorithms.md`](docs/algorithms.md) | Step-by-step pipeline walkthrough with copy-paste code snippets | Debugging or modifying generation internals |
| [`docs/issues.md`](docs/issues.md) | Known bugs with status, workarounds, and fix options | You hit something unexpected — or want to file a new issue |
| [`docs/roadmap.md`](docs/roadmap.md) | Planned features and priorities | Deciding what to work on next |
| [`docs/stateflow_model_creation_guideline.md`](docs/stateflow_model_creation_guideline.md) | Design rules for Level 0–3 models (naming, hierarchy, actions) | Writing or reviewing YAML specs |
| [`docs/slxgen_internals.md`](docs/slxgen_internals.md) | ELK layout, coordinate rules, subchart math | Deep-diving into layout behaviour |
| [`docs/sir_notes.md`](docs/sir_notes.md) | SIR design rationale, schema reference, phase roadmap | Understanding or extending the intermediate representation |
| [`example/model_gen/quick_start.py`](example/model_gen/quick_start.py) | Minimal pipeline example (15 lines) | First run |
| [`example/model_gen/gen_Ex1.py`](example/model_gen/gen_Ex1.py) | Full explicit pipeline — all 4 steps visible | Reference or customisation |
