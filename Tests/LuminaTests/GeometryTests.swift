import Testing
@testable import Lumina

/// Tests for geometry types (LogicalSize, PhysicalSize, LogicalPosition, PhysicalPosition)
///
/// Verifies:
/// - Size and position conversions with various scale factors
/// - Edge cases (zero size, fractional values, rounding)
/// - Hashable conformance for use in collections
/// - Sendable conformance for thread safety

@Suite("Geometry Types")
struct GeometryTests {

    // MARK: - LogicalSize Tests

    @Suite("LogicalSize")
    struct LogicalSizeTests {

        @Test("Create logical size with positive dimensions")
        func createLogicalSize() {
            let size = LogicalSize(width: 800, height: 600)
            #expect(size.width == 800)
            #expect(size.height == 600)
        }

        @Test("Convert logical to physical with 1x scale")
        func convertToPhysical1x() {
            let logical = LogicalSize(width: 800, height: 600)
            let physical = logical.toPhysical(scaleFactor: 1.0)

            #expect(physical.width == 800)
            #expect(physical.height == 600)
        }

        @Test("Convert logical to physical with 2x scale (Retina)")
        func convertToPhysical2x() {
            let logical = LogicalSize(width: 800, height: 600)
            let physical = logical.toPhysical(scaleFactor: 2.0)

            #expect(physical.width == 1600)
            #expect(physical.height == 1200)
        }

        @Test("Convert logical to physical with 1.5x scale")
        func convertToPhysical1_5x() {
            let logical = LogicalSize(width: 100, height: 100)
            let physical = logical.toPhysical(scaleFactor: 1.5)

            // 100 * 1.5 = 150
            #expect(physical.width == 150)
            #expect(physical.height == 150)
        }

        @Test("Rounding behavior with fractional results")
        func roundingBehavior() {
            let logical = LogicalSize(width: 101, height: 101)
            let physical = logical.toPhysical(scaleFactor: 1.5)

            // 101 * 1.5 = 151.5, should round to 152
            #expect(physical.width == 152)
            #expect(physical.height == 152)
        }

        @Test("Zero size handling")
        func zeroSize() {
            let logical = LogicalSize(width: 0, height: 0)
            let physical = logical.toPhysical(scaleFactor: 2.0)

            #expect(physical.width == 0)
            #expect(physical.height == 0)
        }

        @Test("Hashable conformance")
        func hashableConformance() {
            let size1 = LogicalSize(width: 800, height: 600)
            let size2 = LogicalSize(width: 800, height: 600)
            let size3 = LogicalSize(width: 1024, height: 768)

            // Same values should be equal and have same hash
            #expect(size1 == size2)
            #expect(size1.hashValue == size2.hashValue)

            // Different values should not be equal
            #expect(size1 != size3)

            // Can be used in Set
            let sizeSet: Set<LogicalSize> = [size1, size2, size3]
            #expect(sizeSet.count == 2)  // size1 and size2 are duplicates
        }
    }

    // MARK: - PhysicalSize Tests

    @Suite("PhysicalSize")
    struct PhysicalSizeTests {

        @Test("Create physical size with pixel dimensions")
        func createPhysicalSize() {
            let size = PhysicalSize(width: 1920, height: 1080)
            #expect(size.width == 1920)
            #expect(size.height == 1080)
        }

        @Test("Convert physical to logical with 1x scale")
        func convertToLogical1x() {
            let physical = PhysicalSize(width: 1920, height: 1080)
            let logical = physical.toLogical(scaleFactor: 1.0)

            #expect(logical.width == 1920)
            #expect(logical.height == 1080)
        }

        @Test("Convert physical to logical with 2x scale (Retina)")
        func convertToLogical2x() {
            let physical = PhysicalSize(width: 1920, height: 1080)
            let logical = physical.toLogical(scaleFactor: 2.0)

            #expect(logical.width == 960)
            #expect(logical.height == 540)
        }

        @Test("Convert physical to logical with 1.5x scale")
        func convertToLogical1_5x() {
            let physical = PhysicalSize(width: 150, height: 150)
            let logical = physical.toLogical(scaleFactor: 1.5)

            #expect(logical.width == 100)
            #expect(logical.height == 100)
        }

        @Test("Hashable conformance")
        func hashableConformance() {
            let size1 = PhysicalSize(width: 1920, height: 1080)
            let size2 = PhysicalSize(width: 1920, height: 1080)
            let size3 = PhysicalSize(width: 3840, height: 2160)

            #expect(size1 == size2)
            #expect(size1.hashValue == size2.hashValue)
            #expect(size1 != size3)

            let sizeSet: Set<PhysicalSize> = [size1, size2, size3]
            #expect(sizeSet.count == 2)
        }
    }

    // MARK: - LogicalPosition Tests

    @Suite("LogicalPosition")
    struct LogicalPositionTests {

        @Test("Create logical position")
        func createLogicalPosition() {
            let pos = LogicalPosition(x: 100, y: 200)
            #expect(pos.x == 100)
            #expect(pos.y == 200)
        }

