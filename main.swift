import Cocoa
import MetalKit

struct Body {
    var position: simd_float2
    var velocity: simd_float2
    var mass: Float
    var color: simd_float3
    var padding: Float = 0
}

@main
class NBodyApp {
    static func main() {
        let app = NSApplication.shared
        app.delegate = AppDelegate()
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1400, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "N-Body Gravity Simulator - Metal GPU"
        window.center()
        window.contentView = NBodyView(frame: window.contentView!.bounds)
        window.makeKeyAndOrderFront(nil)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

class NBodyView: MTKView {
    var commandQueue: MTLCommandQueue!
    var forcesPipeline: MTLComputePipelineState!
    var positionsPipeline: MTLComputePipelineState!
    var renderPipeline: MTLComputePipelineState!
    var clearPipeline: MTLComputePipelineState!
    
    var bodiesBuffer: MTLBuffer!
    var renderTexture: MTLTexture!
    
    var numBodies: UInt32 = 10000
    var deltaTime: Float = 0.01
    var softening: Float = 0.001
    var particleSize: Float = 0.005
    var isPaused = false
    var showTrails = true
    
    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        setup()
    }
    
    required init(coder: NSCoder) { fatalError() }
    
    func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal not supported") }
        
        self.device = device
        self.framebufferOnly = false
        self.preferredFramesPerSecond = 60
        commandQueue = device.makeCommandQueue()!
        
        let source = try! String(contentsOfFile: "../Shaders.metal")
        let library = try! device.makeLibrary(source: source, options: nil)
        
        forcesPipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "computeForces")!)
        positionsPipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "updatePositions")!)
        renderPipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "renderBodies")!)
        clearPipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "clearTexture")!)
        
        setupBodies()
        setupTexture()
        
        self.delegate = self
        
        print("✓ N-Body Simulator initialized")
        print("  Bodies: \\(numBodies)")
        print("  Space - Pause, R - Reset, 1-5 - Presets")
    }
    
    func setupTexture() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 2048,
            height: 2048,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        renderTexture = device!.makeTexture(descriptor: desc)!
    }
    
    func setupBodies(preset: Int = 2) {
        var bodies = [Body]()
        
        switch preset {
        case 1: // Binary star
            for _ in 0..<Int(numBodies/2) {
                let angle = Float.random(in: 0..<2*Float.pi)
                let radius = Float.random(in: 0.0...0.3)
                let pos = simd_float2(cos(angle) * radius - 0.5, sin(angle) * radius)
                let vel = simd_float2(-sin(angle), cos(angle)) * radius * 2.0
                bodies.append(Body(
                    position: pos,
                    velocity: vel,
                    mass: 0.01,
                    color: simd_float3(1.0, 0.3, 0.3)
                ))
            }
            for _ in 0..<Int(numBodies/2) {
                let angle = Float.random(in: 0..<2*Float.pi)
                let radius = Float.random(in: 0.0...0.3)
                let pos = simd_float2(cos(angle) * radius + 0.5, sin(angle) * radius)
                let vel = simd_float2(-sin(angle), cos(angle)) * radius * 2.0
                bodies.append(Body(
                    position: pos,
                    velocity: vel,
                    mass: 0.01,
                    color: simd_float3(0.3, 0.3, 1.0)
                ))
            }
        case 2: // Galaxy collision
            for _ in 0..<Int(numBodies) {
                let angle = Float.random(in: 0..<2*Float.pi)
                let radius = Float.random(in: 0.0...0.4)
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                let galaxy = Int.random(in: 0...1)
                let offset: Float = galaxy == 0 ? -0.4 : 0.4
                
                bodies.append(Body(
                    position: simd_float2(x + offset, y),
                    velocity: simd_float2(-y, x) * radius + simd_float2(galaxy == 0 ? 0.1 : -0.1, 0),
                    mass: 0.01,
                    color: galaxy == 0 ? simd_float3(1, 0.5, 0) : simd_float3(0, 0.5, 1)
                ))
            }
        default: // Random cloud
            for _ in 0..<Int(numBodies) {
                bodies.append(Body(
                    position: simd_float2(Float.random(in: -0.8...0.8), Float.random(in: -0.8...0.8)),
                    velocity: simd_float2(Float.random(in: -0.1...0.1), Float.random(in: -0.1...0.1)),
                    mass: Float.random(in: 0.005...0.02),
                    color: simd_float3(Float.random(in: 0.5...1), Float.random(in: 0.3...0.7), Float.random(in: 0.3...1))
                ))
            }
        }
        
        bodiesBuffer = device!.makeBuffer(bytes: &bodies, length: MemoryLayout<Body>.stride * bodies.count, options: .storageModeShared)
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case " ": isPaused.toggle(); print(isPaused ? "⏸" : "▶")
        case "r", "R": setupBodies(preset: 2); print("🔄 Reset")
        case "1": setupBodies(preset: 1); print("Binary Star")
        case "2": setupBodies(preset: 2); print("Galaxy Collision")
        case "3": setupBodies(preset: 3); print("Random Cloud")
        case "g", "G": showTrails.toggle(); print("Trails: \\(showTrails)")
        default: super.keyDown(with: event)
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
}

