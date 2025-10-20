<!--
Sync Impact Report:
Version: 1.4.1 → 1.4.2 (PATCH - testing standards clarification)
Modified principles: None
Modified sections:
  - Quality Standards > Testing Standards → Clarified that integration tests are NOT required (all testing is platform-dependent)
Added sections: None
Removed sections: None
Templates requiring updates:
  ✅ plan-template.md - No changes needed
  ✅ spec-template.md - No changes needed
  ✅ tasks-template.md - No changes needed
Follow-up TODOs: None
-->

# Lumina Constitution

## Core Principles

### I. API Documentation (NON-NEGOTIABLE)
All public APIs MUST be documented with clear descriptions, parameter explanations, return values, and usage examples. No public symbol may be exposed without complete documentation. This ensures library usability and prevents breaking changes from being introduced unknowingly.

**Rationale**: As a library consumed by external developers, incomplete API documentation creates friction, support burden, and potential misuse. Documentation is part of the public contract.

### II. No Broken States
Code MUST NOT be committed in a broken state. All commits MUST compile, pass tests, and maintain functional integrity. Developers MUST verify code runs locally before submitting for review. CI/CD is a safety net, not the primary verification mechanism. Work-in-progress features MUST be feature-flagged or maintained in separate branches until complete.

**Rationale**: Broken states block other developers, break CI/CD pipelines, and create technical debt. Developer pre-verification catches issues early and respects team time. Swift's strict type system and compilation requirements make this principle enforceable at build time.

### III. Swift 6.2+ Modern Idioms
All code MUST leverage Swift 6.2+ features including strict concurrency, modern result builders, and type-safe APIs. Avoid legacy patterns, Objective-C bridging unless necessary for platform compatibility, and unsafe constructs.

**Rationale**: Swift 6.2+ provides superior memory safety, concurrency guarantees, and expressiveness. Using modern idioms ensures long-term maintainability and reduces runtime errors.

### IV. Cross-Platform Compatibility
Features MUST work across all supported platforms unless explicitly documented as platform-specific. Platform abstractions MUST be clean, testable, and avoid leaking platform details.

**Supported Platforms**:
- macOS 15+ (Sequoia and later)
- Windows 11+

**Rationale**: Lumina is a cross-platform library. Platform-specific code creates fragmentation and maintenance burden. Abstractions ensure consistent behavior and easier testing. Minimum platform versions ensure access to modern APIs and reduce compatibility burden.

### V. Test Coverage & Quality (Swift Testing Only)
All features MUST include comprehensive tests using Swift Testing framework. XCTest is prohibited. Tests MUST be maintainable, deterministic, and cover edge cases. Tests MUST be written for discrete, testable components without arbitrary coverage percentage targets. The project does NOT follow TDD; tests are written after implementation to verify behavior.

**Rationale**: Swift Testing provides modern async/await support, better diagnostics, and superior Swift 6 integration compared to XCTest. Standardizing on one framework reduces cognitive overhead and improves test maintainability. A windowing library interacts with OS-level APIs where bugs have high user impact. Due to the exploratory nature of windowing system integration, TDD is not practical; implementation-first with comprehensive test coverage is the chosen approach. Coverage percentages are not mandated as they can encourage gaming metrics rather than meaningful testing.

### VI. Borrowing Ownership Model
Developers MUST make every effort to reduce reliance on Swift ARC and prefer the borrowing ownership model where feasible. Use `borrowing` and `consuming` parameter modifiers, avoid unnecessary reference counting overhead, and design APIs that minimize retain/release cycles.

**Rationale**: A windowing library requires high performance and predictable memory behavior. The borrowing ownership model reduces ARC overhead, eliminates reference counting churn, and provides deterministic memory management. This is critical for real-time rendering and event handling where ARC cycles can cause frame drops.

## Development Workflow

### Testing Methodology
This project does NOT follow Test-Driven Development (TDD). Due to the exploratory nature of windowing system integration and platform-specific APIs, implementation comes first followed by comprehensive test coverage. Tests verify correct behavior after implementation is complete.

**Workflow**: Implement → Verify manually → Write comprehensive tests for discrete, testable components

