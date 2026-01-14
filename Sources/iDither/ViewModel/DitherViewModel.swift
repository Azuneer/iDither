import SwiftUI
import CoreGraphics
import ImageIO
import AppKit
import UniformTypeIdentifiers

enum DitherAlgorithm: Int, CaseIterable, Identifiable {
    case noDither = 0
    case bayer2x2 = 1
    case bayer4x4 = 2
    case bayer8x8 = 3
    case cluster4x4 = 4
    case cluster8x8 = 5
    case blueNoise = 6
    case floydSteinberg = 7
    
    var id: Int { rawValue }
    
    var name: String {
        switch self {
        case .noDither: return "No Dither"
        case .bayer2x2: return "Bayer 2x2 (Retro)"
        case .bayer4x4: return "Bayer 4x4 (Balanced)"
        case .bayer8x8: return "Bayer 8x8 (Smooth)"
        case .cluster4x4: return "Cluster 4x4 (Vintage)"
        case .cluster8x8: return "Cluster 8x8 (Soft)"
        case .blueNoise: return "Blue Noise / Organic (Best Quality)"
        case .floydSteinberg: return "Floyd-Steinberg (Error Diffusion)"
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
    var colorDepth: Double = 4.0 // Default to 4 levels
    var selectedAlgorithm: DitherAlgorithm = .bayer4x4
    var isGrayscale: Bool = false
    
    // Chaos / FX Parameters
    var offsetJitter: Double = 0.0
    var patternRotation: Double = 0.0
    var errorAmplify: Double = 1.0
    var errorRandomness: Double = 0.0
    var thresholdNoise: Double = 0.0
    var waveDistortion: Double = 0.0
    var pixelDisplace: Double = 0.0
    var turbulence: Double = 0.0
    var chromaAberration: Double = 0.0
    var bitDepthChaos: Double = 0.0
    var paletteRandomize: Double = 0.0
    
    private let renderer = MetalImageRenderer()
    private var renderTask: Task<Void, Never>?
    private var renderDebounceTask: Task<Void, Never>?
    
    init() {}
    
    func resetChaosEffects() {
        offsetJitter = 0.0
        patternRotation = 0.0
        errorAmplify = 1.0
        errorRandomness = 0.0
        thresholdNoise = 0.0
        waveDistortion = 0.0
        pixelDisplace = 0.0
        turbulence = 0.0
        chromaAberration = 0.0
        bitDepthChaos = 0.0
        paletteRandomize = 0.0
        processImage()
    }
    
    func forceRefresh() {
        print("🔄 Force refresh triggered")
        guard let _ = inputImage else {
            print("⚠️ No input image to refresh")
            return
        }
        
        // Clear everything
        renderDebounceTask?.cancel()
        renderDebounceTask = nil
        renderTask?.cancel()
        renderTask = nil
        processedImage = nil
        
        // Wait a frame
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.processImage()
        }
    }
    
    func load(url: URL) {
        // Cancel all tasks
        renderTask?.cancel()
        renderTask = nil
        renderDebounceTask?.cancel()
        renderDebounceTask = nil
        
        // CRITICAL: Clear old images to release memory
        processedImage = nil
        inputImage = nil
        
        // Force memory cleanup and load new image
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                print("Failed to load image from \(url)")
                return
            }
            
            self.inputImage = cgImage
        }
        
        self.inputImageId = UUID() // Signal that a new image has been loaded
        
