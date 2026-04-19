#pragma once

SWC_BEGIN_NAMESPACE();

enum class FormatIndentStyle : uint8_t
{
    Preserve,
    Spaces,
    Tabs,
};

enum class FormatEndOfLineStyle : uint8_t
{
    Preserve,
    LF,
    CRLF,
};

struct FormatOptions
{
    bool preserveComments           = true;
    bool preserveBlankLines         = true;
    bool preserveBom                = true;
    bool preserveTrailingWhitespace = true;
    bool insertFinalNewline         = false;

    uint32_t indentWidth             = 4;
    uint32_t continuationIndentWidth = 4;

    FormatIndentStyle    indentStyle    = FormatIndentStyle::Preserve;
    FormatEndOfLineStyle endOfLineStyle = FormatEndOfLineStyle::Preserve;
};

SWC_END_NAMESPACE();
