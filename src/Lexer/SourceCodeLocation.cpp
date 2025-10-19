#include "pch.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"

void SourceCodeLocation::fromOffset(const SourceFile* file, uint32_t offset, uint32_t len)
{
    this->file   = file;
    this->offset = offset;
    this->len    = len;

    if (!file)
        return;

    const auto& lines = file->lexer().lines;
    if (lines.empty())
        return;

    // Use binary search to find the line containing this offset
    // upper_bound returns iterator to first element > offset
    auto it = std::ranges::upper_bound(lines, offset);

    if (it == lines.begin())
    {
        // Offset is before the first line start
        this->line   = 1;
        this->column = offset + 1;
    }
    else
    {
        // Go back one element to get the line start <= offset
        --it;
        const size_t lineIndex = std::distance(lines.begin(), it);

        // Line numbers are 1-based
        this->line = static_cast<uint32_t>(lineIndex + 1);

        // Column is the offset from the start of the line (1-based)
        this->column = offset - *it + 1;
    }
}