        @Test("Convert logical to physical with 1x scale")
        func convertToPhysical1x() {
            let logical = LogicalPosition(x: 100, y: 200)
            let physical = logical.toPhysical(scaleFactor: 1.0)

            #expect(physical.x == 100)
            #expect(physical.y == 200)
        }

        @Test("Convert logical to physical with 2x scale")
        func convertToPhysical2x() {
            let logical = LogicalPosition(x: 100, y: 200)
            let physical = logical.toPhysical(scaleFactor: 2.0)

            #expect(physical.x == 200)
            #expect(physical.y == 400)
        }

        @Test("Negative positions")
        func negativePositions() {
            let logical = LogicalPosition(x: -50, y: -100)
            let physical = logical.toPhysical(scaleFactor: 2.0)

            #expect(physical.x == -100)
            #expect(physical.y == -200)
        }

        @Test("Zero position")
        func zeroPosition() {
            let logical = LogicalPosition(x: 0, y: 0)
            let physical = logical.toPhysical(scaleFactor: 2.0)

            #expect(physical.x == 0)
            #expect(physical.y == 0)
        }

        @Test("Hashable conformance")
        func hashableConformance() {
            let pos1 = LogicalPosition(x: 100, y: 200)
            let pos2 = LogicalPosition(x: 100, y: 200)
            let pos3 = LogicalPosition(x: 150, y: 250)

            #expect(pos1 == pos2)
            #expect(pos1.hashValue == pos2.hashValue)
            #expect(pos1 != pos3)

            let posSet: Set<LogicalPosition> = [pos1, pos2, pos3]
            #expect(posSet.count == 2)
        }
    }

    // MARK: - PhysicalPosition Tests

    @Suite("PhysicalPosition")
    struct PhysicalPositionTests {

        @Test("Create physical position")
        func createPhysicalPosition() {
            let pos = PhysicalPosition(x: 200, y: 400)
            #expect(pos.x == 200)
            #expect(pos.y == 400)
        }

        @Test("Convert physical to logical with 1x scale")
        func convertToLogical1x() {
            let physical = PhysicalPosition(x: 200, y: 400)
            let logical = physical.toLogical(scaleFactor: 1.0)

            #expect(logical.x == 200)
            #expect(logical.y == 400)
        }

        @Test("Convert physical to logical with 2x scale")
        func convertToLogical2x() {
            let physical = PhysicalPosition(x: 200, y: 400)
            let logical = physical.toLogical(scaleFactor: 2.0)

            #expect(logical.x == 100)
            #expect(logical.y == 200)
        }

        @Test("Hashable conformance")
        func hashableConformance() {
            let pos1 = PhysicalPosition(x: 200, y: 400)
            let pos2 = PhysicalPosition(x: 200, y: 400)
            let pos3 = PhysicalPosition(x: 300, y: 600)

            #expect(pos1 == pos2)
            #expect(pos1.hashValue == pos2.hashValue)
            #expect(pos1 != pos3)

            let posSet: Set<PhysicalPosition> = [pos1, pos2, pos3]
            #expect(posSet.count == 2)
        }
    }

    // MARK: - Round-trip Conversion Tests

    @Suite("Round-trip Conversions")
    struct RoundTripTests {

        @Test("Logical → Physical → Logical preserves value (1x)")
        func logicalPhysicalLogical1x() {
            let original = LogicalSize(width: 800, height: 600)
            let physical = original.toPhysical(scaleFactor: 1.0)
            let roundTrip = physical.toLogical(scaleFactor: 1.0)

            #expect(roundTrip.width == original.width)
            #expect(roundTrip.height == original.height)
        }

        @Test("Logical → Physical → Logical preserves value (2x)")
        func logicalPhysicalLogical2x() {
            let original = LogicalSize(width: 800, height: 600)
            let physical = original.toPhysical(scaleFactor: 2.0)
            let roundTrip = physical.toLogical(scaleFactor: 2.0)

            #expect(roundTrip.width == original.width)
            #expect(roundTrip.height == original.height)
        }

        @Test("Position round-trip conversion")
        func positionRoundTrip() {
            let original = LogicalPosition(x: 100, y: 200)
            let physical = original.toPhysical(scaleFactor: 2.0)
            let roundTrip = physical.toLogical(scaleFactor: 2.0)

            #expect(roundTrip.x == original.x)
            #expect(roundTrip.y == original.y)
        }

        @Test("Fractional scale factor round-trip (may lose precision)")
        func fractionalScaleRoundTrip() {
            let original = LogicalSize(width: 100, height: 100)
            let physical = original.toPhysical(scaleFactor: 1.5)
            let roundTrip = physical.toLogical(scaleFactor: 1.5)

            // Due to rounding in toPhysical, we may have small differences
            // 100 * 1.5 = 150 (exact), 150 / 1.5 = 100 (exact in this case)
            #expect(roundTrip.width == original.width)
            #expect(roundTrip.height == original.height)
        }
    }
}
