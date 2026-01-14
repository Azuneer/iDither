#include <metal_stdlib>
using namespace metal;

struct RenderParameters {
    // Existing parameters
    float brightness;
    float contrast;
    float pixelScale;
    float colorDepth;
    int algorithm; // 0: None, 1: Bayer 2x2, 2: Bayer 4x4, 3: Bayer 8x8, 4: Cluster 4x4, 5: Cluster 8x8, 6: Blue Noise, 7: Floyd-Steinberg
    int isGrayscale;
    
    // CHAOS / FX PARAMETERS
    float offsetJitter;        // 0.0 to 1.0
    float patternRotation;     // 0.0 to 1.0
    
    float errorAmplify;        // 0.5 to 3.0 (1.0 = normal)
    float errorRandomness;     // 0.0 to 1.0
    
    float thresholdNoise;      // 0.0 to 1.0
    float waveDistortion;      // 0.0 to 1.0
    
    float pixelDisplace;       // 0.0 to 50.0 (pixels)
    float turbulence;          // 0.0 to 1.0
    float chromaAberration;    // 0.0 to 20.0 (pixels)
    
    float bitDepthChaos;       // 0.0 to 1.0
    float paletteRandomize;    // 0.0 to 1.0
    
    uint randomSeed;
};

// ==================================================================================
// CHAOS HELPER FUNCTIONS
// ==================================================================================

float random(float2 st, uint seed) {
    return fract(sin(dot(st.xy + float2(seed * 0.001), float2(12.9898, 78.233))) * 43758.5453);
}

float2 random2(float2 st, uint seed) {
    float2 s = float2(seed * 0.001, seed * 0.002);
    return float2(
        fract(sin(dot(st.xy + s, float2(12.9898, 78.233))) * 43758.5453),
        fract(sin(dot(st.xy + s, float2(93.9898, 67.345))) * 23421.6312)
    );
}

