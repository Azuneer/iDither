#include <metal_stdlib>
using namespace metal;

struct RenderParameters {
    float brightness;
    float contrast;
    float pixelScale;
    float colorDepth; // New parameter: 1.0 to 32.0 (Levels)
    int algorithm; // 0: None, 1: Bayer 2x2, 2: Bayer 4x4, 3: Bayer 8x8, 4: Cluster 4x4, 5: Cluster 8x8, 6: Blue Noise
    int isGrayscale;
};

// Bayer 2x2 Matrix
constant float bayer2x2[2][2] = {
    {0.0/4.0, 2.0/4.0},
    {3.0/4.0, 1.0/4.0}
};

// Bayer 4x4 Matrix
constant float bayer4x4[4][4] = {
    { 0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0 },
    {12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0 },
    { 3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0 },
    {15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0 }
};

// Bayer 8x8 Matrix
constant float bayer8x8[8][8] = {
    { 0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0 },
    {48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0 },
    {12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0 },
    {60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0 },
    { 3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0 },
    {51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0 },
    {15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0 },
    {63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0 }
};

// Cluster 4x4 Matrix
constant float cluster4x4[4][4] = {
    {12.0/16.0, 5.0/16.0,  6.0/16.0, 13.0/16.0},
    { 4.0/16.0, 0.0/16.0,  1.0/16.0,  7.0/16.0},
    {11.0/16.0, 3.0/16.0,  2.0/16.0,  8.0/16.0},
    {15.0/16.0, 10.0/16.0, 9.0/16.0, 14.0/16.0}
};

// Cluster 8x8 Matrix
constant float cluster8x8[8][8] = {
    {24.0/64.0, 10.0/64.0, 12.0/64.0, 26.0/64.0, 35.0/64.0, 47.0/64.0, 49.0/64.0, 37.0/64.0},
    { 8.0/64.0,  0.0/64.0,  2.0/64.0, 14.0/64.0, 45.0/64.0, 59.0/64.0, 61.0/64.0, 51.0/64.0},
    {22.0/64.0,  6.0/64.0,  4.0/64.0, 20.0/64.0, 43.0/64.0, 57.0/64.0, 63.0/64.0, 53.0/64.0},
    {30.0/64.0, 18.0/64.0, 16.0/64.0, 28.0/64.0, 33.0/64.0, 41.0/64.0, 55.0/64.0, 39.0/64.0},
    {34.0/64.0, 46.0/64.0, 48.0/64.0, 36.0/64.0, 25.0/64.0, 11.0/64.0, 13.0/64.0, 27.0/64.0},
    {44.0/64.0, 58.0/64.0, 60.0/64.0, 50.0/64.0,  9.0/64.0,  1.0/64.0,  3.0/64.0, 15.0/64.0},
    {42.0/64.0, 56.0/64.0, 62.0/64.0, 52.0/64.0, 23.0/64.0,  7.0/64.0,  5.0/64.0, 21.0/64.0},
    {32.0/64.0, 40.0/64.0, 54.0/64.0, 38.0/64.0, 31.0/64.0, 19.0/64.0, 17.0/64.0, 29.0/64.0}
};

// Blue Noise 8x8 (Approx)
constant float blueNoise8x8[8][8] = {
    {52.0/64.0, 21.0/64.0, 58.0/64.0, 10.0/64.0, 45.0/64.0, 33.0/64.0, 56.0/64.0, 17.0/64.0},
    { 4.0/64.0, 38.0/64.0, 28.0/64.0, 51.0/64.0,  5.0/64.0, 22.0/64.0, 40.0/64.0, 62.0/64.0},
    {61.0/64.0, 12.0/64.0, 48.0/64.0, 14.0/64.0, 55.0/64.0, 36.0/64.0,  7.0/64.0, 31.0/64.0},
    {32.0/64.0, 43.0/64.0,  2.0/64.0, 46.0/64.0, 25.0/64.0, 63.0/64.0, 19.0/64.0, 50.0/64.0},
    {16.0/64.0, 53.0/64.0, 23.0/64.0, 60.0/64.0,  9.0/64.0, 47.0/64.0, 29.0/64.0,  6.0/64.0},
    {44.0/64.0, 27.0/64.0, 39.0/64.0, 34.0/64.0, 54.0/64.0, 13.0/64.0, 59.0/64.0, 26.0/64.0},
    { 8.0/64.0, 57.0/64.0, 18.0/64.0,  1.0/64.0, 42.0/64.0, 30.0/64.0,  3.0/64.0, 49.0/64.0},
    {35.0/64.0, 24.0/64.0,  0.0/64.0, 41.0/64.0, 15.0/64.0, 52.0/64.0, 20.0/64.0, 37.0/64.0}
};

