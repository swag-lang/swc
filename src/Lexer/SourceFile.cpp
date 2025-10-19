#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Report/Diagnostic.h"

SourceFile::SourceFile(std::filesystem::path path) :
    path_(std::move(path)),
    lexer_()
{
}

Result SourceFile::loadContent(const CompilerInstance& ci, const CompilerContext& ctx)
{
    if (!content_.empty())
        return Result::Success;

    std::ifstream file(path_, std::ios::binary | std::ios::ate);

    if (!file)
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::CannotOpenFile);
        elem->setLocation(this);
        elem->addArgument(path_.string());
        return diag.report(ci);
    }

    const auto fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    content_.resize(fileSize);

    if (!file.read(reinterpret_cast<char*>(content_.data()), fileSize))
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::CannotReadFile);
        elem->setLocation(this);
        elem->addArgument(path_.string());
        return diag.report(ci);
    }

    // Ensure we have at least 4 characters in the buffer
    content_.push_back(0);
    content_.push_back(0);
    content_.push_back(0);
    content_.push_back(0);

    return Result::Success;
}

Result SourceFile::tokenize(const CompilerInstance& ci, const CompilerContext& ctx)
{
    SWAG_CHECK(verifier_.tokenize(ci, ctx));
    return lexer_.tokenize(ci, ctx);
}

Utf8 SourceFile::codeLine(const CompilerInstance& ci, uint32_t line) const
{
    line--;
    SWAG_ASSERT(line < lexer_.lines().size());

    Utf8       result;
    const auto offset      = lexer_.lines()[line];
    const auto startBuffer = reinterpret_cast<const char*>(content_.data() + offset);

    if (line == lexer_.lines().size() - 1)
    {
        auto       buffer = startBuffer;
        const auto end    = reinterpret_cast<const char*>(content_.data() + content_.size());
        while (buffer + 1 < end && buffer[0] != '\n' && buffer[0] != '\r')
            buffer++;
        result = Utf8{std::string_view{startBuffer, buffer}};
    }
    else
    {
        const auto end = reinterpret_cast<const char*>(content_.data() + lexer_.lines()[line + 1]);
        result         = Utf8{std::string_view{startBuffer, end}};
    }

    // Transform tabulations to blanks in order for columns to match
    const uint32_t tabSize = ci.cmdLine().tabSize;
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
