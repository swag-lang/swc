#pragma once

SWC_BEGIN_NAMESPACE();

namespace Format
{
    enum class IndentStyle : uint8_t
    {
        Spaces,
        Tabs,
    };

    enum class EndOfLineStyle : uint8_t
    {
        Preserve,
        LF,
        CRLF,
    };

    struct Options
    {
        bool exactRoundTrip             = true;
        bool preserveComments           = true;
        bool preserveBlankLines         = true;
        bool preserveWhitespace         = true;
        bool preserveEndOfLine          = true;
        bool preserveBom                = true;
        bool preserveTrailingWhitespace = true;
        bool insertFinalNewline         = false;

        uint32_t indentWidth             = 4;
        uint32_t continuationIndentWidth = 4;

        IndentStyle    indentStyle    = IndentStyle::Spaces;
        EndOfLineStyle endOfLineStyle = EndOfLineStyle::Preserve;
    };
}

SWC_END_NAMESPACE();
