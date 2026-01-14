import SwiftUI

struct ContentView: View {
    @State private var viewModel = DitherViewModel()
    @State private var isExporting = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, openFile: openFile, saveFile: saveFile)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            DetailView(viewModel: viewModel, loadFromProviders: loadFromProviders)
        }
        .onChange(of: viewModel.brightness) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.contrast) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.pixelScale) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.selectedAlgorithm) { _, _ in viewModel.processImage() }
        .onChange(of: viewModel.isGrayscale) { _, _ in viewModel.processImage() }
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                viewModel.load(url: url)
            }
        }
    }
    
    private func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "dithered_image.png"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                viewModel.exportResult(to: url)
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

struct SidebarView: View {
    @Bindable var viewModel: DitherViewModel
    var openFile: () -> Void
    var saveFile: () -> Void
    
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
            }
        }
        .formStyle(.grouped)
        .padding(.vertical)
        .navigationTitle("iDither")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: openFile) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import Image")
                
                Button(action: saveFile) {
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
    
    var body: some View {
        ZStack {
            CheckeredBackground()
                .ignoresSafeArea()
            
            if let processedImage = viewModel.processedImage {
                Image(decorative: processedImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(40)
                    .shadow(radius: 10)
            } else {
                ContentUnavailableView {
                    Label("No Image Selected", systemImage: "photo.badge.plus")
                } description: {
                    Text("Drag and drop an image here to start dithering.")
                }
            }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            loadFromProviders(providers)
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