float ditherChannel(float value, float threshold, float limit) {
    // Quantization Formula
    // value: 0.0 to 1.0
    // threshold: 0.0 to 1.0 (from matrix)
    // limit: colorDepth (e.g. 4.0)
    
    float ditheredValue = value + (threshold - 0.5) * (1.0 / (limit - 1.0));
    return floor(ditheredValue * (limit - 1.0) + 0.5) / (limit - 1.0);
}

kernel void ditherShader(texture2d<float, access::read> inputTexture [[texture(0)]],
                         texture2d<float, access::write> outputTexture [[texture(1)]],
                         constant RenderParameters &params [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // 1. Pixelation
    float scale = max(1.0, params.pixelScale);
    uint2 sourceCoord = uint2(floor(float(gid.x) / scale) * scale, floor(float(gid.y) / scale) * scale);
    
    sourceCoord.x = min(sourceCoord.x, inputTexture.get_width() - 1);
    sourceCoord.y = min(sourceCoord.y, inputTexture.get_height() - 1);
    
    float4 color = inputTexture.read(sourceCoord);
    
    // 2. Color Adjustment
    float3 rgb = color.rgb;
    rgb = rgb + params.brightness;
    rgb = (rgb - 0.5) * params.contrast + 0.5;
    
    // Grayscale
    float luma = dot(rgb, float3(0.299, 0.587, 0.114));
    
    if (params.isGrayscale > 0) {
        rgb = float3(luma);
    }
    
    // 3. Dithering
    float threshold = 0.5;
    bool shouldDither = (params.algorithm > 0);
    
    if (shouldDither) {
        uint x, y;
        
        // Fetch threshold from matrix
        switch (params.algorithm) {
            case 1: // Bayer 2x2
                x = uint(sourceCoord.x / scale) % 2;
                y = uint(sourceCoord.y / scale) % 2;
                threshold = bayer2x2[y][x];
                break;
            case 2: // Bayer 4x4
                x = uint(sourceCoord.x / scale) % 4;
                y = uint(sourceCoord.y / scale) % 4;
                threshold = bayer4x4[y][x];
                break;
            case 3: // Bayer 8x8
                x = uint(sourceCoord.x / scale) % 8;
                y = uint(sourceCoord.y / scale) % 8;
                threshold = bayer8x8[y][x];
                break;
            case 4: // Cluster 4x4
                x = uint(sourceCoord.x / scale) % 4;
                y = uint(sourceCoord.y / scale) % 4;
                threshold = cluster4x4[y][x];
                break;
            case 5: // Cluster 8x8
                x = uint(sourceCoord.x / scale) % 8;
                y = uint(sourceCoord.y / scale) % 8;
                threshold = cluster8x8[y][x];
                break;
            case 6: // Blue Noise 8x8
                x = uint(sourceCoord.x / scale) % 8;
                y = uint(sourceCoord.y / scale) % 8;
                threshold = blueNoise8x8[y][x];
                break;
            default:
                break;
        }
        
        // Apply Quantized Dithering
        if (params.isGrayscale > 0) {
            // Apply only to luma (which is already in rgb)
            rgb.r = ditherChannel(rgb.r, threshold, params.colorDepth);
            rgb.g = rgb.r;
            rgb.b = rgb.r;
        } else {
            // Apply to each channel
            rgb.r = ditherChannel(rgb.r, threshold, params.colorDepth);
            rgb.g = ditherChannel(rgb.g, threshold, params.colorDepth);
            rgb.b = ditherChannel(rgb.b, threshold, params.colorDepth);
        }
    }
    

    outputTexture.write(float4(rgb, color.a), gid);
}

// ==================================================================================
// FLOYD-STEINBERG ERROR DIFFUSION HELPERS & KERNELS (Algorithm ID 7)
// ==================================================================================

// Helper to get luminance for error calculation in grayscale mode
float getLuma(float3 rgb) {
    return dot(rgb, float3(0.299, 0.587, 0.114));
}

// PASS 1: EVEN ROWS (Left -> Right)
// - Reads original pixel
// - Dithers it
// - Writes result to outputTexture
// - Writes RAW error 'diff' to errorTexture (at current coord) for Pass 2 to consume
kernel void ditherShaderFS_Pass1(texture2d<float, access::read> inputTexture [[texture(0)]],
                                 texture2d<float, access::write> outputTexture [[texture(1)]],
                                 texture2d<float, access::write> errorTexture [[texture(2)]],
                                 constant RenderParameters &params [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    
    // Dispatch: (1, height/2, 1). Each thread processes one FULL ROW.
    uint y = gid.y * 2; // Pass 1 processes EVEN rows: 0, 2, 4...
    
    if (y >= inputTexture.get_height()) return;
    
    uint width = inputTexture.get_width();
    float3 currentError = float3(0.0); // Error propagated from immediate Left neighbor
    
    // Scale handling (minimal implementation for now, usually FS runs 1:1)
    // If pixel scale > 1, FS behaves weirdly unless we downsample/upsample.
    // For now, let's treat FS as operating on the native coordinates (or scaled ones).
    // The previous shader code did manual pixelation.
    // To support `pixelScale`, we simply use the scaled coordinates for reading input,
    // but we iterate 1:1 on output? No, if we pixelate, we want blocky dither?
    // FS is hard to 'blocky' dither without pre-scaling.
    // Let's stick to 1:1 processing for the error diffusion logic itself.
    // But we read the input color from the "pixelated" coordinate.
    
    float scale = max(1.0, params.pixelScale);
    
    for (uint x = 0; x < width; x++) {
        uint2 coords = uint2(x, y);
        
        // Pixelate Input Read
        uint2 mappedCoords = uint2(floor(float(x) / scale) * scale, floor(float(y) / scale) * scale);
        mappedCoords.x = min(mappedCoords.x, inputTexture.get_width() - 1);
        mappedCoords.y = min(mappedCoords.y, inputTexture.get_height() - 1);

        float4 colorRaw = inputTexture.read(mappedCoords);
        float3 originalColor = colorRaw.rgb;
        
        // Color Adjust
        originalColor = originalColor + params.brightness;
        originalColor = (originalColor - 0.5) * params.contrast + 0.5;
        
        // Grayscale
        if (params.isGrayscale > 0) {
            float l = getLuma(originalColor);
            originalColor = float3(l);
        }
        
        // ----------------------------------------------------
        // ERROR DIFFUSION CORE
        // ----------------------------------------------------
        
        // Add error from Left Neighbor (Pass 1 is L->R)
        float3 pixelIn = originalColor + currentError;
        
        // Quantize
        float3 pixelOut = float3(0.0);
        float levels = max(1.0, params.colorDepth); // Ensure no div by zero
        if (levels <= 1.0) levels = 2.0;

        pixelOut.r = floor(pixelIn.r * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut.g = floor(pixelIn.g * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut.b = floor(pixelIn.b * (levels - 1.0) + 0.5) / (levels - 1.0);
        
        pixelOut = clamp(pixelOut, 0.0, 1.0);
        
        // Calculate Error
        float3 diff = pixelIn - pixelOut;
        
        // Store RAW error for Pass 2 (Row below) to read
        // Note: we store 'diff', NOT the distributed parts. Pass 2 will calculate distribution.
        if (y + 1 < inputTexture.get_height()) {
            errorTexture.write(float4(diff, 1.0), coords);
        }
        
        outputTexture.write(float4(pixelOut, colorRaw.a), coords);
        
        // Propagate to Right Neighbor (7/16)
        currentError = diff * (7.0 / 16.0);
    }
}

// PASS 2: ODD ROWS (Right -> Left Serpentine)
// - Reads original pixel
// - Absorbs error from Row Above (which stored RAW diffs)
// - Dithers
// - Writes result
kernel void ditherShaderFS_Pass2(texture2d<float, access::read> inputTexture [[texture(0)]],
                                 texture2d<float, access::write> outputTexture [[texture(1)]],
                                 texture2d<float, access::read> errorTexture [[texture(2)]], // Contains diffs from Pass 1
                                 constant RenderParameters &params [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    
    // Dispatch: (1, height/2, 1)
    uint y = gid.y * 2 + 1; // Pass 2 processes ODD rows: 1, 3, 5...
    
    if (y >= inputTexture.get_height()) return;
    
    uint width = inputTexture.get_width();
    float3 currentError = float3(0.0); // Error propagated from immediate Right neighbor (Serpentine R->L)
    
    float scale = max(1.0, params.pixelScale);
    
    // Serpentine: Iterate Right to Left
    for (int x_int = int(width) - 1; x_int >= 0; x_int--) {
        uint x = uint(x_int);
        uint2 coords = uint2(x, y);
        
        // 1. Calculate Incoming Error from Row Above (Even Row, L->R)
        // Row Above is y-1. We are at x.
        // Even Row (y-1) propagated error to us (y) via:
        // - (x-1, y-1) sent 3/16 (Bottom Left) -> reaches ME at x if I am (x-1+1) = x. Correct.
        // - (x,   y-1) sent 5/16 (Down)        -> reaches ME at x. Correct.
        // - (x+1, y-1) sent 1/16 (Bottom Right)-> reaches ME at x. Correct.
        
        float3 errorFromAbove = float3(0.0);
        uint prevY = y - 1;
        
        // Read neighbor errors (and apply weights now)
        
        // From Top-Left (x-1, y-1): It pushed 3/16 to Bottom-Right (x) ? No.
        // Standard FS (Left->Right scan):
        // P(x, y) distributes:
        // Right (x+1, y): 7/16
        // Bottom-Left (x-1, y+1): 3/16
        // Bottom (x, y+1): 5/16
        // Bottom-Right (x+1, y+1): 1/16
        
        // So, ME (x, y) receives from:
        // (x+1, y-1) [Top Right]: sent 3/16 to its Bottom Left (which is ME).
        // (x,   y-1) [Top]:       sent 5/16 to its Bottom (which is ME).
        // (x-1, y-1) [Top Left]:  sent 1/16 to its Bottom Right (which is ME).
        
        // Read Top Right (x+1, prevY)
        if (x + 1 < width) {
            float3 e = errorTexture.read(uint2(x+1, prevY)).rgb;
            errorFromAbove += e * (3.0 / 16.0);
        }
        
        // Read Top (x, prevY)
        {
            float3 e = errorTexture.read(uint2(x, prevY)).rgb;
            errorFromAbove += e * (5.0 / 16.0);
        }
        
        // Read Top Left (x-1, prevY)
        if (x >= 1) {
            float3 e = errorTexture.read(uint2(x-1, prevY)).rgb;
            errorFromAbove += e * (1.0 / 16.0);
        }
        
        // 2. Read Pixel
        uint2 mappedCoords = uint2(floor(float(x) / scale) * scale, floor(float(y) / scale) * scale);
        mappedCoords.x = min(mappedCoords.x, inputTexture.get_width() - 1);
        mappedCoords.y = min(mappedCoords.y, inputTexture.get_height() - 1);
        
        float4 colorRaw = inputTexture.read(mappedCoords);
        float3 originalColor = colorRaw.rgb;
        originalColor = originalColor + params.brightness;
        originalColor = (originalColor - 0.5) * params.contrast + 0.5;
        
        if (params.isGrayscale > 0) {
            float l = getLuma(originalColor);
            originalColor = float3(l);
        }
        
        // 3. Combine
        float3 pixelIn = originalColor + currentError + errorFromAbove;
        
        // 4. Quantize
        float3 pixelOut = float3(0.0);
        float levels = max(1.0, params.colorDepth);
        if (levels <= 1.0) levels = 2.0;

        pixelOut.r = floor(pixelIn.r * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut.g = floor(pixelIn.g * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut.b = floor(pixelIn.b * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut = clamp(pixelOut, 0.0, 1.0);
        
        // 5. Diff
        float3 diff = pixelIn - pixelOut;
        
        outputTexture.write(float4(pixelOut, colorRaw.a), coords);
        
        // 6. Propagate Horizontally (Serpentine R->L)
        // In R->L scan, 'Right' neighbor in FS diagram is actually 'Left' neighbor in spatial.
        // We push 7/16 to the next pixel we visit (x-1).
        currentError = diff * (7.0 / 16.0);
    }
}

