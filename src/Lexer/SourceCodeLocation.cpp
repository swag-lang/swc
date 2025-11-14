#include "pch.h"

#include "Core/Utf8Helper.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/TaskContext.h"
#include "Os/Os.h"

SWC_BEGIN_NAMESPACE()

class CompilerInstance;
namespace
{
    uint32_t calculateColumn(const TaskContext& ctx, const char8_t* content, uint32_t lineStart, uint32_t offset)
    {
        const uint32_t tabSize = ctx.cmdLine().tabSize;
        uint32_t       column  = 1; // Columns are 1-based
        auto           ptr     = content + lineStart;
        const auto     end     = content + offset;

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
                auto [next, wc, n] = Utf8Helper::decodeOneChar(ptr, end);
                if (!next)
                    ptr++;
                else
                    ptr = next;
                column++;
            }
        }

        return column;
    }
}

void SourceCodeLocation::fromOffset(const TaskContext& ctx, const LexerOutput& lex, uint32_t inOffset, uint32_t inLen)
{
    if (inLen == 0)
        return;
    if (inOffset >= lex.sourceView().size())
        return;

    lexOut = &lex;
    offset = inOffset;
    len    = inLen;

    const auto& lines = lex.lines();
    if (lines.empty())
        return;

    // Use binary search to find the line containing this offset
    // upper_bound returns iterator to first element > offset
    auto it = std::ranges::upper_bound(lines, inOffset);

    if (it == lines.begin())
    {
        // Offset is before the first line start
        line   = 1;
        column = calculateColumn(ctx, reinterpret_cast<const char8_t*>(lex.sourceView().data()), 0, inOffset);
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
        column = calculateColumn(ctx, reinterpret_cast<const char8_t*>(lex.sourceView().data()), lineStartOffset, inOffset);
    }
}

SWC_END_NAMESPACE()
