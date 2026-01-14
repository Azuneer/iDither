#include <metal_stdlib>
using namespace metal;

struct RenderParameters {
    float brightness;
    float contrast;
    float pixelScale;
    int algorithm; // 0: None, 1: Bayer 8x8, 2: Bayer 4x4
    int isGrayscale;
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

// Bayer 4x4 Matrix
constant float bayer4x4[4][4] = {
    { 0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0 },
    {12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0 },
    { 3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0 },
    {15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0 }
};

kernel void ditherShader(texture2d<float, access::read> inputTexture [[texture(0)]],
                         texture2d<float, access::write> outputTexture [[texture(1)]],
                         constant RenderParameters &params [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // 1. Pixelation (Downsampling)
    float scale = max(1.0, params.pixelScale);
    uint2 sourceCoord = uint2(floor(float(gid.x) / scale) * scale, floor(float(gid.y) / scale) * scale);
    
    // Clamp to texture bounds
    sourceCoord.x = min(sourceCoord.x, inputTexture.get_width() - 1);
    sourceCoord.y = min(sourceCoord.y, inputTexture.get_height() - 1);
    
    float4 color = inputTexture.read(sourceCoord);
    
    // 2. Color Adjustment (Brightness & Contrast)
    float3 rgb = color.rgb;
    rgb = rgb + params.brightness;
    rgb = (rgb - 0.5) * params.contrast + 0.5;
    
    // Grayscale conversion (Luma)
    float luma = dot(rgb, float3(0.299, 0.587, 0.114));
    
    if (params.isGrayscale > 0) {
        rgb = float3(luma);
    }
    
    // 3. Dithering
    if (params.algorithm == 1) { // Bayer 8x8
        // Map current pixel to matrix coordinates
        // We use the original gid (screen coordinates) for the matrix pattern to keep it stable across pixelation blocks?
        // OR we use the sourceCoord (pixelated coordinates) to make the dither pattern scale with the pixels?
        // Usually, dither is applied at screen resolution, but for "retro pixel art" look, the dither pattern usually matches the "big pixel" size.
        // Let's try using the scaled coordinate index: sourceCoord / scale
        
        uint x = uint(sourceCoord.x / scale) % 8;
        uint y = uint(sourceCoord.y / scale) % 8;
        float threshold = bayer8x8[y][x];
        
        // Apply threshold
        rgb = (luma > threshold) ? float3(1.0) : float3(0.0);
        
    } else if (params.algorithm == 2) { // Bayer 4x4
        uint x = uint(sourceCoord.x / scale) % 4;
        uint y = uint(sourceCoord.y / scale) % 4;
        float threshold = bayer4x4[y][x];
        
        rgb = (luma > threshold) ? float3(1.0) : float3(0.0);
    }
    
    outputTexture.write(float4(rgb, color.a), gid);
}
