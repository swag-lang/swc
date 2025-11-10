#pragma once

SWC_BEGIN_NAMESPACE()

class TaskContext;

struct RgbColor
{
    unsigned char r, g, b;
};

enum class LogColor
{
    Reset,
    Bold,
    Dim,

    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,

    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightMagenta,
    BrightCyan,
    Gray,
};

namespace LogColorHelper
{
    Utf8     colorToAnsi(uint32_t r, uint32_t g, uint32_t b);
    Utf8     toAnsi(const TaskContext& ctx, LogColor c);
    void     rgbToHsl(const RgbColor& color, float* h, float* s, float* l);
    float    hueToRgb(float p, float q, float t);
    RgbColor hslToRgb(float h, float s, float l);
}

SWC_END_NAMESPACE()
