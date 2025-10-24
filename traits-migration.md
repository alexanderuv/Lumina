# Wayland Backend: Trait-Based Migration Plan

## Overview

This document outlines the migration from manual compilation flags to SPM traits for Wayland backend selection, enabling truly frictionless backend configuration.

## Current State

**User experience:**
```bash
# X11 only (default)
swift build

# Wayland support (manual flag)
swift build -Xswiftc -DLUMINA_WAYLAND
```

**Problems:**
- Cryptic compiler flags required
- Not discoverable
- Plugin generates protocols but requires manual invocation
- Wayland code always compiled (if flag present), even if dependencies missing

## Target State

**User experience:**
```bash
# X11 only (default)
swift build

# Wayland support (clean, discoverable)
swift build --traits Wayland

# View available traits
swift package describe --traits
```

**Benefits:**
- Self-documenting API
- Wayland code only compiles when trait enabled
- Plugin only runs when needed
- No false warnings
- Conditional compilation via `#if Wayland` (trait name)

---

## Key Concept: Dependency Graph Reachability

**How targets become conditional without a `condition:` parameter:**

Swift Package Manager only builds **reachable targets** - targets that are connected via the dependency graph from root packages. When you make all dependencies TO a target conditional on a trait:

1. **Trait disabled** → No dependencies reference the target → Target unreachable → Not built → Plugins don't run ✅
2. **Trait enabled** → Dependencies reference the target → Target reachable → Built → Plugins run ✅

This is different from traditional conditional compilation flags:
- **Old approach:** Target always compiled, flags control what code is active
- **New approach:** Target only compiled if reachable through dependency graph

**Example:**
```swift
// Target definition (no condition parameter - doesn't exist!)
.target(name: "CWaylandClient", plugins: [...])

// Dependency in consuming target (this is what makes it conditional)
.target(
    name: "Lumina",
    dependencies: [
        .target(name: "CWaylandClient", condition: .when(traits: ["Wayland"]))
    ]
)
```

Result: If `Lumina` is the only thing that depends on `CWaylandClient`, and that dependency is conditional, then `CWaylandClient` becomes effectively conditional.

---

## Required SPM Features

### 1. Package Traits (Swift 6.1+)

**Feature:** Define optional features that can be enabled by users.

**Documentation:** [SE-0450](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md)

**Syntax:**
```swift
let package = Package(
    name: "MyPackage",
    traits: [
        .trait(name: "FeatureName", description: "Feature description"),
        .default(enabledTraits: ["DefaultFeature"])
    ]
)
```

**Usage:**
```bash
swift build --traits FeatureName
```

### 2. Conditional Target Compilation via Dependency Graph Reachability

**Feature:** Targets become conditionally compiled based on dependency graph reachability. If no dependencies reference a target, SPM won't build it.

**Key Capability:** When all dependencies to a target are conditional on traits, the target (and its plugins) only build when the trait is enabled. SPM only builds "reachable" targets - those connected via the dependency graph.

**How it works:**
- Target is defined normally (no `condition` parameter exists on targets)
- All dependencies TO that target are made conditional
- If trait disabled → target unreachable → target not built → plugins don't run
- If trait enabled → target reachable → target built → plugins run

**Note:** There is no `condition:` parameter on `.target()` itself - conditions only exist on dependencies.

### 3. Conditional Dependencies Based on Traits

**Feature:** Dependencies can be conditional on traits.

**Syntax:**
```swift
.target(
    name: "MainTarget",
    dependencies: [
        .target(name: "OptionalDep", condition: .when(traits: ["FeatureName"]))
    ]
)
```

### 4. Trait-Based Defines for Conditional Compilation

**Feature:** Define custom compiler symbols based on enabled traits.

**How it works:**
- Use `.define("SYMBOL", .when(traits: ["TraitName"]))` in swiftSettings
- The define is only active when the trait is enabled
- Code uses standard `#if SYMBOL` conditionals

**Syntax:**
```swift
// In Package.swift:
swiftSettings: [
    .define("LUMINA_WAYLAND", .when(traits: ["Wayland"]))
]

// In source code:
#if LUMINA_WAYLAND
import CWaylandClient
// Use Wayland APIs
#endif
```

**Benefit:** Existing conditional compilation code continues to work unchanged - only the mechanism for controlling the define changes (from manual `-Xswiftc -D` flags to traits).

**Note:** You can also check traits directly with `#if Wayland`, but using custom defines keeps existing code working without modifications.

**Important:** Do NOT use `#if canImport()` for trait-based conditionals - it's non-deterministic and can cause race conditions in clean vs incremental builds.

---

