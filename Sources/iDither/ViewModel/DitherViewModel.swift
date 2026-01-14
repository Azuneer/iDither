import SwiftUI
import Combine

enum DitherAlgorithm: Int, CaseIterable, Identifiable {
    case none = 0
    case bayer8x8 = 1
    case bayer4x4 = 2
    
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .none: return "No Dither"
        case .bayer8x8: return "Bayer 8x8"
        case .bayer4x4: return "Bayer 4x4"
        }
    }
}

@MainActor
@Observable
class DitherViewModel {
    var inputImage: CGImage?
    var processedImage: CGImage?
    
    var brightness: Float = 0.0
    var contrast: Float = 1.0
    var pixelScale: Float = 1.0
    var selectedAlgorithm: DitherAlgorithm = .none
    var isGrayscale: Bool = false
    
    private let renderer: MetalImageRenderer?
    private var processingTask: Task<Void, Never>?
    
    init() {
        self.renderer = MetalImageRenderer()
    }
    
    func load(url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("Failed to load image")
            return
        }
        
        self.inputImage = cgImage
        processImage()
    }
    
    func processImage() {
        guard let inputImage = inputImage, let renderer = renderer else { return }
        
        processingTask?.cancel()
        
        let params = RenderParameters(
            brightness: brightness,
            contrast: contrast,
            pixelScale: pixelScale,
            algorithm: Int32(selectedAlgorithm.rawValue),
            isGrayscale: isGrayscale ? 1 : 0
        )
        
        processingTask = Task.detached(priority: .userInitiated) { [inputImage, renderer, params] in
            if let result = renderer.render(input: inputImage, params: params) {
                await MainActor.run {
                    self.processedImage = result
                }
            }
        }
    }
    
    func exportResult(to url: URL) {
        guard let processedImage = processedImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return
        }
        
        CGImageDestinationAddImage(destination, processedImage, nil)
        CGImageDestinationFinalize(destination)
    }
}
