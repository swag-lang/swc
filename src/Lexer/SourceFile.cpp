#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Diagnostic.h"

SourceFile::SourceFile(const fs::path& path) :
    path_(weakly_canonical(path))
{
}

Result SourceFile::loadContent(CompilerContext& ctx)
{
    if (!content_.empty())
        return Result::Success;

    std::ifstream file(path_, std::ios::binary | std::ios::ate);

    if (!file)
    {
        const auto diag = Diagnostic::error(DiagnosticId::CannotOpenFile, this);
        diag.last()->setLocation(this);
        diag.last()->addArgument(path_.string());
        diag.report(ctx);
        return Result::Error;
    }

    const auto fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    content_.resize(fileSize);

    if (!file.read(reinterpret_cast<char*>(content_.data()), fileSize))
    {
        const auto diag = Diagnostic::error(DiagnosticId::CannotReadFile, this);
        diag.last()->setLocation(this);
        diag.last()->addArgument(path_.string());
        diag.report(ctx);
        return Result::Error;
    }

    // Ensure we have at least 4 characters in the buffer
    content_.push_back(0);
    content_.push_back(0);
    content_.push_back(0);
    content_.push_back(0);

    return Result::Success;
}

Result SourceFile::tokenize(CompilerContext& ctx)
{
    SWAG_CHECK(verifier_.tokenize(ctx));
    return lexer_.tokenize(ctx);
}

Utf8 SourceFile::codeLine(const CompilerContext& ctx, uint32_t line) const
{
    line--;
    SWAG_ASSERT(line < lexer_.lines().size());

    const auto  offset      = lexer_.lines()[line];
    const auto  startBuffer = reinterpret_cast<const char*>(content_.data() + offset);
    const char* end;

    if (line == lexer_.lines().size() - 1)
        end = reinterpret_cast<const char*>(content_.data() + content_.size());
    else
        end = reinterpret_cast<const char*>(content_.data() + lexer_.lines()[line + 1]);

    auto buffer = startBuffer;
    bool hasTab = false;
    while (buffer + 1 < end && buffer[0] != '\n' && buffer[0] != '\r')
    {
        if (buffer[0] == '\t')
            hasTab = true;
        buffer++;
    }

    const auto result = std::string_view{startBuffer, buffer};
    if (!hasTab)
        return result;

    // Transform tabulations to blanks in order for columns to match
    const uint32_t tabSize = ctx.ci().cmdLine().tabSize;
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

std::string_view SourceFile::codeView(uint32_t offset, uint32_t len) const
{
    SWAG_ASSERT(offset + len <= content_.size());
    return std::string_view{reinterpret_cast<const char*>(content_.data() + offset), len};
}