## Implementation Steps

### Step 1: Update Swift Tools Version

**File:** `Package.swift`

```swift
// Change from:
// swift-tools-version: 6.0

// To:
// swift-tools-version: 6.2
```

**Reason:** Traits require Swift 6.1+

**Note:** While traits are available in Swift 6.1, using 6.2 is recommended to get bug fixes for trait-guarded dependencies. However, 6.1 is the minimum required version.

### Step 2: Define Wayland Trait

**File:** `Package.swift`

Add traits definition:

```swift
let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v15)],
    traits: [
        .trait(
            name: "Wayland",
            description: "Enable Wayland backend support on Linux"
        )
    ],
    // ...
)
```

### Step 3: Make Lumina's Wayland Dependency Conditional

**File:** `Package.swift`

Update Lumina target dependencies and add trait-based define:

```swift
.target(
    name: "Lumina",
    dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .target(name: "CXCBLinux", condition: .when(platforms: [.linux])),

        // Change from always-included to conditional:
        .target(
            name: "CWaylandClient",
            condition: .when(traits: ["Wayland"])  // ← Add condition
        )
    ],
    swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("StrictConcurrency"),
        .define("LUMINA_X11", .when(platforms: [.linux])),

        // Keep LUMINA_WAYLAND define, now controlled by trait
        .define("LUMINA_WAYLAND", .when(traits: ["Wayland"]))
    ]
)
```

**Effect:** The existing `#if LUMINA_WAYLAND` code continues to work unchanged - the define is now controlled by the trait instead of a manual compiler flag.

### Step 4: Update Conditional Compilation Checks

**No code changes required.**

The existing `#if LUMINA_WAYLAND` conditionals continue to work as-is. The define is now controlled by the `--traitsWayland` flag instead of `-Xswiftc -DLUMINA_WAYLAND`.

**Example (no changes needed):**

```swift
#if LUMINA_WAYLAND
import CWaylandClient
// Wayland code
#else
// Fallback
#endif
```

### Step 5: Update Documentation

**Files to update:**
- `README.md`
- `docs/platform-compatibility.md`
- Any other docs mentioning `-DLUMINA_WAYLAND`

**Before:**
```markdown
To enable Wayland support:
\`\`\`bash
swift build -Xswiftc -DLUMINA_WAYLAND
\`\`\`
```

**After:**
```markdown
To enable Wayland support:
\`\`\`bash
swift build --traits Wayland
\`\`\`

To list available traits:
\`\`\`bash
swift package describe --traits
\`\`\`
```

### Step 6: Update Example Projects

**Important:** Example projects must mirror the Wayland trait because traits don't propagate from dependencies.

**Pattern for all examples:**
```swift
// In Examples/*/Package.swift:
traits: [
    .trait(name: "Wayland", description: "Enable Wayland backend support")
],
dependencies: [
    .package(
        name: "Lumina",
        path: "../..",
        traits: [
            .defaults,
            .init(name: "Wayland", condition: .when(traits: ["Wayland"]))
        ]
    )
]
```

This allows: `cd Examples/WaylandDemo && swift build --traits Wayland`

### Step 7: Update Build Scripts

**File:** `Examples/WaylandDemo/build-wayland.sh`

**Before:**
```bash
swift build -Xswiftc -DLUMINA_WAYLAND
```

**After:**
```bash
swift build --traits Wayland
```

---

## Migration Checklist

- [ ] Verify Swift 6.1+ is available (`swift --version`)
- [ ] Update `swift-tools-version` to 6.1 or 6.2 in `Package.swift`
- [ ] Add `traits` definition to Package.swift
- [ ] Add `condition: .when(traits: ["Wayland"])` to CWaylandClient dependency in Lumina target
- [ ] Add `.define("LUMINA_WAYLAND", .when(traits: ["Wayland"]))` to swiftSettings
- [ ] Update all example projects to mirror the Wayland trait
- [ ] Update README.md
- [ ] Update docs/platform-compatibility.md
- [ ] Update Examples/WaylandDemo/build-wayland.sh
- [ ] Update Examples/WaylandDemo/README.md
- [ ] Test build without trait: `swift build` (should build X11 only, CWaylandClient unreachable)
- [ ] Test build with trait: `swift build --traits Wayland` (should build Wayland, CWaylandClient reachable)
- [ ] Test trait listing: `swift package describe --traits`
- [ ] Verify plugin warnings only appear when trait enabled
- [ ] Update any CI/CD scripts

---

## Testing

