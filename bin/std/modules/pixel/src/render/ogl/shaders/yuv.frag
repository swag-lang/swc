#version 330 core
#include base

// A picture the decoder handed over unconverted: full-resolution luma on the brush texture and
// the two chroma planes beside it. Sampling them with the same coordinates upsamples the chroma
// for free, which is exactly the two-by-two spread the format defines.
uniform sampler2D inChromaB;
uniform sampler2D inChromaR;
uniform vec4 yuvLumaRed; // Luma offset, luma scale, red-from-Cr, blue-from-Cb.
uniform vec2 yuvGreen;   // Green-from-Cb and green-from-Cr.

in vec4 vcolor;
in vec2 vuv0;
in vec2 vpaintPos;

out vec4 color;

void main()
{
    // The planes arrive in the order a decoder reconstructs them, first row at the top, while
    // every packed image this renderer uploads is stored bottom-up. The vertex stage resolves
    // uv for the bottom-up case, so the one program that knows the storage class undoes it.
    vec2 uv = vec2(vuv0.x, 1.0 - vuv0.y);

    // Fixed-point terms match Pixel.Yuv420View for the range and matrix carried by this texture.
    float luma = texture(inTexture0, uv).r * 255.0;
    float d    = texture(inChromaB, uv).r * 255.0 - 128.0;
    float e    = texture(inChromaR, uv).r * 255.0 - 128.0;
    float c    = max(luma - yuvLumaRed.x, 0.0) * yuvLumaRed.y;

    vec3 rgb = vec3(c + yuvLumaRed.z * e + 128.0,
                    c + yuvGreen.x * d + yuvGreen.y * e + 128.0,
                    c + yuvLumaRed.w * d + 128.0);

    color = vcolor * vec4(clamp(rgb / 256.0, 0.0, 255.0) / 255.0, 1.0);
    applyBlendingMode(color);
}