extension NBodyView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Clear/fade
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(clearPipeline)
            encoder.setTexture(renderTexture, index: 0)
            var clearColor = simd_float4(0.0, 0.0, 0.05, 1.0)
            encoder.setBytes(&clearColor, length: MemoryLayout<simd_float4>.size, index: 0)
            let gridSize = MTLSize(width: renderTexture.width, height: renderTexture.height, depth: 1)
            let threadSize = MTLSize(width: 16, height: 16, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadSize)
            encoder.endEncoding()
        }
        
        // Update physics
        if !isPaused {
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(forcesPipeline)
                encoder.setBuffer(bodiesBuffer, offset: 0, index: 0)
                encoder.setBytes(&numBodies, length: MemoryLayout<UInt32>.size, index: 1)
                encoder.setBytes(&deltaTime, length: MemoryLayout<Float>.size, index: 2)
                encoder.setBytes(&softening, length: MemoryLayout<Float>.size, index: 3)
                encoder.dispatchThreads(MTLSize(width: Int(numBodies), height: 1, depth: 1),
                                      threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
                encoder.endEncoding()
            }
            
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(positionsPipeline)
                encoder.setBuffer(bodiesBuffer, offset: 0, index: 0)
                encoder.setBytes(&numBodies, length: MemoryLayout<UInt32>.size, index: 1)
                encoder.setBytes(&deltaTime, length: MemoryLayout<Float>.size, index: 2)
                encoder.dispatchThreads(MTLSize(width: Int(numBodies), height: 1, depth: 1),
                                      threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
                encoder.endEncoding()
            }
        }
        
        // Render
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(renderPipeline)
            encoder.setTexture(renderTexture, index: 0)
            encoder.setBuffer(bodiesBuffer, offset: 0, index: 0)
            encoder.setBytes(&numBodies, length: MemoryLayout<UInt32>.size, index: 1)
            encoder.setBytes(&particleSize, length: MemoryLayout<Float>.size, index: 2)
            let gridSize = MTLSize(width: renderTexture.width, height: renderTexture.height, depth: 1)
            let threadSize = MTLSize(width: 16, height: 16, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadSize)
            encoder.endEncoding()
        }
        
        // Blit to screen
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(from: renderTexture,
                           sourceSlice: 0, sourceLevel: 0,
                           sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                           sourceSize: MTLSize(width: renderTexture.width, height: renderTexture.height, depth: 1),
                           to: drawable.texture,
                           destinationSlice: 0, destinationLevel: 0,
                           destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blitEncoder.endEncoding()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}