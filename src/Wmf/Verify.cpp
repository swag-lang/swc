#include "pch.h"
#include "Wmf/Verify.h"
#include "Core/Utf8Helper.h"
#include "Lexer/LangSpec.h"
#include "Lexer/Lexer.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

void Verify::tokenizeOption(const TaskContext& ctx, std::string_view comment)
{
    const auto& langSpec = ctx.global().langSpec();

    size_t pos = 0;
    while (true)
    {
        const auto found = comment.find(LangSpec::VERIFY_COMMENT_OPTION, pos);
        if (found == std::string_view::npos)
            break;

        size_t i = found + LangSpec::VERIFY_COMMENT_OPTION.size();

        // Skip blanks and any non-ASCII noise safely
        while (i < comment.size() && langSpec.isBlank(static_cast<char8_t>(comment[i])))
            ++i;

        // There can be multiple options after "swc-option"
        // Parse words until we hit something that's not an option token
        while (i < comment.size())
        {
            // Skip any extra blanks / non-ASCII between options
            while (i < comment.size() && langSpec.isBlank(static_cast<char8_t>(comment[i])))
                ++i;

            // Collect the option token
            const size_t start = i;
            while (i < comment.size() && langSpec.isOption(static_cast<char8_t>(comment[i])))
                ++i;

            // No token? we're done with this swc-option block
            if (i == start)
                break;

            const std::string_view kindWord = comment.substr(start, i - start);

            // Handle known options
            if (kindWord == "lex-only")
                flags_.add(VerifyFlagsE::LexOnly);

            // If options might be comma-separated, skip trailing commas/spacers
            while (i < comment.size() && (langSpec.isBlank(static_cast<char8_t>(comment[i])) || comment[i] == ','))
                ++i;
        }

        // Move past this occurrence so we can find the next one
        pos = std::max(i, found + LangSpec::VERIFY_COMMENT_OPTION.size());
        if (pos == found) // paranoia: guarantee forward progress on pathological inputs
            ++pos;
    }
}

void Verify::tokenizeExpected(const TaskContext& ctx, const SourceTrivia& trivia, std::string_view comment)
{
    const auto& langSpec = ctx.global().langSpec();

    size_t pos = 0;
    while (true)
    {
        pos = comment.find(LangSpec::VERIFY_COMMENT_EXPECTED, pos);
        if (pos == std::string_view::npos)
            break;

        VerifyDirective directive;

        // Parse directive kind ("error", "warning", etc.)
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

        // Base location info
        const auto byteStart = trivia.tok.byteStart + static_cast<uint32_t>(pos);
        const auto byteLen   = static_cast<uint32_t>(LangSpec::VERIFY_COMMENT_EXPECTED.size()) + static_cast<uint32_t>(word.size());
        directive.myLoc.fromOffset(ctx, *srcView_, byteStart, byteLen);
        directive.loc = directive.myLoc;

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
        //
        // Note: baseline is directive.myLoc.line (line of the directive comment token)
        directive.lineMin = directive.loc.line;
        directive.lineMax = directive.loc.line;

        auto isDigit = [](char c) {
            return c >= '0' && c <= '9';
        };

        auto parseInt = [&](size_t& p) -> int {
            // parse unsigned integer; caller handles sign
            int  v   = 0;
            bool any = false;
            while (p < comment.size() && isDigit(comment[p]))
            {
                any = true;
                v   = v * 10 + (comment[p] - '0');
                ++p;
            }
            return any ? v : -1; // -1 means "missing"
        };

        auto parseSigned = [&](size_t& p) -> int {
            int sign = +1;
            if (p < comment.size() && (comment[p] == '+' || comment[p] == '-'))
            {
                sign = (comment[p] == '-') ? -1 : +1;
                ++p;
            }

            const size_t before = p;
            const int    mag    = parseInt(p);
            if (mag < 0)
            {
                // no digits: treat bare "+" or "-" as 1 if the sign was explicit,
                // otherwise (no sign and no digits) it's invalid.
                if (before != p) // shouldn't happen
                    return 0;

                // If there was a sign char we consumed, accept implicit 1.
                // We can detect that by checking comment[before-1] was +/-
                if (before > 0 && (comment[before - 1] == '+' || comment[before - 1] == '-'))
                    return sign * 1;

                return 0;
            }
            return sign * mag;
        };

        auto setAnywhere = [&]() {
            directive.lineMin = 0;
            directive.lineMax = 0;
            directive.allowedLines.clear();
        };

        auto setExactLine = [&](uint32_t line) {
            directive.allowedLines.clear();
            directive.lineMin = line;
            directive.lineMax = line;
        };

        auto setRange = [&](uint32_t a, uint32_t b) {
            directive.allowedLines.clear();
            directive.lineMin = std::min(a, b);
            directive.lineMax = std::max(a, b);
        };

        if (i < comment.size() && comment[i] == '@')
        {
            ++i;

            const uint32_t baseLine = directive.myLoc.line; // line of the directive itself

            if (i < comment.size() && comment[i] == '*')
            {
                ++i;
                setAnywhere();
            }
            else if (i < comment.size() && comment[i] == '(')
            {
                // @(+1,+2) or @(12,14) etc.
                ++i;

                directive.allowedLines.clear();

                while (i < comment.size())
                {
                    // skip blanks
                    while (i < comment.size() && langSpec.isBlank(static_cast<char8_t>(comment[i])))
                        ++i;

                    // parse signed or unsigned
                    size_t save     = i;
                    int    offOrAbs = parseSigned(i);

                    if (i == save)
                        break;

                    // If token had an explicit sign, treat as relative; otherwise absolute.
                    bool hasSign = (save < comment.size() && (comment[save] == '+' || comment[save] == '-'));

                    uint32_t line = 0;
                    if (hasSign)
                    {
                        int32_t v = static_cast<int32_t>(baseLine) + offOrAbs;
                        line      = (v > 0) ? static_cast<uint32_t>(v) : 1u;
                    }
                    else
                    {
                        // absolute (1-based line numbers assumed)
                        line = (offOrAbs > 0) ? static_cast<uint32_t>(offOrAbs) : 1u;
                    }

                    directive.allowedLines.push_back(line);

                    // skip blanks
                    while (i < comment.size() && langSpec.isBlank(static_cast<char8_t>(comment[i])))
                        ++i;

                    if (i < comment.size() && comment[i] == ',')
                    {
                        ++i;
                        continue;
                    }
                    break;
                }

                // consume to ')'
                while (i < comment.size() && comment[i] != ')')
                    ++i;
                if (i < comment.size() && comment[i] == ')')
                    ++i;

                // If list ended up empty, fall back to exact base line
                if (directive.allowedLines.empty())
                    setExactLine(baseLine);
                else
                {
                    directive.lineMin = 0;
                    directive.lineMax = 0; // ignored when allowedLines is non-empty
                }
            }
            else
            {
                // @+N / @-N / @+ / @- / @+A..+B
                size_t save = i;
                int    offA = parseSigned(i);
                if (i == save)
                {
                    // malformed => ignore constraint and keep exact base line
                    setExactLine(baseLine);
                }
                else
                {
                    uint32_t lineA = 1;
                    {
                        int32_t v = static_cast<int32_t>(baseLine) + offA;
                        lineA     = (v > 0) ? static_cast<uint32_t>(v) : 1u;
                    }

                    // range?
                    if (i + 1 < comment.size() && comment[i] == '.' && comment[i + 1] == '.')
                    {
                        i += 2;
                        int offB = parseSigned(i);

                        uint32_t lineB = lineA;
                        {
                            int32_t v = static_cast<int32_t>(baseLine) + offB;
                            lineB     = (v > 0) ? static_cast<uint32_t>(v) : 1u;
                        }

                        setRange(lineA, lineB);
                    }
                    else
                    {
                        setExactLine(lineA);
                    }
                }
            }
        }
        else
        {
            // Default: exact baseline (directive position)
            setExactLine(directive.myLoc.line);
        }

        // Find and parse all `{{ ... }}` blocks following this directive
        while (true)
        {
            const size_t open = comment.find("{{", i);
            if (open == std::string_view::npos)
                break;

            const size_t close = comment.find("}}", open + 2);
            if (close == std::string_view::npos)
                break;

            VerifyDirective dir = directive;
            dir.match           = comment.substr(open + 2, close - (open + 2));
            dir.match           = Utf8Helper::trim(dir.match);
            directives_.emplace_back(std::move(dir));

            i = close + 2;
        }

        pos = i;
    }
}