### Test Case 1: X11 Only (Default)
```bash
swift build
swift test
```
**Expected:**
- ✓ CXCBLinux target builds
- ✓ Lumina builds with X11 support
- ✗ CWaylandClient target skipped
- ✗ generate-wayland-protocols plugin doesn't run
- ✓ Tests pass

### Test Case 2: Wayland (With Dependencies)
```bash
# On Linux with wayland-scanner installed
swift build --traits Wayland
swift test --traits Wayland
```
**Expected:**
- ✓ CXCBLinux target builds
- ✓ CWaylandClient target builds
- ✓ generate-wayland-protocols plugin runs
- ✓ Protocol bindings generated
- ✓ Lumina builds with X11 + Wayland support
- ✓ Tests pass

### Test Case 3: Wayland (Missing Dependencies)
```bash
# On Linux without wayland-scanner
swift build --traits Wayland
```
**Expected:**
- ✓ CXCBLinux target builds
- ✓ CWaylandClient target attempts to build
- ⚠️  Plugin warns about missing wayland-scanner
- ✗ Build fails (no protocol bindings generated)
- ℹ️  Error message guides user to install dependencies

### Test Case 4: Runtime Auto-Selection
```bash
# Build with Wayland support
swift build --traits Wayland

# Run with WAYLAND_DISPLAY set
WAYLAND_DISPLAY=wayland-0 ./MyApp
# Expected: Uses WaylandPlatform

# Run with WAYLAND_DISPLAY unset
unset WAYLAND_DISPLAY
./MyApp
# Expected: Falls back to X11Platform
```

---

## Backward Compatibility

### Breaking Changes

**For users:**
- Old flag `-Xswiftc -DLUMINA_WAYLAND` will no longer work
- Must use `--traits Wayland` instead
- Requires Swift 6.2+ (Xcode 16.3+)

**Migration path:**
```bash
# Old (stops working)
swift build -Xswiftc -DLUMINA_WAYLAND

# New (required)
swift build --traits Wayland
```

**Toolchain requirements:**
- **macOS:** Xcode 16.2 or later (includes Swift 6.1+)
- **Linux:** Swift 6.1+ toolchain via swiftly or swift.org
- **Recommended:** Swift 6.2 for bug fixes in trait-guarded dependency handling

### Non-Breaking Changes

- `.auto` runtime selection behavior unchanged
- API surface unchanged
- Default behavior (X11 only) unchanged

---

## Benefits Summary

### For Users
- ✅ Simple, discoverable API: `--traits Wayland`
- ✅ No cryptic compiler flags
- ✅ Faster builds (Wayland code not compiled unless needed)
- ✅ Clear error messages

### For Developers
- ✅ No source code changes required (existing `#if LUMINA_WAYLAND` continues to work)
- ✅ Better IDE support (traits are first-class SPM features)
- ✅ Simpler Package.swift (traits replace manual flag passing)
- ✅ Plugin only runs when relevant (no false warnings)
- ✅ Targets only compile when reachable (faster builds)

### For Maintainers
- ✅ Easier to add new backends (just add traits)
- ✅ Clear dependency graph
- ✅ Better documentation
- ✅ Reduced support burden (self-documenting)

---

## Common Misconceptions (Corrected)

### ❌ Misconception 1: Targets can have a `condition:` parameter
**Reality:** There is NO `condition:` parameter on `.target()` definitions. Conditions only exist on **dependencies**. Targets become conditional through dependency graph reachability.

### ❌ Misconception 2: Use `#if canImport()` for traits
**Reality:** The `canImport()` approach is non-deterministic and unreliable for trait-based conditionals. Use trait-based defines like `#if LUMINA_WAYLAND` via `.define("LUMINA_WAYLAND", .when(traits: ["Wayland"]))`, or check the trait directly with `#if Wayland`.

### ❌ Misconception 3: Traits prevent targets from being "compiled"
**Reality:** Traits make targets **unreachable** when disabled. SPM only builds reachable targets (those connected via the dependency graph). This achieves the same goal but through a different mechanism.

### ✅ Correct Understanding
- Define traits at package level
- Make dependencies conditional: `.target(name: "Foo", condition: .when(traits: ["Bar"]))`
- Use trait-based defines: `.define("MY_FEATURE", .when(traits: ["Bar"]))`
- Check defines in code: `#if MY_FEATURE`
- Unreachable targets (with no dependencies pointing to them) are not built

---

## References

- [SE-0450: Package Traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md)
- [Swift Package Manager Documentation](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/)
- [All About SPM Traits](https://theswiftdev.com/2025/all-about-swift-package-manager-traits/)
- [Swift Package Manager Source Code](https://github.com/swiftlang/swift-package-manager) (Target.swift, ModulesGraph.swift)
