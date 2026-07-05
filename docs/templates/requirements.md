# Requirements Document: {{MODULE_NAME}}

## Introduction

{{Brief description of the module's purpose, its role in the system, and what problem it solves. 2-4 sentences. Reference the broader system context (e.g., which layer of the architecture it belongs to, what it enables downstream).}}

## Glossary

- **{{Term_1}}**: {{Definition — use PascalCase with underscores for multi-word terms that appear in acceptance criteria}}
- **{{Term_2}}**: {{Definition}}
- **{{Term_3}}**: {{Definition}}

## Requirements

### Requirement 1: {{Requirement Title}}

**User Story:** As a {{role}}, I want {{capability}}, so that {{benefit}}.

#### Acceptance Criteria

1. WHEN {{trigger/condition}}, THE {{System_Component}} SHALL {{expected behavior}}
2. WHEN {{trigger/condition}}, THE {{System_Component}} SHALL {{expected behavior}}
3. IF {{condition}}, THEN THE {{System_Component}} SHALL {{expected behavior}}
4. THE {{System_Component}} SHALL NOT {{prohibited behavior}}

<!-- Acceptance criteria format rules:
  - Use WHEN/SHALL for normal behavior
  - Use IF/THEN for conditional behavior
  - Use SHALL NOT for prohibitions
  - Use FOR ALL for universal constraints
  - Reference glossary terms exactly as defined (PascalCase with underscores)
  - Each criterion must be independently testable
  - Number criteria sequentially within each requirement
-->

### Requirement 2: {{Requirement Title}}

**User Story:** As a {{role}}, I want {{capability}}, so that {{benefit}}.

#### Acceptance Criteria

1. WHEN {{trigger/condition}}, THE {{System_Component}} SHALL {{expected behavior}}
2. WHEN {{trigger/condition}}, THE {{System_Component}} SHALL {{expected behavior}}

<!-- Add rationale blocks for non-obvious decisions: -->

**Rationale:**
- {{Why this requirement exists or why it's designed this way}}
- {{What alternative was considered and rejected}}

**Future consideration:** {{What may change in a later phase and why it's deferred}}

### Requirement N: {{Requirement Title}} (OUT OF SCOPE - {{Phase}})

<!-- Use this pattern for requirements that are acknowledged but explicitly deferred.
     Document the deferral reason so future readers understand the boundary. -->

**User Story:** As a {{role}}, I want {{capability}}, so that {{benefit}}.

**{{Phase}} Decision:** {{Why this is deferred and what the workaround is.}}

#### Acceptance Criteria (Future Phase)

1. WHEN {{trigger/condition}}, THE {{System_Component}} SHALL {{expected behavior}}

**Rationale for deferral:**
- {{Reason 1}}
- {{Reason 2}}

<!--
## Template Usage Notes (delete this section in actual specs)

1. Number requirements sequentially (Requirement 1, 2, 3, ...)
2. Each requirement gets exactly one User Story
3. Acceptance criteria are numbered within each requirement (1, 2, 3, ...)
4. Glossary terms referenced in criteria must match exactly
5. Keep criteria atomic — one testable behavior per criterion
6. Group related requirements logically (data model, parsing, error handling, etc.)
7. Non-functional requirements (performance, security) get their own requirement blocks
8. Use OUT OF SCOPE blocks for acknowledged-but-deferred work
9. Typical module has 5-15 requirements; don't pad or split unnecessarily
-->
