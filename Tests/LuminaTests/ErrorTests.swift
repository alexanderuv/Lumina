import Testing
@testable import Lumina

/// Tests for error types (LuminaError)
///
/// Verifies:
/// - Error creation with different cases
/// - Error conformance to Error protocol
/// - Sendable conformance for thread safety
/// - CustomStringConvertible descriptions
/// - Pattern matching on error cases

@Suite("Error Handling")
struct ErrorTests {

    // MARK: - Error Creation Tests

    @Suite("Error Creation")
    struct ErrorCreationTests {

        @Test("Create window creation failed error")
        func windowCreationFailed() {
            let error = LuminaError.windowCreationFailed(reason: "Insufficient memory")

            if case .windowCreationFailed(let reason) = error {
                #expect(reason == "Insufficient memory")
            } else {
                Issue.record("Expected .windowCreationFailed error")
            }
        }

        @Test("Create platform error")
        func platformError() {
            let error = LuminaError.platformError(platform: "macOS", operation: "Graphics init", code: 123, message: "Graphics initialization failed")

            if case .platformError(let platform, let operation, let code, let message) = error {
                #expect(platform == "macOS")
                #expect(operation == "Graphics init")
                #expect(code == 123)
                #expect(message == "Graphics initialization failed")
            } else {
                Issue.record("Expected .platformError")
            }
        }

        @Test("Create invalid state error")
        func invalidState() {
            let error = LuminaError.invalidState("Window already closed")

            if case .invalidState(let message) = error {
                #expect(message == "Window already closed")
            } else {
                Issue.record("Expected .invalidState error")
            }
        }

        @Test("Create event loop failed error")
        func eventLoopFailed() {
            let error = LuminaError.eventLoopFailed(reason: "Corrupted event queue")

            if case .eventLoopFailed(let reason) = error {
                #expect(reason == "Corrupted event queue")
            } else {
                Issue.record("Expected .eventLoopFailed error")
            }
        }
    }

    // MARK: - Error Protocol Conformance Tests

    @Suite("Error Protocol Conformance")
    struct ErrorProtocolTests {

        @Test("LuminaError conforms to Error")
        func errorConformance() {
            let error: Error = LuminaError.invalidState("Test")
            #expect(error is LuminaError)
        }

        @Test("Can throw and catch LuminaError")
        func throwAndCatch() throws {
            func throwingFunction() throws {
                throw LuminaError.eventLoopFailed(reason: "Test failure")
            }

            var caughtError: LuminaError?

            do {
                try throwingFunction()
                Issue.record("Should have thrown error")
            } catch let error as LuminaError {
                caughtError = error
            }

            #expect(caughtError != nil)
            if let error = caughtError {
                if case .eventLoopFailed(let reason) = error {
                    #expect(reason == "Test failure")
                } else {
                    Issue.record("Expected .eventLoopFailed error")
                }
            }
        }

        @Test("Can use in Result type")
        func resultType() {
            let successResult: Result<Int, LuminaError> = .success(42)
            let failureResult: Result<Int, LuminaError> = .failure(.invalidState("Test"))

            switch successResult {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
            }

            switch failureResult {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                if case .invalidState(let message) = error {
                    #expect(message == "Test")
                } else {
                    Issue.record("Expected .invalidState error")
                }
            }
        }
    }

    // MARK: - CustomStringConvertible Tests

    @Suite("CustomStringConvertible")
    struct CustomStringDescriptionTests {

        @Test("Window creation failed description")
        func windowCreationDescription() {
            let error = LuminaError.windowCreationFailed(reason: "Invalid size")
            let description = error.description

            #expect(description.contains("Window creation failed"))
            #expect(description.contains("Invalid size"))
        }

        @Test("Platform error description")
        func platformErrorDescription() {
            let error = LuminaError.platformError(platform: "Test", operation: "TestOp", code: 42, message: "Test error")
            let description = error.description

            #expect(description.contains("Test"))  // Platform name
            #expect(description.contains("TestOp"))  // Operation
            #expect(description.contains("42"))  // Error code
            #expect(description.contains("Test error"))  // Message
        }

