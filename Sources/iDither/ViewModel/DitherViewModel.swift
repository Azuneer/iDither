import SwiftUI
import CoreGraphics
import ImageIO

enum DitherAlgorithm: Int, CaseIterable, Identifiable {
    case noDither = 0
    case bayer8x8 = 1
    case bayer4x4 = 2
    
    var id: Int { rawValue }
    
    var name: String {
        switch self {
        case .noDither: return "No Dither"
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
    var inputImageId: UUID = UUID() // Unique ID to track when a NEW file is loaded
    
    // Parameters
    var brightness: Double = 0.0
    var contrast: Double = 1.0
    var pixelScale: Double = 4.0
    var selectedAlgorithm: DitherAlgorithm = .bayer8x8
    var isGrayscale: Bool = false
    
    private let renderer = MetalImageRenderer()
    private var renderTask: Task<Void, Never>?
    
    init() {}
    
    func load(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("Failed to load image from \(url)")
            return
        }
        
        self.inputImage = cgImage
        self.inputImageId = UUID() // Signal that a new image has been loaded
        self.processImage()
    }
    
    func processImage() {
        guard let input = inputImage, let renderer = renderer else { return }
        
        // Cancel previous task to prevent UI freezing and Metal overload
        renderTask?.cancel()
        
        let params = RenderParameters(
            brightness: Float(brightness),
            contrast: Float(contrast),
            pixelScale: Float(pixelScale),
            algorithm: Int32(selectedAlgorithm.rawValue),
            isGrayscale: isGrayscale ? 1 : 0
        )
        
        renderTask = Task.detached(priority: .userInitiated) { [input, renderer, params] in
            if Task.isCancelled { return }
            
            let result = renderer.render(input: input, params: params)
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                self.processedImage = result
            }
        }
    }
    
    func exportResult(to url: URL) {
        guard let image = processedImage else { return }
        
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            print("Failed to create image destination")
            return
        }
        
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
