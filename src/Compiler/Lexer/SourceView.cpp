#include "pch.h"
#include "Compiler/Lexer/SourceView.h"
#include "Backend/Runtime.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

SourceView::SourceView(SourceViewRef ref, const SourceFile* file) :
    ref_(ref)
{
    if (file)
    {
        file_         = file;
        fileRef_      = file->ref();
        ownerFileRef_ = fileRef_;
        stringView_   = file->sourceView();
    }

#if SWC_HAS_REF_DEBUG_INFO
    ref_.dbgPtr = this;
#endif
}

Utf8 SourceView::codeLine(const TaskContext& ctx, uint32_t line) const
{
    line--;
    SWC_ASSERT(line < lines_.size());

    const auto  offset      = lines_[line];
    const auto* startBuffer = stringView_.data() + offset;
    const char* end;

    if (line == lines_.size() - 1)
        end = stringView_.data() + stringView_.size();
    else
        end = stringView_.data() + lines_[line + 1];

    const auto* buffer = startBuffer;
    bool        hasTab = false;
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

SourceCodeRange SourceView::tokenCodeRange(const TaskContext& ctx, TokenRef tokRef) const
{
    return token(tokRef).codeRange(ctx, *this);
}

uint32_t SourceView::clampLine(uint32_t line) const
{
    if (!line)
        return 1;
    return std::min(line, static_cast<uint32_t>(lines_.size()));
}

std::pair<uint32_t, uint32_t> SourceView::lineBounds(uint32_t line) const
{
    const uint32_t start = lines_[line - 1];
    uint32_t       end   = static_cast<uint32_t>(stringView_.size());
    if (line < lines_.size())
        end = lines_[line];
    return {start, std::max(start, end)};
}

void SourceView::codeRangeFromRuntimeLocation(const TaskContext& ctx, const Runtime::SourceCodeLocation& location, SourceCodeRange& outCodeRange) const
{
    outCodeRange = {};
    SWC_ASSERT(!stringView_.empty());
    SWC_ASSERT(!lines_.empty());

    const uint32_t startLine = clampLine(location.lineStart);
    uint32_t       endLine   = clampLine(location.lineEnd);
    endLine                  = std::max(endLine, startLine);

    const auto [startLineOffset, startLineEndOffset] = lineBounds(startLine);
    const auto [endLineOffset, endLineEndOffset]     = lineBounds(endLine);

    uint32_t startColumn = location.colStart;
    if (!startColumn)
        startColumn = 1;

    uint32_t endColumn = location.colEnd;
    if (!endColumn)
        endColumn = startColumn + 1;

    const uint32_t maxStartColumnOffset = startLineEndOffset > startLineOffset ? startLineEndOffset - startLineOffset - 1 : 0;
    const uint32_t startColumnOffset    = std::min(startColumn - 1, maxStartColumnOffset);
    uint32_t       offset               = startLineOffset + startColumnOffset;

    const uint32_t maxEndColumnOffset = endLineEndOffset - endLineOffset;
    uint32_t       endOffset          = endLineOffset + std::min(endColumn - 1, maxEndColumnOffset);
    if (endOffset <= offset)
        endOffset = std::min<uint32_t>(offset + 1, static_cast<uint32_t>(stringView_.size()));

    if (offset >= stringView_.size())
        offset = static_cast<uint32_t>(stringView_.size() - 1);
    if (endOffset > stringView_.size())
        endOffset = static_cast<uint32_t>(stringView_.size());

    outCodeRange.fromOffset(ctx, *this, offset, std::max(1u, endOffset - offset));
    SWC_ASSERT(outCodeRange.srcView != nullptr);
    SWC_ASSERT(outCodeRange.len != 0);
}

std::string_view SourceView::tokenString(TokenRef tokRef) const
{
    return token(tokRef).string(*this);
}

TokenRef SourceView::findRightFrom(TokenRef startRef, std::initializer_list<TokenId> ids) const
{
    const uint32_t start = startRef.get();
    const uint32_t n     = numTokens();

    for (uint32_t i = start; i < n; ++i)
    {
        const TokenId tokId = tokens_[i].id;
        for (const TokenId wanted : ids)
        {
            if (tokId == wanted)
                return TokenRef(i);
        }
    }

    return TokenRef::invalid();
}

TokenRef SourceView::findLeftFrom(TokenRef startRef, std::initializer_list<TokenId> ids) const
{
    auto i = static_cast<int32_t>(startRef.get());
    for (; i >= 0; --i)
    {
        const TokenId tokId = tokens_[i].id;
        for (const TokenId wanted : ids)
        {
            if (tokId == wanted)
                return TokenRef(static_cast<uint32_t>(i));
        }
    }

    return TokenRef::invalid();
}

SWC_END_NAMESPACE();