void Verify::tokenize(TaskContext& ctx)
{
    if (!ctx.cmdLine().verify)
        return;

    srcView_ = &ctx.compiler().addSourceView(file_->ref());

    // Get all comments from the file
    Lexer lexer;
    lexer.tokenizeRaw(ctx, *srcView_);

    // Parse all comments to find a verify directive
    for (const auto& trivia : srcView_->trivia())
    {
        const std::string_view comment = trivia.tok.string(*srcView_);
        if (trivia.tok.is(TokenId::CommentLine))
        {
            tokenizeExpected(ctx, trivia, comment);
            tokenizeOption(ctx, comment);
        }
    }
}

bool Verify::verifyExpected(const TaskContext& ctx, const Diagnostic& diag) const
{
    if (directives_.empty())
        return false;

    for (auto& elem : diag.elements())
    {
        const SourceCodeLocation loc = elem->location(0, ctx);

        for (auto& directive : directives_)
        {
            if (directive.kind != elem->severity())
                continue;

            // line constraint matching
            if (!directive.allowedLines.empty())
            {
                bool ok = false;
                for (const uint32_t ln : directive.allowedLines)
                {
                    if (ln == loc.line)
                    {
                        ok = true;
                        break;
                    }
                }
                if (!ok)
                    continue;
            }
            else if ((directive.lineMin || directive.lineMax) && loc.line < directive.lineMin || loc.line > directive.lineMax)
            {
                continue;
            }

            if (elem->idName().find(directive.match) == Utf8::npos &&
                elem->message().find(directive.match) == Utf8::npos)
                continue;

            directive.touched = true;
            return true;
        }
    }

    return false;
}

void Verify::verifyUntouchedExpected(TaskContext& ctx, const SourceView& srcView) const
{
    for (const auto& directive : directives_)
    {
        if (!directive.touched)
        {
            const auto diag = Diagnostic::get(DiagnosticId::unittest_err_not_raised, srcView.fileRef());
            diag.last().addSpan(directive.myLoc, "");
            diag.report(ctx);
        }
    }
}

SWC_END_NAMESPACE()
