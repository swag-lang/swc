#version 330 core
#include base

// A picture the decoder handed over unconverted: full-resolution luma on the brush texture and
// the two chroma planes beside it. Sampling them with the same coordinates upsamples the chroma
// for free, which is exactly the two-by-two spread the format defines.
uniform sampler2D inChromaB;
uniform sampler2D inChromaR;

in vec4 vcolor;
in vec2 vuv0;
in vec2 vpaintPos;

out vec4 color;

void main()
{
    // The limited-range BT.601 arithmetic every decoder in this repository uses, written in the
    // same fixed-point terms so the picture on screen matches the one Pixel.Yuv420View produces.
    float luma = texture(inTexture0, vuv0).r * 255.0;
    float d    = texture(inChromaB, vuv0).r * 255.0 - 128.0;
    float e    = texture(inChromaR, vuv0).r * 255.0 - 128.0;
    float c    = max(luma - 16.0, 0.0) * 298.0;

    vec3 rgb = vec3(c + 409.0 * e + 128.0,
                    c - 100.0 * d - 208.0 * e + 128.0,
                    c + 516.0 * d + 128.0);

    color = vcolor * vec4(clamp(rgb / 256.0, 0.0, 255.0) / 255.0, 1.0);
    applyBlendingMode(color);
}
