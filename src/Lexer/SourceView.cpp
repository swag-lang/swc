#include "pch.h"
#include "Lexer/SourceView.h"
#include "Main/CommandLine.h"
#include "Main/TaskContext.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()

SourceView::SourceView(SourceViewRef ref, const SourceFile* file) :
    ref_(ref)
{
    if (file)
    {
        fileRef_    = file->ref();
        stringView_ = file->sourceView();
    }
}

Utf8 SourceView::codeLine(const TaskContext& ctx, uint32_t line) const
{
    line--;
    SWC_ASSERT(line < lines_.size());

    const auto  offset      = lines_[line];
    const auto  startBuffer = stringView_.data() + offset;
    const char* end;

    if (line == lines_.size() - 1)
        end = stringView_.data() + stringView_.size();
    else
        end = stringView_.data() + lines_[line + 1];

    auto buffer = startBuffer;
    bool hasTab = false;
    while (buffer < end && buffer[0] != '\n' && buffer[0] != '\r')
    {
        if (buffer[0] == '\t')
            hasTab = true;
        buffer++;
    }

    const auto result = std::string_view{startBuffer, buffer};
    if (!hasTab)
        return result;

    // Transform tabulations to blanks in order for columns to match
    const uint32_t tabSize = ctx.cmdLine().tabSize;
    Utf8           expanded;
    expanded.reserve(result.size());

    size_t column = 0;
    for (const char c : result)
    {
        if (c == '\t')
        {
            const size_t spaces = tabSize - (column % tabSize);
            expanded.append(spaces, ' ');
            column += spaces;
        }
        else
        {
            expanded.push_back(c);
            column++;
        }
    }

    return expanded;
}

std::string_view SourceView::codeView(uint32_t offset, uint32_t len) const
{
    SWC_ASSERT(offset + len <= stringView_.size());
    return std::string_view{stringView_.data() + offset, len};
}

std::pair<uint32_t, uint32_t> SourceView::triviaRangeForToken(TokenRef tok) const
{
    const uint32_t i = tok.get();
    SWC_ASSERT(i + 1 < triviaStart_.size());
    return {triviaStart_[i], triviaStart_[i + 1]};
}

SWC_END_NAMESPACE()
