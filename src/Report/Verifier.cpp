#include "pch.h"

#include "Diagnostic.h"
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Verifier.h"

Result Verifier::tokenize(const CompilerInstance& ci, const CompilerContext& ctx)
{
    if (!ci.cmdLine().verify)
        return Result::Success;

    const auto file = ctx.sourceFile();

    // Get all comments from the file
    Lexer lexer;
    SWAG_CHECK(lexer.tokenize(ci, ctx, LEXER_EXTRACT_COMMENTS_MODE));

    // Parse all comments to find a verify directive
    for (const auto& token : lexer.tokens())
    {
        auto comment = token.toString(file);

        std::string_view           sv(comment);
        size_t                     pos    = 0;
        constexpr std::string_view needle = "expected-";
        while (true)
        {
            pos = comment.find(needle, pos);
            if (pos == std::string::npos)
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
                i = j;
                continue;
            }

            // Get directive string
            directive.match = comment.substr(j, comment.size());

            // One more
            directives_.emplace_back(directive);
        }
    }

    return Result::Success;
}