**Rationale**: Windowing APIs require experimentation with OS-specific behaviors that are difficult to specify upfront. Writing tests after understanding the platform behavior leads to more accurate and maintainable tests.

### Pre-Submission Verification
Developers MUST verify the following locally before submitting code for review:
- Code compiles without errors or warnings
- All tests pass (run full test suite)
- Code runs successfully in target environment
- Documentation builds without errors (if applicable)
- CI/CD MUST NOT be the first verification point

**Rationale**: Local verification respects reviewer time, catches issues early, and maintains development velocity. CI/CD should confirm what developers have already validated, not discover basic failures.

### Code Review Requirements
- All changes MUST be reviewed by at least one maintainer
- Public API changes require design review and documentation review
- Breaking changes require migration guide and deprecation period
- Platform-specific code requires testing on target platform

### Commit Standards
- Commits MUST follow conventional commit format
- Each commit MUST represent a complete, buildable change
- Commit messages MUST explain "why" not just "what"
- Breaking changes MUST be clearly marked in commit message

### Branching Strategy
- `main` branch MUST always be stable and buildable
- Feature branches for new functionality
- Hotfix branches for critical bugs
- Release branches for version preparation

## Quality Standards

### Performance Requirements
- Window creation MUST complete in <100ms on reference hardware
- Event handling MUST not block UI thread for >16ms (60fps)
- Memory usage MUST not leak across window lifecycle
- Platform API calls MUST be asynchronous where blocking would impact UX

### Memory Management
- Prefer borrowing ownership model (`borrowing`, `consuming`) over ARC where possible
- Minimize retain/release cycles in hot paths (rendering, event handling)
- Profile and measure ARC overhead in performance-critical code
- Document justification when ARC is required (callbacks, async closures, shared state)
- Use value types and stack allocation where feasible

**Rationale**: Predictable, low-overhead memory management is essential for consistent frame rates and responsive UI. The borrowing model eliminates reference counting overhead in performance-critical paths.

### Security & Safety
- All pointer usage MUST be justified and documented
- Unsafe Swift MUST be isolated and thoroughly reviewed
- User input MUST be validated at API boundaries
- Platform security features (sandboxing, entitlements) MUST be respected

### Documentation Standards
- Public APIs: Complete documentation with examples
- Internal APIs: Purpose and usage documentation
- Complex algorithms: Explanation of approach and trade-offs
- Platform-specific code: Why platform-specific and alternatives considered
- File paths: MUST use relative paths in all documentation and code; absolute paths are prohibited

**Rationale**: Absolute paths break portability across development environments, CI/CD systems, and user machines. Relative paths ensure documentation and code work regardless of repository location.

### Testing Standards
- All tests MUST use Swift Testing framework
- XCTest is prohibited
- Tests MUST support async/await patterns
- Test names MUST clearly describe what is being tested
- Integration tests are NOT required; all testing is platform-dependent and requires window creation

**Rationale**: Windowing library tests inherently require platform-specific window creation and event handling. What might traditionally be called "integration tests" are actually platform-specific tests. Unit tests focus on discrete, testable components (geometry calculations, event type conversions, etc.) while platform-specific tests verify actual windowing behavior on each supported platform.

## Governance

### License
This project is licensed under the MIT License. All contributions MUST comply with MIT license terms. Contributors retain copyright of their contributions while granting the project rights under MIT terms.

### Amendment Process
1. Constitution changes MUST be proposed via pull request
2. Changes require approval from majority of maintainers
3. Breaking principle changes require migration plan
4. Version bump follows semantic versioning:
   - MAJOR: Backward incompatible principle changes
   - MINOR: New principles or sections added
   - PATCH: Clarifications and wording improvements

### Compliance Review
- All pull requests MUST verify constitutional compliance
- CI/CD MUST enforce: builds pass, tests pass, documentation complete
- Quarterly audits of codebase against principles
- Violations MUST be justified or remediated

### Versioning Policy
- Library follows semantic versioning (MAJOR.MINOR.PATCH)
- Constitution follows semantic versioning independently
- Constitution version changes documented in amendment history
- Breaking changes require deprecation warnings for at least one minor version

**Version**: 1.4.2 | **Ratified**: 2025-10-04 | **Last Amended**: 2025-10-04
