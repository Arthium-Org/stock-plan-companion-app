# Design Document: {{MODULE_NAME}}

## Overview

{{2-4 sentences describing what this module does, how it fits into the system architecture, and its primary responsibilities. Reference the medallion layer (Bronze/Silver/Gold) or system layer this belongs to.}}

### Key Design Principles

1. **{{Principle Name}}**: {{One-line description of the principle and why it matters}}
2. **{{Principle Name}}**: {{One-line description}}
3. **{{Principle Name}}**: {{One-line description}}

<!-- Principles are module-specific constraints that guide implementation decisions.
     Examples: "Idempotent", "Pure functions (no DB writes)", "Append-only", "Rebuildable" -->

### Architecture

<!-- ASCII diagram showing how this module relates to its inputs and outputs.
     Show data flow, not class hierarchy. Keep it simple — one diagram per module. -->

```
{{Input Source}}
     |
     v
┌──────────────┐
│  {{Module}}  │
│  (file.ex)   │
└──────┬───────┘
       |
       v
{{Output / Next Stage}}
```

## Components and Interfaces

### 1. {{Component Name}} (`lib/stock_plan/path/to/file.ex`)

**Responsibility**: {{One sentence — what this component owns}}

**Public Interface**:
```elixir
@doc """
{{Brief description}}
"""
@spec function_name(arg_type) :: return_type
def function_name(arg) do
  # ...
end
```

**Behavior**:
1. {{Step 1 of what happens when this function is called}}
2. {{Step 2}}
3. {{Step 3}}

<!-- For each component:
     - State the file path
     - Define the public interface with @spec typespecs
     - Describe behavior as a numbered sequence
     - Note error conditions and what they return
-->

### 2. {{Component Name}} (`lib/stock_plan/path/to/file.ex`)

**Responsibility**: {{One sentence}}

**Public Interface**:
```elixir
@spec function_name(arg_type) :: {:ok, result_type} | {:error, reason}
```

**Key Algorithms**:

{{Describe any non-trivial logic — e.g., parent-child row linking, date normalization,
  cost basis computation. Use numbered steps or pseudocode.}}

```
# Pseudocode for {{algorithm name}}
for each row in sheet:
  if row.record_type == "Grant":
    current_parent = row
  elif row.record_type == "Event":
    link row to current_parent
```

## Data Models

<!-- Define structs, schemas, or intermediate data shapes this module produces or consumes.
     Use Elixir struct notation or Ecto schema format. -->

### {{Struct/Schema Name}}

```elixir
defmodule StockPlan.Schema.{{Name}} do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "{{table_name}}" do
    field :field_name, :string
    field :field_name, StockPlan.Types.SafeDecimal
    timestamps(type: :string)
  end
end
```

### {{Intermediate Struct}} (in-memory, not persisted)

```elixir
defmodule StockPlan.Ingestion.{{Name}} do
  defstruct [
    :field_1,
    :field_2,
    :field_3
  ]

  @type t :: %__MODULE__{
    field_1: String.t(),
    field_2: String.t(),
    field_3: integer()
  }
end
```

## Correctness Properties

<!-- Formal statements about what must always be true for this module.
     Each property should be testable. Reference the requirement it validates. -->

### Property 1: {{Property Name}}

*For any* {{input condition}}, {{what must be true about the output}}.

**Validates:** Requirement {{N}}, Criteria {{M}}

### Property 2: {{Property Name}}

*For any* {{input condition}}, {{what must be true about the output}}.

**Validates:** Requirement {{N}}, Criteria {{M}}

## Error Handling

<!-- How this module handles failures. Be specific about what errors are possible
     and what happens for each. -->

| Error Condition | Handling Strategy | Caller Impact |
|---|---|---|
| {{condition}} | {{what happens}} | {{what caller sees}} |
| {{condition}} | {{what happens}} | {{what caller sees}} |

## Testing Strategy

<!-- What types of tests this module needs and what they verify. -->

| Test Type | What It Covers | Key Scenarios |
|---|---|---|
| Unit | {{scope}} | {{key cases}} |
| Integration | {{scope}} | {{key cases}} |
| Property-based | {{scope}} | {{key cases}} |

## Implementation Notes

<!-- Any gotchas, SQLite-specific behavior, library choices, or non-obvious decisions
     that an implementer should know. Keep it brief — these are notes, not prose. -->

- {{Note 1}}
- {{Note 2}}

<!--
## Template Usage Notes (delete this section in actual specs)

1. Components section mirrors the directory structure in CLAUDE.md
2. Use Elixir code blocks with @spec typespecs for interfaces
3. Architecture diagram should show THIS module's data flow, not the full system
4. Correctness properties must reference specific requirements
5. Error handling table covers this module's boundary — what it catches vs. what it propagates
6. Keep design decisions that are already in CLAUDE.md brief (reference, don't repeat)
7. Focus on the "how" that isn't obvious from the requirements or CLAUDE.md
-->
