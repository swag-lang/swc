#include "pch.h"

#include "Diagnostic.h"
#include "Lexer/LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Report/UnitTest.h"

SWC_BEGIN_NAMESPACE()

void UnitTest::tokenizeOption(const Context& ctx, std::string_view comment)
{
    const auto  file     = ctx.sourceFile();
    const auto& langSpec = ctx.global().langSpec();

    size_t pos = 0;
    while (true)
    {
        const auto found = comment.find(LangSpec::VERIFY_COMMENT_OPTION, pos);
        if (found == std::string_view::npos)
            break;

        size_t i = found + LangSpec::VERIFY_COMMENT_OPTION.size();

        // Skip blanks and any non-ASCII noise safely
        while (i < comment.size() && langSpec.isBlank(static_cast<unsigned char>(comment[i])))
            ++i;

        // There can be multiple options after "swc-option"
        // Parse words until we hit something that's not an option token
        while (i < comment.size())
        {
            // Skip any extra blanks / non-ASCII between options
            while (i < comment.size() && langSpec.isBlank(static_cast<unsigned char>(comment[i])))
                ++i;

            // Collect the option token
            const size_t start = i;
            while (i < comment.size() && langSpec.isOption(static_cast<unsigned char>(comment[i])))
                ++i;

            // No token? we're done with this swc-option block
            if (i == start)
                break;

            const std::string_view kindWord = comment.substr(start, i - start);

            // Handle known options
            if (kindWord == "lex-only")
                file->addFlag(FileFlags::LexOnly);

            // If options might be comma-separated, skip trailing commas/spacers
            while (i < comment.size() && (langSpec.isBlank(static_cast<unsigned char>(comment[i])) || comment[i] == ','))
                ++i;
        }

        // Move past this occurrence so we can find the next one
        pos = std::max(i, found + LangSpec::VERIFY_COMMENT_OPTION.size());
        if (pos == found) // paranoia: guarantee forward progress on pathological inputs
            ++pos;
    }
}

void UnitTest::tokenizeExpected(const Context& ctx, const LexTrivia& trivia, std::string_view comment)
{
    const auto  file     = ctx.sourceFile();
    const auto& langSpec = ctx.global().langSpec();

    size_t pos = 0;
    while (true)
    {
        pos = comment.find(LangSpec::VERIFY_COMMENT_EXPECTED, pos);
        if (pos == Utf8::npos)
            break;

        UnitTestDirective directive;

        // Get directive word
        const size_t start = pos + LangSpec::VERIFY_COMMENT_EXPECTED.size();
        size_t       i     = start;
        while (i < comment.size() && langSpec.isLetter(comment[i]))
            i++;
        const auto word = comment.substr(start, i - start);
        if (word == "error")
            directive.kind = DiagnosticSeverity::Error;
        else if (word == "warning")
            directive.kind = DiagnosticSeverity::Warning;
        else
        {
            pos = i;
            continue;
        }

        // Location
        directive.myLoc.fromOffset(ctx, *file,
                                   trivia.token.byteStart + static_cast<uint32_t>(pos),
                                   static_cast<uint32_t>(LangSpec::VERIFY_COMMENT_EXPECTED.size()) + static_cast<uint32_t>(word.size()));
        directive.loc = directive.myLoc;

        // Parse location
        if (i < comment.size() && comment[i] == '@')
        {
            i++;
            if (i < comment.size())
            {
                if (comment[i] == '*')
                {
                    directive.loc.line = 0;
                    i++;
                }
                else if (comment[i] == '+')
                {
                    directive.loc.line++;
                    i++;
                }
            }
        }

        // Get directive string
        directive.match = comment.substr(i, comment.size());
        directive.match.trim();

        // One more
        directives_.emplace_back(directive);

        pos = i;
    }
}

Result UnitTest::tokenize(const Context& ctx)
{
    if (!ctx.cmdLine().verify)
        return Result::Success;

    Context lexerCtx(ctx);
    lexerCtx.setSourceFile(file_);

    // Get all comments from the file
    Lexer lexer;
    SWC_CHECK(lexer.tokenizeRaw(lexerCtx));

    // Parse all one-line comments to find a verify directive
    for (const auto& trivia : file_->lexOut().trivia())
    {
        const std::string_view comment = trivia.token.toString(*file_);
        tokenizeExpected(ctx, trivia, comment);
        tokenizeOption(ctx, comment);
    }

    return Result::Success;
}

bool UnitTest::verifyExpected(const Context& ctx, const Diagnostic& diag) const
{
    if (directives_.empty())
        return false;

    Context lexerCtx(ctx);
    lexerCtx.setSourceFile(file_);

    for (auto& elem : diag.elements())
    {
        const SourceCodeLocation loc = elem->location(lexerCtx);

        for (auto& directive : directives_)
        {
            if (directive.kind != elem->severity_)
                continue;
            if (directive.loc.line && directive.loc.line != loc.line)
                continue;

            if (elem->idName().find(directive.match) == Utf8::npos &&
                elem->message().find(directive.match) == Utf8::npos)
                continue;

            directive.touched = true;
            return true;
        }
    }

    return false;
}

Result UnitTest::verifyUntouchedExpected(const Context& ctx) const
{
    Context lexerCtx(ctx);
    lexerCtx.setSourceFile(file_);

    for (const auto& directive : directives_)
    {
        if (!directive.touched)
        {
            const auto diag = Diagnostic::raise(lexerCtx, DiagnosticId::UnRaisedDirective, file_);
            diag.last().setLocation(directive.myLoc);
        }
    }

    return file_->hasErrors() ? Result::Error : Result::Success;
}

SWC_END_NAMESPACE()
