# Contributing to Lumina

Thank you for your interest in contributing to Lumina! This document outlines the development methodology, coding standards, and contribution workflow.

## Development Philosophy

Lumina follows an **implementation-first methodology** (NOT TDD):

1. **Implement** → Design and write working code first
2. **Verify** → Test the implementation manually
3. **Test** → Write automated tests to verify behavior

This approach is codified in the project constitution and applies to all contributions.

## Prerequisites

- macOS 15.0+ (Sequoia) for macOS development
- Swift 6.0+ (6.2+ recommended)
- Xcode 16.0+ (for macOS platform)
- Familiarity with Swift 6 features:
  - Strict concurrency (`@MainActor`, `Sendable`)
  - Ownership annotations (`borrowing`, `consuming`, `~Copyable`)
  - Modern result builders and async/await

## Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/Lumina.git
   cd Lumina
   ```

2. **Build the project**:
   ```bash
   swift build
   ```

3. **Run tests**:
   ```bash
   swift test
   ```

4. **Try the examples**:
   ```bash
   cd Examples/HelloWindow
   swift run
   ```

## Project Structure

```
Lumina/
├── Sources/
│   └── Lumina/              # Public cross-platform API
│       ├── Application.swift
│       ├── Window.swift
│       ├── Cursor.swift
│       ├── Geometry.swift
│       ├── Events.swift
│       ├── Errors.swift
│       ├── WindowID.swift
│       ├── EventLoopBackend.swift
│       ├── WindowBackend.swift
│       ├── MacApplication.swift    # macOS backend (#if os(macOS))
│       ├── MacWindow.swift
│       ├── MacInput.swift
│       ├── WinApplication.swift    # Windows backend (#if os(Windows))
│       ├── WinWindow.swift
│       └── WinInput.swift
├── Tests/
│   └── LuminaTests/         # Swift Testing tests
├── Examples/                # Example applications
└── specs/                   # Design documents
```

## Coding Standards

### Swift Style

- **Language Mode**: Swift 6.2+ with strict concurrency enabled
- **Naming**: Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- **Access Control**: Use `public`, `internal`, `private` appropriately
  - Public API: Fully documented with examples
  - Internal: Implementation details
  - Private: File-scoped implementation
- **Documentation**: All public APIs must have complete documentation

### Concurrency

- Use `@MainActor` for all window/UI operations
- Mark types `Sendable` when they can cross actor boundaries
- Use `async/await` for asynchronous operations
- Never block the main thread

### Ownership Model

Lumina uses Swift's borrowing ownership model for performance:

- **`borrowing`**: Read-only access, no copy (hot paths)
- **`consuming`**: Transfer ownership, invalidates original
- **`~Copyable`**: Prevent accidental duplication (Application, Window)

Example:
```swift
// Good: Window.close() consumes self
public consuming func close() {
    backend.close()
}

// Good: Event dispatch with borrowing
func dispatch(borrowing event: Event) {
    // Read-only access, no copy
}
```

### Platform Abstractions

- Use conditional compilation for platform-specific code:
  ```swift
  #if os(macOS)
  // macOS implementation
  #elseif os(Windows)
  // Windows implementation
  #endif
  ```
- Keep platform code isolated in platform-specific files
- Public API must be platform-agnostic

### Error Handling

- Use `Result<T, LuminaError>` for recoverable errors (e.g., window creation)
- Use `throws` for critical failures (e.g., event loop errors)
- Provide actionable error messages with context

## Testing

### Framework: Swift Testing Only

Lumina uses **Swift Testing** framework, NOT XCTest:

```swift
import Testing
@testable import Lumina

@Suite("Feature Name")
struct FeatureTests {
    @Test("Test description")
    func testSomething() {
        #expect(value == expected)
    }
}
```

### Test Organization

- **GeometryTests.swift**: Geometry types (sizes, positions, conversions)
- **EventTests.swift**: Event types and pattern matching
- **ErrorTests.swift**: Error handling and conformance
- Platform-specific tests: Conditional compilation in same test file

### Testing Guidelines

1. **Implementation First**: Write tests AFTER implementing features
2. **Focus on Behavior**: Test discrete, testable components
3. **No Arbitrary Coverage**: No coverage percentage mandates
4. **Edge Cases**: Test boundary conditions, zero values, negative inputs
5. **Sendable/Hashable**: Verify protocol conformance where applicable

### Running Tests

```bash
# Run all tests
swift test

