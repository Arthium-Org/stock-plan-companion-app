# Tasks: {{MODULE_NAME}}

## Prerequisites

<!-- List any modules or tasks that must be complete before this module can begin.
     Reference specific module IDs from the execution plan. -->

- {{M{N}: Module Name}} — {{what it provides that this module needs}}

---

## Task 1: {{Task Title}}

{{One sentence describing the goal of this task.}}

- [ ] 1.1 {{Concrete implementation step — include file path where relevant}}
- [ ] 1.2 {{Step — be specific: "Create file X" or "Add function Y to Z"}}
- [ ] 1.3 {{Step}}
- [ ] 1.4 Write tests: {{describe what the tests verify}}

<!-- Task sub-step rules:
  - Each sub-step should be independently completable and verifiable
  - Include file paths for creation/modification steps
  - Group test-writing as the last sub-steps of each task
  - Prefix test sub-steps with "Write tests:" or "Write test for:"
  - Reference requirement numbers where the mapping is non-obvious
-->

## Task 2: {{Task Title}}

{{One sentence describing the goal.}}

- [ ] 2.1 {{Step}}
- [ ] 2.2 {{Step}}
- [ ] 2.3 {{Step}}
- [ ] 2.4 Write tests: {{what they verify}}

## Task 3: {{Task Title}}

{{One sentence describing the goal.}}

- [ ] 3.1 {{Step}}
- [ ] 3.2 {{Step}}
- [ ] 3.3 Write test for: {{specific scenario}}
- [ ] 3.4 Write test for: {{specific edge case}}

---

## Task N: Integration Testing

Test the module end-to-end with realistic data.

- [ ] N.1 Create test fixtures: {{describe fixture data}}
- [ ] N.2 Write integration test: {{happy path scenario}}
- [ ] N.3 Write integration test: {{error/edge case scenario}}
- [ ] N.4 Verify with sample data from `docs/Sample-Data/`

---

## Task N+1: Future Enhancements (Out of Scope)

<!-- Document known future work so it's visible but clearly deferred.
     These tasks should NOT have checkboxes — they're not actionable yet. -->

- {{Enhancement 1 — brief description and why it's deferred}}
- {{Enhancement 2}}

---

## Notes

<!-- Brief notes that apply across all tasks in this module. -->

- **Implementation priority**: {{what to build first and why}}
- **Key constraint**: {{constraint from CLAUDE.md or design doc that affects task ordering}}
- **Testing approach**: {{unit vs integration vs manual for this module}}
- **Risk**: {{what could go wrong and how to mitigate}}

<!--
## Template Usage Notes (delete this section in actual specs)

1. Tasks are numbered sequentially (Task 1, 2, 3, ...)
2. Sub-tasks use decimal notation (1.1, 1.2, 1.3, ...)
3. All actionable sub-tasks get checkboxes: - [ ]
4. Out-of-scope items do NOT get checkboxes
5. Order tasks by dependency — earlier tasks should not depend on later ones
6. Each task should be completable in one focused session
7. Include a final integration testing task for every module
8. Prerequisites reference module IDs (M1, M2, etc.) from execution-plan.md
9. Typical module has 3-8 tasks; don't over-fragment
-->
