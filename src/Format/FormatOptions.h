#pragma once

SWC_BEGIN_NAMESPACE();

enum class FormatIndentStyle : uint8_t
{
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
    bool preserveWhitespace         = true;
    bool preserveEndOfLine          = true;
    bool preserveBom                = true;
    bool preserveTrailingWhitespace = true;
    bool insertFinalNewline         = false;

    uint32_t indentWidth             = 4;
    uint32_t continuationIndentWidth = 4;

    FormatIndentStyle    indentStyle    = FormatIndentStyle::Spaces;
    FormatEndOfLineStyle endOfLineStyle = FormatEndOfLineStyle::Preserve;
};

SWC_END_NAMESPACE();
