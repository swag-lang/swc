#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"

SWC_BEGIN_NAMESPACE();

Utf8 LogColorHelper::colorToAnsi(uint32_t r, uint32_t g, uint32_t b)
{
    return std::format("\x1b[38;2;{};{};{}m", r, g, b);
}

Utf8 LogColorHelper::toAnsi(const TaskContext& ctx, LogColor c)
{
    if (!ctx.cmdLine().logColor)
        return "";

    using enum LogColor;
    switch (c)
    {
        case Reset:
        default:
            return "\x1b[0m";
        case Bold:
            return "\x1b[1m";
        case Dim:
            return "\x1b[2m";

        case Red:
            return "\x1b[31m";
        case Green:
            return "\x1b[32m";
        case Yellow:
            return "\x1b[33m";
        case Blue:
            return "\x1b[34m";
        case Magenta:
            return "\x1b[35m";
        case Cyan:
            return "\x1b[36m";
        case White:
            return "\x1b[37m";

        case Gray:
            return "\x1b[90m";
        case BrightRed:
            return "\x1b[91m";
        case BrightGreen:
            return "\x1b[92m";
        case BrightYellow:
            return "\x1b[93m";
        case BrightBlue:
            return "\x1b[94m";
        case BrightMagenta:
            return "\x1b[95m";
        case BrightCyan:
            return "\x1b[96m";
    }
}

void LogColorHelper::rgbToHsl(const RgbColor& color, float* h, float* s, float* l)
{
    const float r = static_cast<float>(color.r) / 255.0f;
    const float g = static_cast<float>(color.g) / 255.0f;
    const float b = static_cast<float>(color.b) / 255.0f;

    const float maxVal = fmaxf(fmaxf(r, g), b);
    const float minVal = fminf(fminf(r, g), b);

    *l = (maxVal + minVal) / 2;

    if (maxVal == minVal)
    {
        *h = *s = 0;
    }
    else
    {
        const float d = maxVal - minVal;
        *s            = *l > 0.5f ? d / (2 - maxVal - minVal) : d / (maxVal + minVal);

        if (maxVal == r)
        {
            *h = (g - b) / d + (g < b ? 6.0f : 0.0f);
        }
        else if (maxVal == g)
        {
            *h = (b - r) / d + 2;
        }
        else if (maxVal == b)
        {
            *h = (r - g) / d + 4;
        }
        *h /= 6;
    }
}

float LogColorHelper::hueToRgb(float p, float q, float t)
{
    if (t < 0)
        t += 1;
    if (t > 1)
        t -= 1;
    if (t < 1.0f / 6)
        return p + (q - p) * 6 * t;
    if (t < 1.0f / 2)
        return q;
    if (t < 2.0f / 3)
        return p + (q - p) * (2.0f / 3 - t) * 6;
    return p;
}

RgbColor LogColorHelper::hslToRgb(float h, float s, float l)
{
    float r, g, b;

    if (s == 0)
    {
        r = g = b = l;
    }
    else
    {
        const float q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        const float p = 2 * l - q;

        r = hueToRgb(p, q, h + 1.0f / 3);
        g = hueToRgb(p, q, h);
        b = hueToRgb(p, q, h - 1.0f / 3);
    }

    RgbColor result;
    result.r = static_cast<char8_t>(r * 255.0f);
    result.g = static_cast<char8_t>(g * 255.0f);
    result.b = static_cast<char8_t>(b * 255.0f);
    return result;
}

SWC_END_NAMESPACE();
