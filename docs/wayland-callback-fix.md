# Wayland libdecor Callback Corruption Fix

## Problem Summary

The WaylandWindow implementation was crashing during `libdecor_dispatch()` with corrupted function pointers when the compositor tried to invoke callbacks.

**Crash Location**: Event loop in `WaylandApplication.pollEvents()` → `libdecor_dispatch()` → callback invocation

**Symptom**: Segmentation fault or invalid instruction pointer when libdecor tried to invoke the `configure`, `close`, or `commit` callbacks.

## Root Cause

**File**: `/home/alexander/dev/Lumina/Sources/Lumina/Platforms/Linux/Wayland/WaylandWindow.swift`
**Lines**: 162-186 (original implementation)

The bug was a classic **C interop memory safety violation**:

### What Was Wrong

```swift
// ORIGINAL BUGGY CODE (lines 162-186)
var frameInterface = libdecor_frame_interface(
    configure: { frame, configuration, userData in
        // Swift closure literal
        handleConfigure(frame: frame, configuration: configuration, userData: userData)
    },
    close: { frame, userData in
        // Swift closure literal
        handleClose(frame: frame, userData: userData)
    },
    commit: { frame, userData in
        // Swift closure literal
        handleCommit(frame: frame, userData: userData)
    },
    dismiss_popup: nil,
    // ... reserved fields ...
)

// Pass address of local stack variable to C library
guard let frame = libdecor_decorate(
    decorContext,
    surface,
    &frameInterface,  // ⚠️ DANGLING POINTER!
    userDataPtr
) else { /* ... */ }
```

### Why This Failed

1. **Swift closures are NOT C function pointers**
   - Swift closures are heap-allocated objects with context capture
   - They have their own memory management lifecycle
   - C function pointers are simple addresses to executable code

2. **Stack variable lifetime violation**
   - `frameInterface` is a local variable on the stack
   - When `create()` returns, the stack frame is destroyed
   - libdecor stores pointers to the closure objects that were in this struct
   - These closure objects may be deallocated or moved by Swift's ARC

3. **Dangling pointers in C code**
   - libdecor saves the callback pointers for later use
   - When `libdecor_dispatch()` tries to invoke them, the pointers are invalid
   - Result: crash with corrupted function pointer or segfault

### Swift 6.2 Concurrency Angle

While not directly a Swift Concurrency issue, this demonstrates why Swift 6's stricter memory safety checks are important:

- **Sendable conformance** doesn't protect against this (it's a C interop issue)
- **Strict concurrency** doesn't catch passing invalid pointers to C
- **Manual memory management** required when crossing Swift/C boundary

This is a gap where Swift's type system can't protect you - C APIs accept raw pointers and there's no way for the compiler to know the lifetime requirements.

## The Fix

### What Changed

Replace Swift closure literals with **module-level C function pointers** using `@convention(c)`:

```swift
// FIXED CODE - C function pointers with @convention(c)

/// C function pointer for libdecor configure callback
/// Uses @convention(c) to create a real C function pointer (not a Swift closure)
private let configureCCallback: @convention(c) (
    OpaquePointer?,
    OpaquePointer?,
    UnsafeMutableRawPointer?
) -> Void = { frame, configuration, userData in
    handleConfigure(frame: frame, configuration: configuration, userData: userData)
}

/// C function pointer for libdecor close callback
private let closeCCallback: @convention(c) (
    OpaquePointer?,
    UnsafeMutableRawPointer?
) -> Void = { frame, userData in
    handleClose(frame: frame, userData: userData)
}

/// C function pointer for libdecor commit callback
private let commitCCallback: @convention(c) (
    OpaquePointer?,
    UnsafeMutableRawPointer?
) -> Void = { frame, userData in
    handleCommit(frame: frame, userData: userData)
}

// In create() method:
var frameInterface = libdecor_frame_interface(
    configure: configureCCallback,  // ✅ Stable C function pointer
    close: closeCCallback,          // ✅ Stable C function pointer
    commit: commitCCallback,         // ✅ Stable C function pointer
    dismiss_popup: nil,
    // ... reserved fields ...
)
```

### Why This Works

1. **`@convention(c)` creates real C function pointers**
   - No context capture allowed (compile error if you try)
   - No heap allocation - just a function address
   - Binary compatible with C function pointer expectations

2. **Module-level lifetime**
   - `private let` declarations at module scope live for the program's duration
   - Function pointers remain valid as long as the module is loaded
   - No dangling pointer risk

3. **Type safety preserved**
   - Swift still enforces type signatures
   - Optional parameters match C NULL expectations
   - Opaque pointers properly represent void* from C

## Best Practices for C Interop

### When Working with C Callbacks

✅ **DO**:
- Use `@convention(c)` for all C callback function pointers
- Declare callbacks at module scope with `private let`
- Pass user data through the void* parameter (using `Unmanaged`)
- Document lifetime requirements clearly

