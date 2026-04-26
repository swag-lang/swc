#include "pch.h"
#include "Compiler/Verify.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Consumes optional "@..." at position i and applies constraint to directive.
    // Returns a new index (i advanced), or leaves the directive at default if malformed.
    size_t parseLineConstraint(const LangSpec& langSpec, std::string_view comment, size_t i, VerifyDirective& directive)
    {
        const uint32_t baseLine = directive.myCodeRange.line;

        // default is exact base line unless "@..." overrides it
        directive.allowedLines.clear();
        directive.lineMin = baseLine;
        directive.lineMax = baseLine;

        if (i >= comment.size() || comment[i] != '@')
            return i;

        ++i; // consume '@'

        if (i < comment.size() && comment[i] == '*')
        {
            ++i;
            directive.allowedLines.clear();
            directive.lineMin = 0;
            directive.lineMax = 0;
            return i;
        }

        if (i < comment.size() && comment[i] == '(')
        {
            ++i; // consume '('
            std::vector<uint32_t> lines;

            while (i < comment.size())
            {
                while (i < comment.size() && langSpec.isBlank(static_cast<char8_t>(comment[i])))
                    ++i;

                const size_t save    = i;
                int          v       = 0;
                bool         hasSign = false;

                if (!Utf8Helper::parseSignedOrAbs(langSpec, comment, i, v, hasSign))
                {
                    i = save;
                    break;
                }

                if (hasSign)
                {
                    const int32_t lineValue = static_cast<int32_t>(baseLine) + v;
                    lines.push_back(lineValue > 0 ? static_cast<uint32_t>(lineValue) : 1u);
                }
                else
                {
                    lines.push_back(v > 0 ? static_cast<uint32_t>(v) : 1u);
                }

                while (i < comment.size() && langSpec.isBlank(static_cast<char8_t>(comment[i])))
                    ++i;

                if (i < comment.size() && comment[i] == ',')
                {
                    ++i;
                    continue;
                }
                break;
            }

            // consume until ')'
            while (i < comment.size() && comment[i] != ')')
                ++i;
            if (i < comment.size() && comment[i] == ')')
                ++i;

            if (!lines.empty())
            {
                directive.allowedLines = std::move(lines);
                directive.lineMin      = 0;
                directive.lineMax      = 0;
            }
            // else keep default exact(baseLine)

            return i;
        }

        // @+N / @-N / @+ / @- / @+A..+B
        {
            const size_t save    = i;
            int          offA    = 0;
            bool         hasSign = false;

            if (!Utf8Helper::parseSignedOrAbs(langSpec, comment, i, offA, hasSign) || !hasSign)
            {
                // For this form we require a sign; otherwise treat as malformed and keep default exact(baseLine).
                i = save;
                return i;
            }

            const int32_t  lineAValue = static_cast<int32_t>(baseLine) + offA;
            const uint32_t lineA      = lineAValue > 0 ? static_cast<uint32_t>(lineAValue) : 1u;

            // range?
            if (i + 1 < comment.size() && comment[i] == '.' && comment[i + 1] == '.')
            {
                i += 2;

                int  offB     = 0;
                bool hasSignB = false;
                if (!Utf8Helper::parseSignedOrAbs(langSpec, comment, i, offB, hasSignB) || !hasSignB)
                {
                    // malformed range end -> just treat as exact lineA
                    directive.allowedLines.clear();
                    directive.lineMin = lineA;
                    directive.lineMax = lineA;
                    return i;
                }

                const int32_t  lineBValue = static_cast<int32_t>(baseLine) + offB;
                const uint32_t lineB      = lineBValue > 0 ? static_cast<uint32_t>(lineBValue) : 1u;
                directive.allowedLines.clear();
                directive.lineMin = std::min(lineA, lineB);
                directive.lineMax = std::max(lineA, lineB);
                return i;
            }

            directive.allowedLines.clear();
            directive.lineMin = lineA;
            directive.lineMax = lineA;
            return i;
        }
    }
}

void Verify::tokenize(TaskContext& ctx)
{
    if (!ctx.cmdLine().sourceDrivenTest)
        return;

    srcView_ = &file_->ast().srcView();
    srcView_->trivia().clear();
    srcView_->triviaStart().clear();
    srcView_->identifiers().clear();
    directives_.clear();
    srcView_->clearParseFlags();

    if (ctx.cmdLine().lexOnly)
        srcView_->setLexOnly();
    else if (ctx.cmdLine().syntaxOnly)
        srcView_->setSyntaxOnly();
    else if (ctx.cmdLine().semaOnly)
        srcView_->setSemaOnly();

    // Get all comments from the file
    Lexer lexer;
    lexer.tokenizeRaw(ctx, *srcView_);

    // Parse all comments to find a verify directive
    for (const SourceTrivia& trivia : srcView_->trivia())
    {
        const std::string_view comment = trivia.tok.string(*srcView_);
        if (trivia.tok.is(TokenId::CommentLine))
        {
            tokenizeExpected(ctx, trivia, comment);
        }
    }
}

