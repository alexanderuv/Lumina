#!/bin/bash
# Build and run WaylandDemo with Wayland support

set -e

# Check if Wayland protocol files exist
PROTOCOL_HEADER="../../Sources/CInterop/CWaylandClient/include/xdg-shell-client-protocol.h"

if [ ! -f "$PROTOCOL_HEADER" ]; then
    echo "Wayland protocol files not found. Generating them..."
    echo ""
    swift package --package-path ../.. plugin generate-wayland-protocols
    echo ""
fi

echo "Building WaylandDemo with Wayland trait..."
echo ""

# Build with Wayland trait
swift build --traits Wayland

echo ""
echo "Build complete! Running WaylandDemo..."
echo ""

# Run the example
swift run --traits Wayland
