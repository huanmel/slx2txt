# Stateflow Design Guidelines

**Target Toolchain:** MATLAB / Simulink / Stateflow R2024a  
**Compliance Frameworks:** ISO 26262-6, MAAB V5.0

---

## 0. Purpose

This document defines guidelines for designing Stateflow state machines that are:

- consistent and readable
- maintainable over a long lifecycle
- suitable for testing and debugging
- traceable to requirements
- optionally compatible with formal verification
- suitable for automation (generation from text, LLM, or DSL)

> One modeling style is not enough — choose a **design level**, but keep a **common structural backbone**.

---

## 1. Design Philosophy

### 1.1 State machines are not logic containers

A state machine should represent system **modes**, not detailed algorithmic behavior or procedural sequences.  
If logic dominates structure, the model is incorrect.

### 1.2 Explicitness over cleverness

Prefer explicit states, explicit transitions, and explicit predicates.  
Avoid hidden logic in transitions, implicit dependencies, and overloaded conditions.

### 1.3 Separation of concerns

Split the model into:

- **FSM** — control logic and modes
- **Predicate layer** — conditions
- **Time layer** — timing logic
- **Data layer** — signals and state variables

---

## 2. Modeling Levels

Choose intentionally based on project needs.

### Level 0 — Rapid / readable model

For prototypes, internal tools, and non-critical systems.  
Characteristics: moderate use of temporal operators, simple hierarchy, minimal abstraction.

### Level 1 — Industrial / maintainable model (recommended default)

For production control systems and team development.  
Rules: predicates for complex conditions, limited transition actions, structured timers, shallow hierarchy.

### Level 2 — Verification-ready model

For safety-critical systems requiring formal analysis.  
Rules: no side effects in transitions, explicit state encoding, bounded variables, minimal AND decomposition, no ambiguous guards.

### Level 3 — Automation-ready model (LLM / DSL generation)

For machine-generated or model-transformed FSMs.  
Rules: strict JSON/YAML-compatible structure, no hidden state, standardized predicates, explicit timers, minimal free-form logic.

---

## 3. State Design Rules

### 3.1 States must represent stable modes

A state must be observable in system behavior, stable over time, and semantically meaningful.

| Bad                  | Good      |
| -------------------- | --------- |
| `check_sensor`       | `IDLE`    |
| `increment_counter`  | `RUNNING` |
| `wait_5ms`           | `FAULT`   |

### 3.2 Avoid micro-states

Do not encode algorithm steps, short computations, or temporary conditions as states.

### 3.3 State naming

Use UPPER_CASE for modes. Examples: `IDLE`, `ACTIVE`, `FAULT_RECOVERY`.

### 3.4 State syntax and formatting

Every state label must use explicit action prefixes on their own lines:

```matlab
entry:
  variable = value;
during:
  output = compute();
exit:
  cleanup();
```

Use 2 spaces of indentation per nesting level. Append an explicit semicolon `;` to every data assignment.

---

## 4. Transition Design Rules

### 4.1 Transitions must be deterministic

Each transition must have a clear condition, be mutually exclusive with others, and avoid overlap.

### 4.2 No side effects in transitions (recommended)

Avoid resetting variables, triggering actions, or modifying system state inside transition labels.  
Prefer entry/exit actions in states instead.

### 4.3 Transition conditions must be simple

Preferred forms: boolean flags, predicates, simple comparisons.  
Avoid complex multi-line expressions or embedded algorithmic logic.

### 4.4 Predicate abstraction rule

If a condition exceeds a complexity threshold, move it into a named predicate:

```text
isSafeEntry
isSystemStable
isFaultResolved
```

### 4.5 Operator rules

Do **not** use `count()` to track how long a boolean condition has been true — this is not a valid temporal operator for that purpose.  
Use `duration()` instead:

```matlab
[duration(devStatus ~= DevStatus_e.STANDBY) > startupTout]
{dev_fault = DevFault_e.FAULT_STANDBY_TOUT;}
```

### 4.6 Condition actions vs. transition actions

Condition actions execute immediately when the condition is true and are safe at junctions.  
Transition actions execute only when the destination is confirmed; do not use them before a junction.

Syntax summary:

| Form               | Syntax                   |
| ------------------ | ------------------------ |
| Condition action   | `[condition]{action;}`   |
| Transition action  | `[condition]/action;`    |

Never combine both forms on the same transition segment (`[condition]/{ action }` is invalid).

### 4.7 Junction topology and syntax mapping

| Topology                          | Allowed                                   | Prohibited                    | Reason                                                         |
| --------------------------------- | ----------------------------------------- | ----------------------------- | -------------------------------------------------------------- |
| State → Junction                  | Condition action: `[cond]{action;}`       | Transition action: `/action`  | Prevents backtracking side effects if downstream branches fail |
| Junction → State (final segment)  | Both forms allowed                        | —                             | Destination is finalized; no backtracking risk                 |
| Direct State → State              | Both forms allowed                        | —                             | No alternative routing branches exist                          |