        @Test("Invalid state description")
        func invalidStateDescription() {
            let error = LuminaError.invalidState("Operation not allowed")
            let description = error.description

            #expect(description.contains("Invalid state"))
            #expect(description.contains("Operation not allowed"))
        }

        @Test("Event loop failed description")
        func eventLoopFailedDescription() {
            let error = LuminaError.eventLoopFailed(reason: "Thread error")
            let description = error.description

            #expect(description.contains("Event loop failed"))
            #expect(description.contains("Thread error"))
        }
    }

    // MARK: - Pattern Matching Tests

    @Suite("Pattern Matching")
    struct PatternMatchingTests {

        @Test("Match window creation error")
        func matchWindowCreation() {
            let error = LuminaError.windowCreationFailed(reason: "Test")
            var matched = false

            switch error {
            case .windowCreationFailed:
                matched = true
            default:
                break
            }

            #expect(matched)
        }

        @Test("Match platform error")
        func matchPlatformError() {
            let error = LuminaError.platformError(platform: "Test", operation: "TestOp", code: 100, message: "Test")
            var matched = false

            switch error {
            case .platformError(_, _, let code, _):
                matched = true
                #expect(code == 100)
            default:
                break
            }

            #expect(matched)
        }

        @Test("Match with guard let")
        func matchWithGuard() {
            let error: Error = LuminaError.invalidState("Test")

            guard let luminaError = error as? LuminaError else {
                Issue.record("Expected LuminaError")
                return
            }

            if case .invalidState(let message) = luminaError {
                #expect(message == "Test")
            } else {
                Issue.record("Expected .invalidState")
            }
        }
    }

    // MARK: - Sendable Conformance Tests

    @Suite("Sendable Conformance")
    struct SendableTests {

        @Test("Can send across actor boundaries")
        func sendableAcrossActors() async {
            actor ErrorHandler {
                var lastError: LuminaError?

                func recordError(_ error: LuminaError) {
                    lastError = error
                }

                func getLastError() -> LuminaError? {
                    lastError
                }
            }

            let handler = ErrorHandler()
            let error = LuminaError.windowCreationFailed(reason: "Test from main")

            // Send error to actor (proves Sendable conformance)
            await handler.recordError(error)

            let retrieved = await handler.getLastError()
            #expect(retrieved != nil)

            if let err = retrieved {
                if case .windowCreationFailed(let reason) = err {
                    #expect(reason == "Test from main")
                } else {
                    Issue.record("Expected .windowCreationFailed")
                }
            }
        }

        @Test("Can use in Task")
        func useInTask() async {
            let error = LuminaError.platformError(platform: "Test", operation: "AsyncOp", code: 42, message: "Async test")

            let taskError = await Task {
                error  // Capture and return error
            }.value

            if case .platformError(_, _, let code, let message) = taskError {
                #expect(code == 42)
                #expect(message == "Async test")
            } else {
                Issue.record("Expected .platformError")
            }
        }
    }

    // MARK: - Real-world Usage Tests

    @Suite("Real-world Usage")
    struct UsageTests {

        @Test("Error handling in Result chain")
        func resultChain() {
            func createWindow() -> Result<String, LuminaError> {
                .failure(.windowCreationFailed(reason: "No memory"))
            }

            func showWindow(_ windowId: String) -> Result<Void, LuminaError> {
                .success(())
            }

            let result = createWindow()
                .flatMap { windowId in
                    showWindow(windowId)
                }

            switch result {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                if case .windowCreationFailed(let reason) = error {
                    #expect(reason == "No memory")
                } else {
                    Issue.record("Expected .windowCreationFailed")
                }
            }
        }

        @Test("Multiple error types in do-catch")
        func multipleCatch() {
            enum LocalError: Error {
                case localIssue
            }

            func mixed() throws {
                throw LuminaError.eventLoopFailed(reason: "Test")
            }

            var luminaErrorCaught = false

            do {
                try mixed()
            } catch let error as LuminaError {
                luminaErrorCaught = true
                if case .eventLoopFailed = error {
                    // Expected
                } else {
                    Issue.record("Expected .eventLoopFailed")
                }
            } catch {
                Issue.record("Expected LuminaError")
            }

            #expect(luminaErrorCaught)
        }
    }
}