float noise(float2 st, uint seed) {
    float2 i = floor(st);
    float2 f = fract(st);
    
    float a = random(i, seed);
    float b = random(i + float2(1.0, 0.0), seed);
    float c = random(i + float2(0.0, 1.0), seed);
    float d = random(i + float2(1.0, 1.0), seed);
    
    float2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float2 applySpatialChaos(float2 coord, constant RenderParameters &params, uint2 gid) {
    float2 chaosCoord = coord;
    
    if (params.pixelDisplace > 0.0) {
        float2 offset = random2(coord * 0.01, params.randomSeed) - 0.5;
        chaosCoord += offset * params.pixelDisplace;
    }
    
    if (params.turbulence > 0.0) {
        float scale = 0.05;
        float offsetX = noise(coord * scale, params.randomSeed) * 2.0 - 1.0;
        float offsetY = noise(coord * scale + float2(100.0), params.randomSeed) * 2.0 - 1.0;
        chaosCoord += float2(offsetX, offsetY) * params.turbulence * 20.0;
    }
    
    return chaosCoord;
}

float applyThresholdChaos(float threshold, float2 coord, constant RenderParameters &params) {
    float chaosThreshold = threshold;
    
    if (params.thresholdNoise > 0.0) {
        float noise = random(coord, params.randomSeed);
        chaosThreshold = mix(chaosThreshold, noise, params.thresholdNoise);
    }
    
    if (params.waveDistortion > 0.0) {
        float wave = sin(coord.x * 0.1) * cos(coord.y * 0.1) * 0.5 + 0.5;
        chaosThreshold = mix(chaosThreshold, wave, params.waveDistortion * 0.5);
    }
    
    return chaosThreshold;
}

uint2 applyPatternChaos(uint2 matrixCoord, float2 pixelCoord, constant RenderParameters &params, uint matrixSize) {
    uint2 chaosCoord = matrixCoord;
    
    if (params.offsetJitter > 0.0) {
        float2 jitter = random2(pixelCoord * 0.1, params.randomSeed) * params.offsetJitter * float(matrixSize);
        chaosCoord = uint2((float2(chaosCoord) + jitter)) % matrixSize;
    }
    
    if (params.patternRotation > 0.0) {
        float rotRandom = random(pixelCoord * 0.05, params.randomSeed);
        if (rotRandom < params.patternRotation) {
            uint temp = chaosCoord.x;
            chaosCoord.x = matrixSize - 1 - chaosCoord.y;
            chaosCoord.y = temp;
        }
    }
    
    return chaosCoord;
}

float3 applyChromaAberration(texture2d<float, access::read> inputTexture,
                             float2 coord,
                             float amount,
                             uint2 texSize) {
    if (amount == 0.0) {
        uint2 pixelCoord = uint2(clamp(coord, float2(0), float2(texSize) - 1.0));
        return inputTexture.read(pixelCoord).rgb;
    }
    
    float2 redOffset = coord + float2(amount, 0);
    float2 blueOffset = coord - float2(amount, 0);
    
    uint2 redCoord = uint2(clamp(redOffset, float2(0), float2(texSize) - 1.0));
    uint2 greenCoord = uint2(clamp(coord, float2(0), float2(texSize) - 1.0));
    uint2 blueCoord = uint2(clamp(blueOffset, float2(0), float2(texSize) - 1.0));
    
    float r = inputTexture.read(redCoord).r;
    float g = inputTexture.read(greenCoord).g;
    float b = inputTexture.read(blueCoord).b;
    
    return float3(r, g, b);
}

float applyQuantizationChaos(float value, float2 coord, constant RenderParameters &params) {
    float chaosValue = value;
    
    if (params.bitDepthChaos > 0.0) {
        float randVal = random(coord * 0.1, params.randomSeed);
        if (randVal < params.bitDepthChaos) {
            float reducedDepth = floor(randVal * 3.0) + 2.0;
            chaosValue = floor(value * reducedDepth) / reducedDepth;
        }
    }
    
    if (params.paletteRandomize > 0.0) {
        float randShift = (random(coord, params.randomSeed) - 0.5) * params.paletteRandomize;
        chaosValue = clamp(value + randShift, 0.0, 1.0);
    }
    
    return chaosValue;
}

// ==================================================================================
// DITHERING MATRICES
// ==================================================================================

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
kernel void ditherShaderFS_Pass1(texture2d<float, access::read> inputTexture [[texture(0)]],
                                 texture2d<float, access::write> outputTexture [[texture(1)]],
                                 texture2d<float, access::write> errorTexture [[texture(2)]],
                                 constant RenderParameters &params [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    
    uint y = gid.y * 2;
    if (y >= inputTexture.get_height()) return;
    
    uint width = inputTexture.get_width();
    float3 currentError = float3(0.0);
    
    float scale = max(1.0, params.pixelScale);
    
    for (uint x = 0; x < width; x++) {
        uint2 coords = uint2(x, y);
        
        // Pixelate Input Read with Chaos
        uint2 mappedCoords = uint2(floor(float(x) / scale) * scale, floor(float(y) / scale) * scale);
        
        if (params.pixelDisplace > 0.0 || params.turbulence > 0.0) {
             float2 chaosC = applySpatialChaos(float2(mappedCoords), params, coords);
             mappedCoords = uint2(clamp(chaosC, float2(0), float2(inputTexture.get_width()-1, inputTexture.get_height()-1)));
        }
        
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
        
        // Error Diffusion Core
        float3 pixelIn = originalColor + currentError;
        
        // Apply Quantization Chaos
        if (params.isGrayscale > 0) {
            pixelIn.r = applyQuantizationChaos(pixelIn.r, float2(coords), params);
            pixelIn.g = pixelIn.r;
            pixelIn.b = pixelIn.r;
        } else {
             pixelIn.r = applyQuantizationChaos(pixelIn.r, float2(coords), params);
             pixelIn.g = applyQuantizationChaos(pixelIn.g, float2(coords), params);
             pixelIn.b = applyQuantizationChaos(pixelIn.b, float2(coords), params);
        }

        // Quantize
        float3 pixelOut = float3(0.0);
        float levels = max(1.0, params.colorDepth);
        if (levels <= 1.0) levels = 2.0;

        pixelOut.r = floor(pixelIn.r * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut.g = floor(pixelIn.g * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut.b = floor(pixelIn.b * (levels - 1.0) + 0.5) / (levels - 1.0);
        
        pixelOut = clamp(pixelOut, 0.0, 1.0);
        
        // Calculate Error
        float3 diff = pixelIn - pixelOut;
        
        // Chaos: Error Amplify
        if (params.errorAmplify != 1.0) {
            diff *= params.errorAmplify;
        }
        
        // Store RAW error for Pass 2
        if (y + 1 < inputTexture.get_height()) {
            errorTexture.write(float4(diff, 1.0), coords);
        }
        
        outputTexture.write(float4(pixelOut, colorRaw.a), coords);
        
        // Chaos: Error Randomness in Propagation
        float weight = 7.0 / 16.0;
        if (params.errorRandomness > 0.0) {
             float r = random(float2(coords), params.randomSeed);
             weight = mix(weight, r * 0.8, params.errorRandomness);
        }
        
        currentError = diff * weight;
    }
}

// PASS 2: ODD ROWS (Right -> Left Serpentine)
kernel void ditherShaderFS_Pass2(texture2d<float, access::read> inputTexture [[texture(0)]],
                                 texture2d<float, access::write> outputTexture [[texture(1)]],
                                 texture2d<float, access::read> errorTexture [[texture(2)]],
                                 constant RenderParameters &params [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    
    uint y = gid.y * 2 + 1;
    if (y >= inputTexture.get_height()) return;
    
    uint width = inputTexture.get_width();
    float3 currentError = float3(0.0);
    
    float scale = max(1.0, params.pixelScale);
    
    for (int x_int = int(width) - 1; x_int >= 0; x_int--) {
        uint x = uint(x_int);
        uint2 coords = uint2(x, y);
        
        // 1. Calculate Incoming Error from Row Above
        float3 errorFromAbove = float3(0.0);
        uint prevY = y - 1;
        
        // Weights
        float w_tr = 3.0 / 16.0;
        float w_t  = 5.0 / 16.0;
        float w_tl = 1.0 / 16.0;
        
        // Chaos: Error Randomness
        if (params.errorRandomness > 0.0) {
            float r = random(float2(coords) + float2(10.0), params.randomSeed);
            if (r < params.errorRandomness) {
                 float r1 = random(float2(coords) + float2(1.0), params.randomSeed);
                 float r2 = random(float2(coords) + float2(2.0), params.randomSeed);
                 float r3 = random(float2(coords) + float2(3.0), params.randomSeed);
                 float sum = r1 + r2 + r3 + 0.1;
                 w_tr = r1 / sum;
                 w_t  = r2 / sum;
                 w_tl = r3 / sum;
            }
        }
        
        // Read neighbors
        if (x + 1 < width) {
            float3 e = errorTexture.read(uint2(x+1, prevY)).rgb;
            errorFromAbove += e * w_tr;
        }
        {
            float3 e = errorTexture.read(uint2(x, prevY)).rgb;
            errorFromAbove += e * w_t;
        }
        if (x >= 1) {
            float3 e = errorTexture.read(uint2(x-1, prevY)).rgb;
            errorFromAbove += e * w_tl;
        }
        
        // 2. Read Pixel
        uint2 mappedCoords = uint2(floor(float(x) / scale) * scale, floor(float(y) / scale) * scale);
        
        if (params.pixelDisplace > 0.0 || params.turbulence > 0.0) {
             float2 chaosC = applySpatialChaos(float2(mappedCoords), params, coords);
             mappedCoords = uint2(clamp(chaosC, float2(0), float2(inputTexture.get_width()-1, inputTexture.get_height()-1)));
        }
        
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
        if (params.isGrayscale > 0) {
            pixelIn.r = applyQuantizationChaos(pixelIn.r, float2(coords), params);
            pixelIn.g = pixelIn.r;
            pixelIn.b = pixelIn.r;
        } else {
             pixelIn.r = applyQuantizationChaos(pixelIn.r, float2(coords), params);
             pixelIn.g = applyQuantizationChaos(pixelIn.g, float2(coords), params);
             pixelIn.b = applyQuantizationChaos(pixelIn.b, float2(coords), params);
        }

        float3 pixelOut = float3(0.0);
        float levels = max(1.0, params.colorDepth);
        if (levels <= 1.0) levels = 2.0;

        pixelOut.r = floor(pixelIn.r * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut.g = floor(pixelIn.g * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut.b = floor(pixelIn.b * (levels - 1.0) + 0.5) / (levels - 1.0);
        pixelOut = clamp(pixelOut, 0.0, 1.0);
        
        // 5. Diff & Propagate
        float3 diff = pixelIn - pixelOut;
        if (params.errorAmplify != 1.0) {
            diff *= params.errorAmplify;
        }
        
        outputTexture.write(float4(pixelOut, colorRaw.a), coords);
        
        float weight = 7.0 / 16.0;
        if (params.errorRandomness > 0.0) {
             float r = random(float2(coords), params.randomSeed);
             weight = mix(weight, r * 0.8, params.errorRandomness);
        }
        currentError = diff * weight;
    }
}

