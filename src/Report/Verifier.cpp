#include "pch.h"

#include "Diagnostic.h"
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Verifier.h"
#include <windows.h>

Result Verifier::tokenize(const CompilerInstance& ci, const CompilerContext& ctx)
{
    if (!ci.cmdLine().verify)
        return Result::Success;

    const auto file = ctx.sourceFile();

    // Get all comments from the file
    auto& lexer = file->lexer();
    SWAG_CHECK(lexer.tokenize(ci, ctx, LEXER_EXTRACT_COMMENTS_MODE));

    // Parse all comments to find a verify directive
    constexpr std::string_view needle = "expected-";
    for (const auto& token : lexer.tokens())
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
            size_t i = pos + needle.size();
            size_t j = i;
            while (j < comment.size() && std::isalpha(comment[j]))
                j++;
            const auto kindWord = comment.substr(i, j - i);
            if (kindWord == "error")
                directive.kind = DiagnosticKind::Error;
            else
            {
                pos = j;
                continue;
            }

            // Get directive string
            directive.match = comment.substr(j, comment.size());
            directive.match.trim();

            // Location
            directive.location.fromOffset(ci, file, token.start + static_cast<uint32_t>(pos), static_cast<uint32_t>(needle.size()) + static_cast<uint32_t>(kindWord.size()));

            // One more
            directives_.emplace_back(directive);

            pos = j;
        }
    }

    return Result::Success;
}

bool Verifier::verify(const CompilerInstance& ci, const Diagnostic& diag) const
{
    if (directives_.empty())
        return false;

    for (auto& elem : diag.elements())
    {
        const auto loc = elem->location(ci);

        for (auto& directive : directives_)
        {
            if (directive.kind != elem->kind_)
                continue;
            if (directive.location.line != loc.line)
                continue;

            if (elem->idName(ci).find(directive.match) == Utf8::npos &&
                elem->message(ci).find(directive.match) == Utf8::npos)
                continue;

            directive.touched = true;
            return true;
        }
    }

    return false;
}

Result Verifier::verify(const CompilerInstance& ci, const CompilerContext& ctx) const
{
    for (const auto& directive : directives_)
    {
        if (!directive.touched)
        {
            Diagnostic diag(ctx.sourceFile());
            const auto elem = diag.addError(DiagnosticId::UnRaisedDirective);
            elem->setLocation(directive.location);
            diag.report(ci);
        }
    }

    return Result::Success;
}
