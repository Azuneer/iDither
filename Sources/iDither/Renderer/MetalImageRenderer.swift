import Metal
import MetalKit
import CoreGraphics

struct RenderParameters {
    var brightness: Float
    var contrast: Float
    var pixelScale: Float
    var algorithm: Int32 // 0: None, 1: Bayer 8x8, 2: Bayer 4x4
    var isGrayscale: Int32 // 0: false, 1: true
}

final class MetalImageRenderer: Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: Bundle.module),
              let function = library.makeFunction(name: "ditherShader") else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        do {
            self.pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            print("Failed to create pipeline state: \(error)")
            return nil
        }
    }
    
    func render(input: CGImage, params: RenderParameters) -> CGImage? {
        let textureLoader = MTKTextureLoader(device: device)
        
        // Load input texture
        guard let inputTexture = try? textureLoader.newTexture(cgImage: input, options: [.origin: MTKTextureLoader.Origin.topLeft]) else {
            return nil
        }
        
        // Create output texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                              width: inputTexture.width,
                                                              height: inputTexture.height,
                                                              mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        
        // Encode command
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(inputTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)
        
        var params = params
        computeEncoder.setBytes(&params, length: MemoryLayout<RenderParameters>.stride, index: 0)
        
        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(inputTexture.width, inputTexture.height, 1)
        
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Convert back to CGImage (for simplicity in this iteration, though MTKView is better for display)
        // We will use a helper to convert MTLTexture to CGImage
        return createCGImage(from: outputTexture)
    }
    
    private func createCGImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        let length = rowBytes * height
        
        var bytes = [UInt8](repeating: 0, count: length)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        texture.getBytes(&bytes, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let provider = CGDataProvider(data: Data(bytes: bytes, count: length) as CFData) else { return nil }
        
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: rowBytes,
                       space: colorSpace,
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
