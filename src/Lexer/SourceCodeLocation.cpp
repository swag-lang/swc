#include "pch.h"

#include "Lexer/SourceCodeLocation.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"

namespace
{
    uint32_t calculateColumn(const uint8_t* content, uint32_t lineStart, uint32_t offset)
    {
        constexpr uint32_t tabWidth = 4; // Standard tab width

        uint32_t column = 1; // Columns are 1-based
        for (uint32_t i = lineStart; i < offset; ++i)
        {
            if (content[i] == '\t')
                column = ((column - 1) / tabWidth + 1) * tabWidth + 1;
            else
                column++;
        }

        return column;
    }
}

void SourceCodeLocation::fromOffset(const SourceFile* inFile, uint32_t inOffset, uint32_t inLen)
{
    SWAG_ASSERT(!inFile);
    
    file = inFile;
    offset = inOffset;
    len    = inLen;

    const auto& lines = inFile->lexer().lines;
    if (lines.empty())
        return;

    // Use binary search to find the line containing this offset
    // upper_bound returns iterator to first element > offset
    auto it = std::ranges::upper_bound(lines, inOffset);

    if (it == lines.begin())
    {
        // Offset is before the first line start
        line   = 1;
        column = calculateColumn(inFile->content().data(), 0, inOffset);
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
        column = calculateColumn(inFile->content().data(), lineStartOffset, inOffset);
    }
}
