echo "Building N-Body Gravity Simulator..."
swiftc -O -framework Metal -framework MetalKit -framework Cocoa Sources/*.swift -o NBodySimulator
if [ $? -eq 0 ]; then
    echo "✓ Build successful! Run with: ./NBodySimulator"
else
    echo "✗ Build failed"
    exit 1
fi