bool Verify::verifyExpected(const TaskContext& ctx, const Diagnostic& diag) const
{
    const std::scoped_lock lk(directivesMutex_);

    if (directives_.empty())
        return false;

    bool dismiss = false;
    for (size_t elemIndex = 0; elemIndex < diag.elements().size(); ++elemIndex)
    {
        const std::shared_ptr<DiagnosticElement>& elem = diag.elements()[elemIndex];
        const SourceCodeRange codeRange = elem->codeRange(0, ctx);
        for (const VerifyDirective& directive : directives_)
        {
            if (directive.touched)
                continue;

            if (directive.kind != elem->severity())
                continue;

            if (!directive.matchesLine(codeRange.line))
                continue;

            if (elem->idName().find(directive.match) == Utf8::npos &&
                elem->message().find(directive.match) == Utf8::npos)
                continue;

            directive.touched = true;
            if (elemIndex == 0)
                dismiss = true;
            break;
        }
    }

    return dismiss;
}

void Verify::verifyUntouchedExpected(TaskContext& ctx, const SourceView& srcView) const
{
    std::vector<SourceCodeRange> missingRanges;
    {
        const std::scoped_lock lk(directivesMutex_);
        missingRanges.reserve(directives_.size());
        for (const VerifyDirective& directive : directives_)
        {
            if (!directive.touched)
                missingRanges.push_back(directive.myCodeRange);
        }
    }

    // Reporting re-enters source-driven verification through Diagnostic::report,
    // so keep it outside the directives mutex to avoid recursive locking.
    for (const SourceCodeRange& missingRange : missingRanges)
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::unittest_err_not_raised, srcView.fileRef());
        diag.last().addSpan(missingRange, "");
        diag.report(ctx);
    }
}

void Verify::tokenizeExpected(const TaskContext& ctx, const SourceTrivia& trivia, std::string_view comment)
{
    const LangSpec& langSpec = ctx.global().langSpec();

    size_t pos = 0;
    while (true)
    {
        pos = comment.find(LangSpec::VERIFY_COMMENT_EXPECTED, pos);
        if (pos == std::string_view::npos)
            break;

        VerifyDirective directive;

        // Parse directive kind ("error", "warning", "note", etc.)
        const size_t start = pos + LangSpec::VERIFY_COMMENT_EXPECTED.size();
        size_t       i     = start;
        while (i < comment.size() && langSpec.isLetter(comment[i]))
            i++;
        const std::string_view word = comment.substr(start, i - start);
        if (word == "error")
            directive.kind = DiagnosticSeverity::Error;
        else if (word == "warning")
            directive.kind = DiagnosticSeverity::Warning;
        else if (word == "note")
            directive.kind = DiagnosticSeverity::Note;
        else if (word == "help")
            directive.kind = DiagnosticSeverity::Help;
        else
        {
            pos = i;
            continue;
        }

        // Base location info
        const uint32_t byteStart = trivia.tok.byteStart + static_cast<uint32_t>(pos);
        const uint32_t byteLen   = static_cast<uint32_t>(LangSpec::VERIFY_COMMENT_EXPECTED.size()) + static_cast<uint32_t>(word.size());
        directive.myCodeRange.fromOffset(ctx, *srcView_, byteStart, byteLen);
        directive.codeRange = directive.myCodeRange;

        // Handle @*, @+ etc. suffix
        // Handle @... suffix (line constraints)
        // Supported:
        //   @*                  => anywhere
        //   @+                  => +1
        //   @-                  => -1
        //   @+N / @-N           => relative offset
        //   @+A..+B / @-A..+B   => relative range (inclusive)
        //   @(+A,+B,...)        => one-of relative offsets list
        //   @(<abs>,<abs>,...)  => one-of absolute lines (if no sign)
        // Note:
        //   baseline is directive.myLoc.line (line of the directive comment token)
        i = parseLineConstraint(langSpec, comment, i, directive);

        // Find and parse all `{{ ... }}` blocks following this directive
        while (true)
        {
            const size_t open = comment.find("{{", i);
            if (open == std::string_view::npos)
                break;

            const size_t close = comment.find("}}", open + 2);
            if (close == std::string_view::npos)
                break;

            const Utf8 match = Utf8Helper::trim(comment.substr(open + 2, close - (open + 2)));

            VerifyDirective dir = directive;
            dir.match           = match;
            directives_.emplace_back(std::move(dir));

            i = close + 2;
        }

        pos = i;
    }
}

SWC_END_NAMESPACE();
