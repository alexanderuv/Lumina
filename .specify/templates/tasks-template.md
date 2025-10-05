# Tasks: [FEATURE NAME]

**Input**: Design documents from `/specs/[###-feature-name]/`
**Prerequisites**: plan.md (required), research.md, data-model.md, contracts/

## Execution Flow (main)
```
1. Load plan.md from feature directory
   → If not found: ERROR "No implementation plan found"
   → Extract: tech stack, libraries, structure
2. Load optional design documents:
   → data-model.md: Extract entities → model tasks
   → contracts/: Each file → contract test task
   → research.md: Extract decisions → setup tasks
3. Generate tasks by category:
   → Setup: project init, dependencies, linting
   → Tests: contract tests, integration tests
   → Core: models, services, CLI commands
   → Integration: DB, middleware, logging
   → Polish: unit tests, performance, docs
4. Apply task rules:
   → Different files = mark [P] for parallel
   → Same file = sequential (no [P])
   → Tests before implementation (TDD)
5. Number tasks sequentially (T001, T002...)
6. Generate dependency graph
7. Create parallel execution examples
8. Validate task completeness:
   → All contracts have tests?
   → All entities have models?
   → All endpoints implemented?
9. Return: SUCCESS (tasks ready for execution)
```

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- Include exact file paths in descriptions

## Path Conventions
- **Single project**: `src/`, `tests/` at repository root
- **Web app**: `backend/src/`, `frontend/src/`
- **Mobile**: `api/src/`, `ios/src/` or `android/src/`
- Paths shown below assume single project - adjust based on plan.md structure

## Phase 3.1: Setup
- [ ] T001 Create project structure per implementation plan
- [ ] T002 Initialize [language] project with [framework] dependencies
- [ ] T003 [P] Configure linting and formatting tools

## Phase 3.2: Core Implementation
**IMPORTANT: Use Swift Testing framework ONLY - NO XCTest**
- [ ] T004 [P] User model in src/models/user.py
- [ ] T005 [P] UserService CRUD in src/services/user_service.py
- [ ] T006 [P] CLI --create-user in src/cli/user_commands.py
- [ ] T007 POST /api/users endpoint
- [ ] T008 GET /api/users/{id} endpoint
- [ ] T009 Input validation
- [ ] T010 Error handling and logging

## Phase 3.3: Comprehensive Testing (after implementation)
**Write tests to verify implemented behavior and achieve 80% coverage**
- [ ] T011 [P] Contract test POST /api/users in tests/contract/test_users_post.py
- [ ] T012 [P] Contract test GET /api/users/{id} in tests/contract/test_users_get.py
- [ ] T013 [P] Integration test user registration in tests/integration/test_registration.py
- [ ] T014 [P] Integration test auth flow in tests/integration/test_auth.py

## Phase 3.4: Integration
- [ ] T015 Connect UserService to DB
- [ ] T016 Auth middleware
- [ ] T017 Request/response logging
- [ ] T018 CORS and security headers

## Phase 3.5: Additional Tests & Polish
- [ ] T019 [P] Unit tests for validation in tests/unit/test_validation.py
- [ ] T020 Performance tests (<200ms)
- [ ] T021 [P] Update docs/api.md
- [ ] T022 Remove duplication
- [ ] T023 Verify 80% code coverage achieved
- [ ] T024 Verify locally: builds, all tests pass, code runs, documentation builds
- [ ] T025 Run manual-testing.md

## Dependencies
- Implementation (T004-T010) before tests (T011-T014)
- T004 blocks T005, T015
- T016 blocks T018
- Implementation before polish (T019-T023)

## Parallel Example
```
# Launch T004-T007 together:
Task: "Contract test POST /api/users in tests/contract/test_users_post.py"
Task: "Contract test GET /api/users/{id} in tests/contract/test_users_get.py"
Task: "Integration test registration in tests/integration/test_registration.py"
Task: "Integration test auth in tests/integration/test_auth.py"
```

## Notes
- [P] tasks = different files, no dependencies
- Use Swift Testing framework ONLY (NO XCTest)
- Implementation first, then comprehensive tests (NO TDD)
- Achieve 80% code coverage minimum
- Verify locally before submitting: builds, tests pass, code runs, docs build
- Commit after each task
- Avoid: vague tasks, same file conflicts

## Task Generation Rules
*Applied during main() execution*

1. **From Contracts**:
   - Each contract file → contract test task [P]
   - Each endpoint → implementation task
   
2. **From Data Model**:
   - Each entity → model creation task [P]
   - Relationships → service layer tasks
   
3. **From User Stories**:
   - Each story → integration test [P]
   - Quickstart scenarios → validation tasks

4. **Ordering**:
   - Setup → Implementation → Tests → Polish
   - Dependencies block parallel execution

## Validation Checklist
*GATE: Checked by main() before returning*

- [ ] All contracts have corresponding tests
- [ ] All entities have model tasks
- [ ] All tests use Swift Testing framework (XCTest prohibited)
- [ ] All tests come AFTER implementation (NO TDD)
- [ ] Coverage verification task included (80% minimum)
- [ ] Pre-submission verification task included
- [ ] Parallel tasks truly independent
- [ ] Each task specifies exact file path
- [ ] No task modifies same file as another [P] task