### 4.8 Default transitions

Every exclusive (OR) state container must have a default transition. It must point directly to the initial active state, not to a junction.

---

## 5. State Actions Rules

| Action      | Use for                                         |
| ----------- | ----------------------------------------------- |
| `entry:`    | initialization, reset logic, activation setup   |
| `during:`   | continuous control logic, monitoring, updates   |
| `exit:`     | cleanup, finalization, logging                  |

Do not compute transitions inside actions or modify unrelated subsystem state.

---

## 6. Temporal Logic and Timer Rules

Stateflow supports: `after()`, `duration()`, `count()`.

### 6.1 When to use temporal operators

Use when logic is local to a state, timing is short-term, and behavior is not safety-critical alone.

### 6.2 When NOT to use temporal operators

Avoid when timing is part of a safety decision, must be observable externally, or is reused across states.

### 6.3 Timer style selection

| Use case              | Preferred style                              |
| --------------------- | -------------------------------------------- |
| Local FSM logic       | Stateflow native (`after()`, `duration()`)   |
| Safety / diagnostics  | Explicit variable timer (`timer += dt`)      |
| Formal verification   | Explicit variable timer                      |
| Automation pipelines  | Explicit variable timer                      |

Critical timing logic should optionally be duplicated as an explicit signal for observability.

---

## 7. Hierarchy Rules

- Keep hierarchy shallow: maximum 2–3 levels.
- If a substate requires high complexity, refactor it into a separate atomic subchart.
- OR decomposition is the default (mutually exclusive modes).
- AND decomposition is restricted: use only when subsystems are truly independent, and avoid coupling orthogonal regions.

---

## 8. History Junction Rules

Use history junctions only when a requirement explicitly demands resume behavior.

Avoid them when:

- behavior must be deterministic and analyzable
- system is safety-critical
- the junction would be placed inside a parallel (AND) state

---

## 9. Data Handling Rules

### 9.1 No implicit state

All memory must be explicit via states, variables, timers, or controlled history use.

### 9.2 Bound all variables

Saturate counters, avoid unbounded growth, and avoid unconstrained floats in FSM logic.

### 9.3 Strong data typing

Explicitly assign a rigid data type (`boolean`, `single`, `int32`, etc.) to all data objects.  
Never allow implicit type inheritance from a Simulink bus.

### 9.4 No event broadcasting

Do not use directed event broadcasting (`send`). Cross-state interactions must use data-driven flags.

### 9.5 Parallel state execution order

Parallel (AND) states must have their `ExecutionOrder` property manually sequenced (1, 2, 3…). Do not allow implicit ordering.

---

## 10. Layout and Geometry

- **Grid:** use a 40 px base grid.
- **Flow direction:** left-to-right or top-to-bottom consistently.
- **Spacing:** minimum 80 px horizontal, 60 px vertical between objects.
- **State size:** minimum 160 × 80 px; scale width to fit the longest text line plus 20 px padding.
- **Junction alignment:** junctions forming if/else cascades must align on a straight horizontal or vertical line.
- **Transition lines:** must not route under or intersect unrelated states or junctions.
- **Transition labels:** place at the midpoint of the transition line, offset 15 px to avoid overlap with the line.

---

## 11. Testing and Debuggability

### 11.1 Each state must be testable

Define entry condition, exit condition, and expected invariants for every state.

### 11.2 Transition coverage

Ensure all transitions are reachable, no dead states exist, and no hidden transitions are present.

---

## 12. Requirements Traceability

Map each model element to a requirement ID:

| Element      | Requirement category       |
| ------------ | -------------------------- |
| States       | System mode requirements   |
| Transitions  | Behavioral requirements    |
| Predicates   | Condition requirements     |
| Timers       | Timing requirements        |

Example annotation: `RUNNING [REQ-12]`, `IDLE -> RUNNING [REQ-15]`

---

## 13. Automation and LLM Compatibility

Use a structured intermediate format compatible with JSON/YAML:

```json
{
  "states": [],
  "transitions": [],
  "predicates": [],
  "timers": []
}
```

Rules:

- All transition conditions must reference predicates, simple signals, or timer outputs — no free-form logic.
- Structure must be deterministic: no ambiguous transitions, no implicit priorities, no hidden state.

---

## 14. Formal Verification Compatibility (optional)

Required conditions:

- finite state space
- deterministic transitions
- bounded variables
- no side effects in guards

Preferred characteristics:

- explicit timers
- shallow hierarchy
- no history junctions
- minimal AND decomposition

---

## 15. Recommended Architecture

| Layer                                  | Content                                              |
| -------------------------------------- | ---------------------------------------------------- |
| 1 — FSM (Stateflow)                    | System modes only                                    |
| 2 — Predicates (Simulink / functions)  | Semantic conditions                                  |
| 3 — Timing layer                       | Hybrid: Stateflow timers + optional explicit signals |
| 4 — Safety supervisor (optional)       | Second FSM for monitoring                            |

---

## 16. Predicate Computation Patterns

