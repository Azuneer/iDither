import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = DitherViewModel()
    @State private var isImporting = false
    @State private var isExporting = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, isImporting: $isImporting, isExporting: $isExporting)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            DetailView(viewModel: viewModel, loadFromProviders: loadFromProviders)
        }
        // Global Cursor Fix: Force arrow cursor to prevent I-Beam
        .onHover { _ in
            NSCursor.arrow.push()
        }
        .onChange(of: viewModel.brightness) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.contrast) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.pixelScale) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.colorDepth) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.selectedAlgorithm) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.isGrayscale) { _, _ in viewModel.processImage() }
        // File Importer at the very top level
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.load(url: url)
                }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: ImageDocument(image: viewModel.processedImage),
            contentType: .png,
            defaultFilename: "dithered_image"
        ) { result in
            if case .failure(let error) = result {
                print("Export failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadFromProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        viewModel.load(url: url)
                    }
                }
            }
            return true
        }
        return false
    }
}

// Helper for FileExporter
struct ImageDocument: FileDocument {
    var image: CGImage?
    
    init(image: CGImage?) {
        self.image = image
    }
    
    static var readableContentTypes: [UTType] { [.png] }
    
    init(configuration: ReadConfiguration) throws {
        // Read not implemented for export-only
        self.image = nil
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let image = image else { throw CocoaError(.fileWriteUnknown) }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: pngData)
    }
}

struct SidebarView: View {
    @Bindable var viewModel: DitherViewModel
    @Binding var isImporting: Bool
    @Binding var isExporting: Bool
    
    var body: some View {
        Form {
            Section("Dithering Algorithm") {
                Picker("Algorithm", selection: $viewModel.selectedAlgorithm) {
                    ForEach(DitherAlgorithm.allCases) { algo in
                        Text(algo.name).tag(algo)
                    }
                }
                
                Toggle("Grayscale / 1-bit", isOn: $viewModel.isGrayscale)
            }
            
            Section("Pre-Processing") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Brightness")
                        Spacer()
                        Text(String(format: "%.2f", viewModel.brightness))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.brightness, in: -1.0...1.0)
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Contrast")
                        Spacer()
                        Text(String(format: "%.2f", viewModel.contrast))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.contrast, in: 0.0...4.0)
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Pixel Scale")
                        Spacer()
                        Text("\(Int(viewModel.pixelScale))x")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.pixelScale, in: 1.0...20.0, step: 1.0)
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Color Depth")
                        Spacer()
                        Text("\(Int(viewModel.colorDepth))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.colorDepth, in: 1.0...32.0, step: 1.0)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical)
        .navigationTitle("iDither")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { isImporting = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import Image")
                
                Button(action: { isExporting = true }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.processedImage == nil)
                .help("Export PNG")
            }
        }
    }
}

struct DetailView: View {
    var viewModel: DitherViewModel
    var loadFromProviders: ([NSItemProvider]) -> Bool
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    // For gesture state
    @State private var magnification: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Background
                CheckeredBackground()
                    .ignoresSafeArea()
                
                // Layer 2: Image
                if let processedImage = viewModel.processedImage {
                    Image(decorative: processedImage, scale: 1.0, orientation: .up)
                        .resizable()
                        .interpolation(.none) // Nearest Neighbor for sharp pixels
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale * magnification)
                        .offset(
                            x: offset.width + (magnification - 1) * 0,
                            y: offset.height
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    magnification = value
                                }
                                .onEnded { value in
                                    scale = min(max(scale * value, 0.1), 20.0)
                                    magnification = 1.0
                                }
                        )
                } else {
                    ContentUnavailableView {
                        Label("No Image Selected", systemImage: "photo.badge.plus")
                    } description: {
                        Text("Drag and drop an image here to start dithering.")
                    }
                }
                
                // Layer 3: Floating HUD
                if viewModel.processedImage != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            FloatingToolbar(scale: $scale, offset: $offset, lastOffset: $lastOffset, onFit: {
                                fitToWindow(geometry: geometry)
                            })
                            .padding()
                        }
                    }
                }
            }
            .onDrop(of: [.image], isTargeted: nil) { providers in
                loadFromProviders(providers)
            }
            // CRITICAL FIX: Only fit to window when a NEW image is loaded (inputImageId changes)
            // This prevents the image from shrinking/resetting when adjusting sliders
            .onChange(of: viewModel.inputImageId) { _, _ in
                fitToWindow(geometry: geometry)
            }
        }
    }
    
    private func fitToWindow(geometry: GeometryProxy) {
        guard let image = viewModel.processedImage else { return }
        let imageSize = CGSize(width: image.width, height: image.height)
        let viewSize = geometry.size
        
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        
        let widthScale = viewSize.width / imageSize.width
        let heightScale = viewSize.height / imageSize.height
        let fitScale = min(widthScale, heightScale)
        
        // Apply fit
        withAnimation {
            scale = min(fitScale * 0.9, 1.0) // 90% fit or 1.0 max
            offset = .zero
            lastOffset = .zero
        }
    }
}

struct FloatingToolbar: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    var onFit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation {
                    scale = max(scale - 0.2, 0.1)
                }
            }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            
            Text("\(Int(scale * 100))%")
                .monospacedDigit()
                .frame(width: 50)
            
            Button(action: {
                withAnimation {
                    scale = min(scale + 0.2, 20.0)
                }
            }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 20)
            
            Button("1:1") {
                withAnimation {
                    scale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .buttonStyle(.plain)
            
            Button("Fit") {
                onFit()
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(radius: 5)
    }
}

struct CheckeredBackground: View {
    var body: some View {
        Canvas { context, size in
            let squareSize: CGFloat = 20
            let rows = Int(ceil(size.height / squareSize))
            let cols = Int(ceil(size.width / squareSize))
            
            for row in 0..<rows {
                for col in 0..<cols {
                    if (row + col) % 2 == 0 {
                        let rect = CGRect(x: CGFloat(col) * squareSize,
                                          y: CGFloat(row) * squareSize,
                                          width: squareSize,
                                          height: squareSize)
                        context.fill(Path(rect), with: .color(.gray.opacity(0.15)))
                    }
                }
            }
        }
        .background(Color.white)
    }
}