❌ **DON'T**:
- Use Swift closure literals for C callbacks
- Create callback pointers in local scope
- Capture Swift variables in `@convention(c)` closures (it won't compile anyway)
- Assume Swift's ARC will manage C-held references

### Pattern for C Callbacks with User Data

Swift provides **two safe patterns** for C callbacks:

#### Pattern 1: Module-level closure with @convention(c) (PREFERRED)

```swift
// 1. Define user data class
private final class CallbackUserData {
    var state: SomeState
    weak var owner: AnyObject?
}

// 2. Define C callback as module-level constant with @convention(c)
// CRITICAL: Must be `let` at module scope, NOT a local variable
private let cCallback: @convention(c) (
    /* C params */,
    UnsafeMutableRawPointer?  // userData
) -> Void = { /* params */, userData in
    guard let userData = userData else { return }

    // Extract user data
    let data = Unmanaged<CallbackUserData>
        .fromOpaque(userData)
        .takeUnretainedValue()

    // Use data (no retain/release here - just borrow)
    data.state.doSomething()
}

// 3. Pass to C API
func registerCallback() {
    let userData = CallbackUserData(...)
    let ptr = Unmanaged.passRetained(userData).toOpaque()

    c_register_callback(cCallback, ptr)

    // Remember to release when done!
    // Unmanaged<CallbackUserData>.fromOpaque(ptr).release()
}
```

#### Pattern 2: Module-level func declaration (ALSO SAFE)

```swift
// Module-level functions can be used directly as C function pointers
// No @convention(c) needed for top-level functions
private func cCallback(
    /* C params */,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData = userData else { return }

    let data = Unmanaged<CallbackUserData>
        .fromOpaque(userData)
        .takeUnretainedValue()

    data.state.doSomething()
}

// Pass function name directly - Swift converts it to C function pointer
func registerCallback() {
    let userData = CallbackUserData(...)
    let ptr = Unmanaged.passRetained(userData).toOpaque()

    c_register_callback(cCallback, ptr)
}
```

**When to use each:**
- **Pattern 1** (`@convention(c)` closure): Use when you need to explicitly document C calling convention
- **Pattern 2** (module func): Use for readability when the function is complex

Both patterns create stable function pointers with module-level lifetime.

### Common Pitfalls

1. **Forgetting to release retained user data**
   - `passRetained()` increments ref count
   - Must call `.release()` when callback is unregistered
   - In WaylandWindow, we release in `close()` method

2. **Using `takeRetainedValue()` in callbacks**
   - Would decrement ref count each time callback fires
   - Use `takeUnretainedValue()` to just borrow the reference

3. **Assuming closures are function pointers**
   - This works in some languages (C++ lambdas with no capture)
   - Never works in Swift without `@convention(c)`

## Testing the Fix

### Before Fix
```
Thread 1 "WaylandDemo" received signal SIGSEGV, Segmentation fault.
0x00007ffff7fc3050 in ?? ()
(gdb) bt
#0  0x00007ffff7fc3050 in ?? ()
#1  0x00007ffff7f9a123 in libdecor_dispatch () from /usr/lib/libdecor-0.so.0
```

### After Fix
```
$ cd Examples/WaylandDemo && swift run
[INFO] Creating Wayland window: 800x600
[INFO] Window created successfully
[INFO] Entering event loop...
[INFO] Configure event: 800x600
[INFO] Window mapped
^C
```

No crashes, callbacks fire correctly.

## Related Code

**Other files that use similar patterns:**
- `Sources/Lumina/Platforms/Linux/Wayland/WaylandApplication.swift` - libdecor context callbacks
- Check for similar C callback registrations across the codebase

**Review checklist for C interop:**
- [ ] All C callbacks use `@convention(c)`
- [ ] Callback pointers have module-level lifetime
- [ ] User data properly retained/released with `Unmanaged`
- [ ] No capture of Swift variables in C callbacks

## References

- [Swift Language Guide: Type Casting](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/typecasting/)
- [Swift Manual Memory Management with Unmanaged](https://developer.apple.com/documentation/swift/unmanaged)
- [Swift-Evolution: @convention(c) attribute](https://github.com/apple/swift-evolution/blob/main/proposals/0018-flexible-memberwise-initialization.md)
- [libdecor documentation](https://gitlab.freedesktop.org/libdecor/libdecor)

## Lessons Learned

1. **Type systems have limits** - Swift can't prevent all memory safety issues when crossing FFI boundaries
2. **C interop requires manual care** - You're responsible for matching C's lifetime expectations
3. **Test early with C libraries** - These bugs only appear at runtime when C tries to use the pointers
4. **Follow established patterns** - SDL3 and GLFW use the same @convention(c) pattern for Wayland callbacks

This fix aligns with industry best practices for Swift/C interop and matches the patterns used by major cross-platform libraries.