Predicates can live in three places. The choice affects observability, testability, and correctness with temporal operators.

### 16.1 Inline in transition condition

```matlab
[duration(devStatus ~= DevStatus_e.STANDBY) > startupTout]
```

- Evaluated only when the transition is being checked.
- No intermediate variable; cannot be logged in the Data Inspector.
- Preferred when the predicate is used in exactly one place and debugging is not a concern.

### 16.2 Computed in `during:` action (observable predicate)

```matlab
during:
    isStartupTimedOut =
        duration(devStatus ~= DevStatus_e.STANDBY) > startupTout;
```

Then used as `[isStartupTimedOut]` on the outgoing transition.

- The variable is visible and loggable in simulation.
- Evaluated once per chart tick while the state is active.
- **Important:** the temporal operator's clock belongs to the chart, not the variable. Assigning the result to a boolean does not give the predicate its own reset point. The clock resets on chart reset or first activation, not on assignment. Use `duration()` with this understanding, and verify the reset behaviour matches requirements.
- Do not use this pattern as a substitute for understanding temporal scope.

### 16.3 Local MATLAB function (pure logic only)

```matlab
function result = isCommHealthy(commAge, threshold)
    result = commAge > threshold;
end
```

- Reusable across states; unit-testable outside the chart.
- **Temporal operators (`after()`, `duration()`, `count()`) are illegal inside MATLAB functions.** Any predicate that involves timing must remain in chart context (options 16.1 or 16.2).

### 16.4 Selection guideline

| Predicate type                    | Recommended placement              |
| --------------------------------- | ---------------------------------- |
| Pure logic, single use            | Inline in transition               |
| Pure logic, reused or unit-tested | Local MATLAB function              |
| Temporal, debugging needed        | `during:` action (chart context)   |
| Temporal, formal verification     | Inline in transition               |

---

## 17. Fault Output Assignment Patterns

When multiple states can transition to a common FAULT state with different fault codes, two patterns are available.

### Pattern A — Direct condition action (recommended)

Assign the fault output directly in the condition action on each transition. Direct State → State transitions permit condition actions (see section 4.7).

```matlab
[isStartupTimedOut]
{dev_fault = DevFault_e.FAULT_STANDBY_TOUT;}
```

```text
↓

FAULT
```

- The fault code is assigned at the exact point where the cause is known.
- No additional variables required.
- Safe for all entry paths to FAULT, including future ones added by refactoring.
- Fault assignment is distributed across transitions — acceptable when each transition has a single, clear cause.

### Pattern B — Fault context variable (use with caution)

Set an intermediate variable in each transition condition action; assign the output in FAULT entry.

```matlab
% transition condition action:
[isStartupTimedOut]
{fault_context = DevFault_e.FAULT_STANDBY_TOUT;}
```

```text
↓

FAULT

entry:
    dev_fault = fault_context;
```

- Output assignment is in one place, which is useful if FAULT entry needs to branch on fault type for additional initialization.
- **Risks:**
  - `fault_context` must be initialized to a valid value at chart startup; an uninitialized value produces a silent wrong output.
  - Any code path that reaches FAULT without first setting `fault_context` (a safety supervisor, a future transition) will silently forward a stale or default code.
  - The transition and FAULT entry are implicitly coupled and must be kept synchronized.

**Rule:** use Pattern A by default. Use Pattern B only if FAULT entry must branch on fault type for initialization, and only when all entry paths to FAULT are explicitly enumerated and reviewed.

---

## 18. Automation compatibility (slxgen)

This guideline is designed to be machine-readable. The `slxgen` tool converts YAML state-machine descriptions that follow these rules into MATLAB Stateflow scripts automatically.

For details on the slxgen pipeline, coordinate system, ELK layout options, and known limitations, see [slxgen_internals.md](slxgen_internals.md).

---

## 19. Closing Principle

> A good Stateflow model is not the one that is most compact,
> but the one that is **most predictable, testable, and transformable into other representations**.

---

## References

1. Planning Model Architecture for ISO 26262 Compliance — <https://www.scribd.com/document/655978540/>
2. MathWorks Stateflow User's Guide — <https://www.mathworks.com/help/pdf_doc/stateflow/stateflow_ug.pdf>
3. MathWorks Stateflow Best Practices (GE) — <https://www.mathworks.com/content/dam/mathworks/mathworks-dot-com/campaigns/portals/files/general-electric/stateflow-best-practices.pdf>
4. MathWorks Modeling Guidelines for State Charts — <https://www.mathworks.com/help/stateflow/ug/modeling-guidelines-for-state-charts.html>
5. ISO 26262 Workflow for Automated Driving — <https://www.mathworks.com/company/technical-articles/an-iso-26262-workflow-for-automated-driving-applications-using-matlab-guidelines-and-best-practices.html>
6. Best Practices for AUTOSAR Classic and ISO 26262 — <https://www.mathworks.com/content/dam/mathworks/white-paper/best-practices-for-targeting-autosar-classic-and-iso-26262-with-simulink.pdf>