        // Small delay to ensure UI updates
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.processImage()
        }
    }
    
    func processImage() {
        guard let input = inputImage, let renderer = renderer else { return }
        
        // Cancel previous debounce
        renderDebounceTask?.cancel()
        
        // Debounce rapid parameter changes
        renderDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50)) // 50ms debounce
            
            if Task.isCancelled { return }
            
            // Cancel previous render task
            self.renderTask?.cancel()
            self.renderTask = nil
            
            // Generate a random seed for consistent chaos per frame/update
            let seed = UInt32.random(in: 0...UInt32.max)
            
            let params = RenderParameters(
                brightness: Float(self.brightness),
                contrast: Float(self.contrast),
                pixelScale: Float(self.pixelScale),
                colorDepth: Float(self.colorDepth),
                algorithm: Int32(self.selectedAlgorithm.rawValue),
                isGrayscale: self.isGrayscale ? 1 : 0,
                
                // Chaos Params
                offsetJitter: Float(self.offsetJitter),
                patternRotation: Float(self.patternRotation),
                errorAmplify: Float(self.errorAmplify),
                errorRandomness: Float(self.errorRandomness),
                thresholdNoise: Float(self.thresholdNoise),
                waveDistortion: Float(self.waveDistortion),
                pixelDisplace: Float(self.pixelDisplace),
                turbulence: Float(self.turbulence),
                chromaAberration: Float(self.chromaAberration),
                bitDepthChaos: Float(self.bitDepthChaos),
                paletteRandomize: Float(self.paletteRandomize),
                randomSeed: seed
            )
            
            print("🔄 Processing image with algorithm: \(self.selectedAlgorithm.name)")
            
            self.renderTask = Task.detached(priority: .userInitiated) { [input, renderer, params] in
                if Task.isCancelled {
                    print("⚠️ Render task cancelled before starting")
                    return
                }
                
                let result = renderer.render(input: input, params: params)
                
                if Task.isCancelled {
                    print("⚠️ Render task cancelled after render")
                    return
                }
                
                await MainActor.run {
                    if Task.isCancelled { return }
                    print("✅ Render complete, updating UI")
                    self.processedImage = result
                }
            }
        }
    }
    
    func exportResult(to url: URL) {
        // Legacy export, keeping for compatibility but forwarding to new system with defaults
        exportImage(to: url, format: .png, scale: 1.0, jpegQuality: 1.0, preserveMetadata: true, flattenTransparency: false)
    }
    
    // MARK: - Advanced Export
    
    func exportImage(to url: URL,
                     format: ExportFormat,
                     scale: CGFloat,
                     jpegQuality: Double,
                     preserveMetadata: Bool,
                     flattenTransparency: Bool) {
        
        guard let currentImage = processedImage else { return }
        
        // Convert CGImage to NSImage for processing
        let nsImage = NSImage(cgImage: currentImage, size: NSSize(width: currentImage.width, height: currentImage.height))
        
        // Apply scaling if needed
        let finalImage: NSImage
        if scale > 1.0 {
            finalImage = resizeImage(nsImage, scale: scale)
        } else {
            finalImage = nsImage
        }
        
        // Export based on format
        switch format {
        case .png:
            exportAsPNG(finalImage, to: url, flattenAlpha: flattenTransparency)
        case .jpeg:
            exportAsJPEG(finalImage, to: url, quality: jpegQuality)
        case .tiff:
            exportAsTIFF(finalImage, to: url, flattenAlpha: flattenTransparency)
        case .pdf:
            exportAsPDF(finalImage, to: url)
        }
    }
    
    private func resizeImage(_ image: NSImage, scale: CGFloat) -> NSImage {
        let newSize = NSSize(width: image.size.width * scale,
                             height: image.size.height * scale)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .none // Nearest neighbor for pixel art
        
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        newImage.unlockFocus()
        return newImage
    }
    
    private func flattenImageAlpha(_ image: NSImage) -> NSImage {
        let flattened = NSImage(size: image.size)
        flattened.lockFocus()
        
        // Draw white background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        
        // Draw image on top
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1.0)
        
        flattened.unlockFocus()
        return flattened
    }
    
    // MARK: - Format Exporters
    
    private func exportAsPNG(_ image: NSImage, to url: URL, flattenAlpha: Bool) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        bitmapRep.size = image.size
        
        // Handle alpha flattening
        if flattenAlpha {
            let flattened = flattenImageAlpha(image)
            guard let flatCGImage = flattened.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let flatRep = NSBitmapImageRep(cgImage: flatCGImage)
            flatRep.size = image.size
            
            guard let pngData = flatRep.representation(using: .png, properties: [:]) else { return }
            try? pngData.write(to: url, options: .atomic)
            return
        }
        
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: url, options: .atomic)
    }
    
    private func exportAsJPEG(_ image: NSImage, to url: URL, quality: Double) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        bitmapRep.size = image.size
        
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: NSNumber(value: quality)
        ]
        
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: properties) else { return }
        try? jpegData.write(to: url, options: .atomic)
    }
    
    private func exportAsTIFF(_ image: NSImage, to url: URL, flattenAlpha: Bool) {
        let imageToExport = flattenAlpha ? flattenImageAlpha(image) : image
        guard let tiffData = imageToExport.tiffRepresentation else { return }
        try? tiffData.write(to: url, options: .atomic)
    }
    
    private func exportAsPDF(_ image: NSImage, to url: URL) {
        let pdfData = NSMutableData()
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return }
        
        var mediaBox = CGRect(origin: .zero, size: image.size)
        
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
        
        pdfContext.beginPage(mediaBox: &mediaBox)
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        pdfContext.draw(cgImage, in: mediaBox)
        
        pdfContext.endPage()
        pdfContext.closePDF()
        
        try? pdfData.write(to: url, options: .atomic)
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    case tiff = "TIFF"
    case pdf = "PDF"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        case .pdf: return "pdf"
        }
    }
    
    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .pdf: return .pdf
        }
    }
}

