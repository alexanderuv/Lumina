#!/bin/bash
# Build and run WaylandDemo with Wayland support

set -e

echo "Building WaylandDemo with LUMINA_WAYLAND support..."
echo ""

# Build with LUMINA_WAYLAND flag
swift build -Xswiftc -DLUMINA_WAYLAND

echo ""
echo "Build complete! Running WaylandDemo..."
echo ""

# Run the example
swift run -Xswiftc -DLUMINA_WAYLAND
