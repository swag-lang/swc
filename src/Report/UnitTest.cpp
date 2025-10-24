#include "pch.h"

#include "Diagnostic.h"
#include "Lexer/LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"
#include "Main/Global.h"
#include "Report/UnitTest.h"

SWC_BEGIN_NAMESPACE()

Result UnitTest::tokenize(CompilerContext& ctx)
{
    if (!ctx.cmdLine()->verify)
        return Result::Success;

    const auto  file     = ctx.sourceFile();
    const auto& langSpec = ctx.global()->langSpec();

    // Get all comments from the file
    Lexer lexer;
    SWAG_CHECK(lexer.tokenizeRaw(ctx));

    // Parse all comments to find a verify directive
    constexpr std::string_view needle = "expected-";
    for (const auto& token : file->lexOut().tokens())
    {
        auto   comment = token.toString(file);
        size_t pos     = 0;
        while (true)
        {
            pos = comment.find(needle, pos);
            if (pos == Utf8::npos)
                break;

            VerifierDirective directive;

            // Get directive kind
            const size_t start = pos + needle.size();
            size_t       i     = start;
            while (i < comment.size() && langSpec.isLetter(comment[i]))
                i++;
            const auto kindWord = comment.substr(start, i - start);
            if (kindWord == "error")
                directive.kind = DiagnosticSeverity::Error;
            else if (kindWord == "warning")
                directive.kind = DiagnosticSeverity::Warning;
            else
            {
                pos = i;
                continue;
            }

            // Location
            directive.myLoc.fromOffset(ctx, file, token.start + static_cast<uint32_t>(pos), static_cast<uint32_t>(needle.size()) + static_cast<uint32_t>(kindWord.size()));
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

    return Result::Success;
}

bool UnitTest::verify(const CompilerContext& ctx, const Diagnostic& diag) const
{
    if (directives_.empty())
        return false;

    for (auto& elem : diag.elements())
    {
        const auto loc = elem->location(ctx);

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

Result UnitTest::verify(CompilerContext& ctx) const
{
    for (const auto& directive : directives_)
    {
        if (!directive.touched)
        {
            Diagnostic diag(ctx.sourceFile());
            const auto elem = diag.addError(DiagnosticId::UnRaisedDirective);
            elem->setLocation(directive.myLoc);
            diag.report(ctx);
        }
    }

    return Result::Success;
}

SWC_END_NAMESPACE()
