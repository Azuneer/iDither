import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = DitherViewModel()
    @State private var isImporting = false
    
    // Export State
    @State private var showExportOptionsSheet = false
    @State private var exportFormat: ExportFormat = .png
    @State private var exportScale: CGFloat = 1.0
    @State private var jpegQuality: Double = 0.85
    @State private var preserveMetadata = true
    @State private var flattenTransparency = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, isImporting: $isImporting, showExportOptions: $showExportOptionsSheet)
                .navigationSplitViewColumnWidth(min: 280, ideal: 300)
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
        // CHAOS / FX PARAMETERS (Grouped in modifier)
        .onChaosChange(viewModel: viewModel)
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
        // Export Options Sheet
        .sheet(isPresented: $showExportOptionsSheet) {
            NavigationStack {
                Form {
                    // SECTION 1: Format
                    Section("Format") {
                        Picker("Format", selection: $exportFormat) {
                            ForEach(ExportFormat.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        // Show quality slider ONLY for JPEG
                        if exportFormat == .jpeg {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Quality")
                                    Spacer()
                                    Text("\(Int(jpegQuality * 100))%")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                Slider(value: $jpegQuality, in: 0.1...1.0)
                                    .tint(.accentColor)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // SECTION 2: Resolution
                    Section("Resolution") {
                        Picker("Scale", selection: $exportScale) {
                            Text("1× (Original)").tag(1.0)
                            Text("2× (Double)").tag(2.0)
                            Text("4× (Quadruple)").tag(4.0)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // SECTION 3: Options
                    Section("Options") {
                        Toggle("Preserve metadata", isOn: $preserveMetadata)
                        
                        if exportFormat == .png || exportFormat == .tiff {
                            Toggle("Flatten transparency", isOn: $flattenTransparency)
                        }
                    }
                    
                    // SECTION 4: Info
                    Section {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("Export will apply all current dithering settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Export Options")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showExportOptionsSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Export...") {
                            showExportOptionsSheet = false
                            // Now open NSSavePanel with configured settings
                            performExportWithOptions()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .frame(minWidth: 450, idealWidth: 500, minHeight: 400)
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
    
    func performExportWithOptions() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = true
        
        // Set filename with correct extension based on chosen format
        let baseName = "dithered_image"
        savePanel.nameFieldStringValue = "\(baseName).\(exportFormat.fileExtension)"
        
        // Set allowed file types
        savePanel.allowedContentTypes = [exportFormat.utType]
        
        savePanel.begin { response in
            guard response == .OK,
                  let url = savePanel.url else { return }
            
            // Perform export with the configured settings
            viewModel.exportImage(to: url,
                                  format: exportFormat,
                                  scale: exportScale,
                                  jpegQuality: jpegQuality,
                                  preserveMetadata: preserveMetadata,
                                  flattenTransparency: flattenTransparency)
        }
    }
}

// SidebarView (Updated to trigger sheet)
struct SidebarView: View {
    @Bindable var viewModel: DitherViewModel
    @Binding var isImporting: Bool
    @Binding var showExportOptions: Bool
    
    @State private var showChaosSection = false // Chaos Section State
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // --- ALGORITHM SECTION ---
                VStack(alignment: .leading, spacing: 12) {
                    Text("ALGORITHM")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    
                    Picker("Algorithm", selection: $viewModel.selectedAlgorithm) {
                        ForEach(DitherAlgorithm.allCases) { algo in
                            Text(algo.name).tag(algo)
                        }
                    }
                    .labelsHidden()
                    
                    Toggle("Grayscale / 1-bit", isOn: $viewModel.isGrayscale)
                        .toggleStyle(.switch)
                        .padding(.top, 4)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // --- PRE-PROCESSING SECTION ---
                VStack(alignment: .leading, spacing: 16) {
                    Text("PRE-PROCESSING")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    // Brightness slider
                    VStack(spacing: 6) {
                        HStack {
                            Text("Brightness")
                                .font(.system(size: 13))
                            Spacer()
                            Text(String(format: "%.2f", viewModel.brightness))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.brightness, in: -1.0...1.0)
                            .tint(.accentColor)
                    }
                    
                    // Contrast slider
                    VStack(spacing: 6) {
                        HStack {
                            Text("Contrast")
                                .font(.system(size: 13))
                            Spacer()
                            Text(String(format: "%.2f", viewModel.contrast))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.contrast, in: 0.0...4.0)
                            .tint(.accentColor)
                    }
                    
                    // Pixel Scale slider
                    VStack(spacing: 6) {
                        HStack {
                            Text("Pixel Scale")
                                .font(.system(size: 13))
                            Spacer()
                            Text("\(Int(viewModel.pixelScale))x")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.pixelScale, in: 1.0...20.0, step: 1.0)
                            .tint(.accentColor)
                    }
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // --- QUANTIZATION SECTION ---
                VStack(alignment: .leading, spacing: 16) {
                    Text("QUANTIZATION")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 6) {
                        HStack {
                            Text("Color Depth")
                                .font(.system(size: 13))
                            Spacer()
                            Text("\(Int(viewModel.colorDepth))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.colorDepth, in: 1.0...32.0, step: 1.0)
                            .tint(.accentColor)
                    }
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // --- CHAOS / FX SECTION ---
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        withAnimation(.snappy) {
                            showChaosSection.toggle()
                        }
                    }) {
                        HStack {
                            Text("CHAOS / FX")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: showChaosSection ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    
                    if showChaosSection {
                        VStack(alignment: .leading, spacing: 16) {
                            // Pattern Distortion
                            Text("Pattern Distortion")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.top, 12)
                            
                            SliderControl(label: "Offset Jitter", value: $viewModel.offsetJitter, range: 0...1, format: .percent)
                            SliderControl(label: "Rotation", value: $viewModel.patternRotation, range: 0...1, format: .percent)
                            
                            // Error Propagation (Floyd-Steinberg only)
                            if viewModel.selectedAlgorithm == .floydSteinberg {
                                Text("Error Propagation")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary.opacity(0.8))
                                    .padding(.top, 12)
                                
                                SliderControl(label: "Error Amplify", value: $viewModel.errorAmplify, range: 0.5...3.0, format: .multiplier)
                                SliderControl(label: "Random Direction", value: $viewModel.errorRandomness, range: 0...1, format: .percent)
                            }
                            
                            // Threshold Effects
                            Text("Threshold Effects")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.top, 12)
                            
                            SliderControl(label: "Noise Injection", value: $viewModel.thresholdNoise, range: 0...1, format: .percent)
                            SliderControl(label: "Wave Distortion", value: $viewModel.waveDistortion, range: 0...1, format: .percent)
                            
                            // Spatial Glitch
                            Text("Spatial Glitch")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.top, 12)
                            
                            SliderControl(label: "Pixel Displace", value: $viewModel.pixelDisplace, range: 0...100, format: .pixels)
                            SliderControl(label: "Turbulence", value: $viewModel.turbulence, range: 0...1, format: .percent)
                            SliderControl(label: "Chroma Aberration", value: $viewModel.chromaAberration, range: 0...20, format: .pixels)
                            
                            // Quantization Chaos
                            Text("Quantization Chaos")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.top, 12)
                            
                            SliderControl(label: "Bit Depth Chaos", value: $viewModel.bitDepthChaos, range: 0...1, format: .percent)
                            SliderControl(label: "Palette Randomize", value: $viewModel.paletteRandomize, range: 0...1, format: .percent)
                            
                            // Reset Button
                            Button(action: {
                                withAnimation {
                                    viewModel.resetChaosEffects()
                                }
                            }) {
                                Text("Reset All Chaos")
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.small)
                            .padding(.top, 12)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                
                #if DEBUG
                Button("Force Refresh (Debug)") {
                    viewModel.forceRefresh()
                }
                .font(.caption)
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .padding(.leading, 4)
                #endif
                
                Spacer()
            }
            .padding(20)
        }
        .background(.regularMaterial)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("iDither")
        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { isImporting = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import Image")
                
                Button(action: { showExportOptions = true }) {
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





// Custom Modifier to handle Chaos/FX parameter observation
// Extracts complexity from the main ContentView body to fix compiler type-check timeout
struct ChaosEffectObserver: ViewModifier {
    var viewModel: DitherViewModel
    
    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.offsetJitter) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.patternRotation) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.errorAmplify) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.errorRandomness) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.thresholdNoise) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.waveDistortion) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.pixelDisplace) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.turbulence) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.chromaAberration) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.bitDepthChaos) { _, _ in viewModel.processImage() }
            .onChange(of: viewModel.paletteRandomize) { _, _ in viewModel.processImage() }
    }
}

extension View {
    func onChaosChange(viewModel: DitherViewModel) -> some View {
        self.modifier(ChaosEffectObserver(viewModel: viewModel))
    }
}

struct SliderControl: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: ValueFormat
    
    enum ValueFormat {
        case percent
        case multiplier
        case pixels
        case raw
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .tint(.accentColor)
        }
    }
    
    var formattedValue: String {
        switch format {
        case .percent:
            return "\(Int(value * 100))%"
        case .multiplier:
            return String(format: "%.1f×", value)
        case .pixels:
            return "\(Int(value))px"
        case .raw:
            return String(format: "%.2f", value)
        }
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
