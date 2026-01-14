import Metal
import MetalKit
import CoreGraphics

struct RenderParameters {
    var brightness: Float
    var contrast: Float
    var pixelScale: Float
    var colorDepth: Float
    var algorithm: Int32
    var isGrayscale: Int32
    
    // CHAOS / FX PARAMETERS
    var offsetJitter: Float
    var patternRotation: Float
    
    var errorAmplify: Float
    var errorRandomness: Float
    
    var thresholdNoise: Float
    var waveDistortion: Float
    
    var pixelDisplace: Float
    var turbulence: Float
    var chromaAberration: Float
    
    var bitDepthChaos: Float
    var paletteRandomize: Float
    
    var randomSeed: UInt32
}

final class MetalImageRenderer: Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let pipelineStateFS_Pass1: MTLComputePipelineState?
    private let pipelineStateFS_Pass2: MTLComputePipelineState?
    
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
            // Load FS Kernels
            if let f1 = library.makeFunction(name: "ditherShaderFS_Pass1"),
               let f2 = library.makeFunction(name: "ditherShaderFS_Pass2") {
                self.pipelineStateFS_Pass1 = try device.makeComputePipelineState(function: f1)
                self.pipelineStateFS_Pass2 = try device.makeComputePipelineState(function: f2)
            } else {
                self.pipelineStateFS_Pass1 = nil
                self.pipelineStateFS_Pass2 = nil
            }
        } catch {
            print("Failed to create pipeline state: \(error)")
            return nil
        }
    }
    
    func render(input: CGImage, params: RenderParameters) -> CGImage? {
        return autoreleasepool {
            print("🎨 Metal render started - Image: \(input.width)x\(input.height), Algo: \(params.algorithm)")
            
            let textureLoader = MTKTextureLoader(device: device)
            
            // Load input texture
            guard let inputTexture = try? textureLoader.newTexture(cgImage: input, options: [.origin: MTKTextureLoader.Origin.topLeft]) else {
                print("❌ Failed to create input texture")
                return nil
            }
            
            print("✅ Input texture created: \(inputTexture.width)x\(inputTexture.height)")
            
            // Create output texture
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                  width: inputTexture.width,
                                                                  height: inputTexture.height,
                                                                  mipmapped: false)
            descriptor.usage = [.shaderWrite, .shaderRead]
            
            guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
                print("❌ Failed to create output texture")
                return nil
            }
            
            // Encode command
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("❌ Failed to create command buffer or encoder")
                return nil
            }
            
            var params = params
            
            if params.algorithm == 7, let pipe1 = pipelineStateFS_Pass1, let pipe2 = pipelineStateFS_Pass2 {
                print("🔄 Using Floyd-Steinberg two-pass rendering")
                
                // FLOYD-STEINBERG MULTI-PASS
                
                // Create Error Texture (Float16 or Float32 for precision)
                let errorDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                                         width: inputTexture.width,
                                                                         height: inputTexture.height,
                                                                         mipmapped: false)
                errorDesc.usage = [.shaderWrite, .shaderRead]
                
                // CRITICAL: Use autoreleasepool check for error texture too
                guard let errorTexture = device.makeTexture(descriptor: errorDesc) else {
                     computeEncoder.endEncoding()
                     return nil
                }
                
                // PASS 1: Even Rows
                computeEncoder.setComputePipelineState(pipe1)
                computeEncoder.setTexture(inputTexture, index: 0)
                computeEncoder.setTexture(outputTexture, index: 1)
                computeEncoder.setTexture(errorTexture, index: 2)
                computeEncoder.setBytes(&params, length: MemoryLayout<RenderParameters>.stride, index: 0)
                
                // Dispatch (1, H/2, 1) -> Each thread handles one full row
                let h = (inputTexture.height + 1) / 2
                let threadsPerGrid = MTLSizeMake(1, h, 1)
                let threadsPerThreadgroup = MTLSizeMake(1, min(h, pipe1.maxTotalThreadsPerThreadgroup), 1)
                
                computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                
                // Memory Barrier (Ensure Pass 1 writes are visible to Pass 2)
                computeEncoder.memoryBarrier(scope: .textures)
                
                // PASS 2: Odd Rows
                computeEncoder.setComputePipelineState(pipe2)
                computeEncoder.setTexture(inputTexture, index: 0)
                computeEncoder.setTexture(outputTexture, index: 1)
                computeEncoder.setTexture(errorTexture, index: 2)
                computeEncoder.setBytes(&params, length: MemoryLayout<RenderParameters>.stride, index: 0)
                
                computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                
            } else {
                print("🔄 Using standard dithering algorithm")
                
                // STANDARD ALGORITHMS
                computeEncoder.setComputePipelineState(pipelineState)
                computeEncoder.setTexture(inputTexture, index: 0)
                computeEncoder.setTexture(outputTexture, index: 1)
                computeEncoder.setBytes(&params, length: MemoryLayout<RenderParameters>.stride, index: 0)
                
                let w = pipelineState.threadExecutionWidth
                let h = pipelineState.maxTotalThreadsPerThreadgroup / w
                let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
                let threadsPerGrid = MTLSizeMake(inputTexture.width, inputTexture.height, 1)
                
                computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            }

            computeEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            if let error = commandBuffer.error {
                print("❌ Metal command buffer error: \(error)")
                return nil
            }
            
            print("✅ Metal render completed successfully")
            
            let result = createCGImage(from: outputTexture)
            if result == nil {
                print("❌ Failed to create CGImage from output texture")
            }
            
            return result
        }
    }
    
    private func createCGImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        let length = rowBytes * height
        
        // CRITICAL: Create data buffer that will be copied, not retained
        var bytes = [UInt8](repeating: 0, count: length)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        texture.getBytes(&bytes, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        // Create data with .copy behavior to avoid retaining original buffer
        guard let data = CFDataCreate(nil, bytes, length) else { return nil }
        guard let provider = CGDataProvider(data: data) else { return nil }
        
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