# Run with parallel execution
swift test --parallel

# Run specific test suite
swift test --filter GeometryTests

# Verbose output
swift test --verbose
```

## Contribution Workflow

### 1. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Implement Your Feature

Follow the implementation-first methodology:
1. Design the API
2. Implement the feature
3. Manually verify it works
4. Write tests to verify behavior

### 3. Ensure Code Quality

- **Build without warnings**:
  ```bash
  swift build -Xswiftc -warnings-as-errors
  ```

- **Run tests**:
  ```bash
  swift test
  ```

- **Format code consistently**:
  - Use 4 spaces for indentation
  - Maximum line length: 100 characters (flexible for documentation)

- **Document public APIs**:
  ```swift
  /// Brief description of what the function does.
  ///
  /// Detailed explanation of behavior, edge cases, and usage.
  ///
  /// - Parameters:
  ///   - param1: Description of param1
  ///   - param2: Description of param2
  /// - Returns: Description of return value
  /// - Throws: When and why this throws
  ///
  /// Example:
  /// ```swift
  /// let result = doSomething(param1: value1, param2: value2)
  /// ```
  public func doSomething(param1: Type1, param2: Type2) throws -> ReturnType {
      // Implementation
  }
  ```

### 4. Commit Your Changes

Follow conventional commit format:

```bash
git commit -m "Add feature: window opacity control

- Implement Window.setOpacity(_:) method
- Add opacity property to WindowBackend protocol
- Add tests for opacity range validation
- Update documentation with opacity examples"
```

### 5. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a pull request with:
- **Title**: Brief description of the feature/fix
- **Description**:
  - What was changed and why
  - Test plan and verification steps
  - Breaking changes (if any)
  - Related issues (if applicable)

## Pull Request Checklist

Before submitting a PR, ensure:

- [ ] Code builds without warnings
- [ ] All tests pass (`swift test`)
- [ ] New features have tests
- [ ] Public APIs are documented
- [ ] Examples updated (if applicable)
- [ ] README updated (if adding major features)
- [ ] No breaking changes (or clearly documented)
- [ ] Platform compatibility verified (macOS 15+)

## Constitutional Principles

Lumina development adheres to these core principles:

1. **Complete API Documentation**: All public APIs must have:
   - Description of functionality
   - Parameter documentation
   - Return value documentation
   - Usage examples
   - Error conditions (when applicable)

2. **No Broken States**: Use Swift's type system to prevent invalid states:
   - `~Copyable` for unique resources (Window, Application)
   - `consuming` for destructive operations
   - `borrowing` for read-only access
   - Optional for truly optional values

3. **Modern Swift Idioms**: Leverage Swift 6.2+ features:
   - Strict concurrency (`@MainActor`, `Sendable`)
   - Borrowing ownership model
   - Result builders where appropriate
   - Async/await for concurrency

4. **Platform Abstractions**: Clean separation between:
   - Public cross-platform API
   - Internal platform backends
   - Conditional compilation for platform-specific code

5. **Swift Testing Only**: Use Swift Testing framework:
   - `@Test` and `@Suite` attributes
   - `#expect()` for assertions
   - NO XCTest imports

6. **Borrowing Ownership in Hot Paths**:
   - Event dispatch uses `borrowing`
   - Avoid unnecessary copies
   - Profile and optimize based on measurements

## Platform-Specific Contributions

### macOS (AppKit)

- Use `NSApplication`, `NSWindow`, `NSEvent`
- Handle coordinate system differences (AppKit uses bottom-left origin)
- Support Retina displays (`backingScaleFactor`)
- Follow macOS HIG for window behavior

### Windows (Win32)

- Use Win32 API (`CreateWindowEx`, message loop)
- Handle DPI awareness (`SetProcessDpiAwareness`, `GetDpiForWindow`)
- Support high-DPI displays
- Follow Windows UX guidelines

## Getting Help

- **Issues**: Report bugs or request features via GitHub Issues
- **Discussions**: Ask questions in GitHub Discussions
- **Spec Documents**: See `specs/` directory for design rationale

## Code of Conduct

- Be respectful and constructive
- Focus on the code, not the person
- Welcome newcomers and help them learn
- Follow the Swift community guidelines

## License

By contributing to Lumina, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to Lumina! Your efforts help build a better cross-platform windowing library for the Swift community.
