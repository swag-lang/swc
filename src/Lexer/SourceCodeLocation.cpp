#include "pch.h"

#include "Core/Utf8.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"

namespace
{
    uint32_t calculateColumn(const CompilerInstance& ci, const uint8_t* content, uint32_t lineStart, uint32_t offset)
    {
        static constexpr uint32_t TAB_WIDTH = 4; // Standard tab width

        const uint32_t tabSize = ci.cmdLine().tabSize;
        uint32_t       column  = 1; // Columns are 1-based
        auto           ptr     = reinterpret_cast<const char*>(content + lineStart);
        const auto     end     = reinterpret_cast<const char*>(content + offset);

        while (ptr < end)
        {
            if (*ptr == '\t')
            {
                // Tab advances to the next multiple of tabSize
                column = ((column - 1) / tabSize + 1) * tabSize + 1;
                ptr++;
            }
            else
            {
                // Each UTF-8 character counts as one column
                auto [next, wc, n] = Utf8::decode(ptr, end);
                ptr                = next;
                column++;
            }
        }

        return column;
    }
}

void SourceCodeLocation::fromOffset(const CompilerInstance& ci, const SourceFile* inFile, uint32_t inOffset, uint32_t inLen)
{
    SWAG_ASSERT(inFile);

    file   = inFile;
    offset = inOffset;
    len    = inLen;

    const auto& lines = inFile->lexer().lines();
    if (lines.empty())
        return;

    // Use binary search to find the line containing this offset
    // upper_bound returns iterator to first element > offset
    auto it = std::ranges::upper_bound(lines, inOffset);

    if (it == lines.begin())
    {
        // Offset is before the first line start
        line   = 1;
        column = calculateColumn(ci, inFile->content().data(), 0, inOffset);
    }
    else
    {
        // Go back one element to get the line start <= offset
        --it;
        const size_t   lineIndex       = std::distance(lines.begin(), it);
        const uint32_t lineStartOffset = *it;

        // Line numbers are 1-based
        line = static_cast<uint32_t>(lineIndex + 1);

        // Column is the offset from the start of the line (1-based)
        column = calculateColumn(ci, inFile->content().data(), lineStartOffset, inOffset);
    }
}
