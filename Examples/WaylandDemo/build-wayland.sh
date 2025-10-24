#!/bin/bash
# Build and run WaylandDemo with Wayland support

set -e

echo "Building WaylandDemo with Wayland trait..."
echo ""

# Build with Wayland trait
swift build --traits Wayland

echo ""
echo "Build complete! Running WaylandDemo..."
echo ""

# Run the example
swift run --traits Wayland
