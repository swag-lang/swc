#include "pch.h"
#include "Wmf/Verify.h"
#include "Support/Core/Utf8Helper.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Lexer.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isDigit(char c) noexcept
    {
        return c >= '0' && c <= '9';
    }

    uint32_t clampLine(int32_t v) noexcept
    {
        return (v > 0) ? static_cast<uint32_t>(v) : 1u;
    }

    // Parses an unsigned integer at p. Returns true if at least one digit was consumed.
    bool parseUInt(std::string_view s, size_t& p, int& out) noexcept
    {
        int  v   = 0;
        bool any = false;
        while (p < s.size() && isDigit(s[p]))
        {
            any = true;
            v   = v * 10 + (s[p] - '0');
            ++p;
        }
        if (!any)
            return false;
        out = v;
        return true;
    }

    // Parses: [+|-] [digits?]
    // Rules:
    //  - if sign is present but digits are missing -> implicit 1
    //  - if no sign and no digits -> fail
    // Sets hasSign accordingly.
    bool parseSignedOrAbs(std::string_view s, size_t& p, int& value, bool& hasSign) noexcept
    {
        hasSign  = false;
        int sign = +1;

        if (p < s.size() && (s[p] == '+' || s[p] == '-'))
        {
            hasSign = true;
            sign    = (s[p] == '-') ? -1 : +1;
            ++p;

            int mag = 0;
            if (!parseUInt(s, p, mag))
            {
                value = sign * 1; // implicit +/-1
                return true;
            }

            value = sign * mag;
            return true;
        }

        // No sign -> must be digits (absolute line)
        int absV = 0;
        if (!parseUInt(s, p, absV))
            return false;

        value = absV;
        return true;
    }

    void setAnywhere(VerifyDirective& d)
    {
        d.allowedLines.clear();
        d.lineMin = 0;
        d.lineMax = 0;
    }

    void setExact(VerifyDirective& d, uint32_t line)
    {
        d.allowedLines.clear();
        d.lineMin = line;
        d.lineMax = line;
    }

    void setRange(VerifyDirective& d, uint32_t a, uint32_t b)
    {
        d.allowedLines.clear();
        d.lineMin = std::min(a, b);
        d.lineMax = std::max(a, b);
    }

    void setAllowedList(VerifyDirective& d, std::vector<uint32_t> lines)
    {
        d.allowedLines = std::move(lines);
        d.lineMin      = 0;
        d.lineMax      = 0; // ignored when allowedLines non-empty
    }

    // Consumes optional "@..." at position i and applies constraint to directive.
    // Returns a new index (i advanced), or leaves the directive at default if malformed.
    size_t parseLineConstraint(const LangSpec& langSpec, std::string_view comment, size_t i, VerifyDirective& directive)
    {
        const uint32_t baseLine = directive.myLoc.line;

        // default is exact base line unless "@..." overrides it
        setExact(directive, baseLine);

        if (i >= comment.size() || comment[i] != '@')
            return i;

        ++i; // consume '@'

        if (i < comment.size() && comment[i] == '*')
        {
            ++i;
            setAnywhere(directive);
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

                if (!parseSignedOrAbs(comment, i, v, hasSign))
                {
                    i = save;
                    break;
                }

                if (hasSign)
                    lines.push_back(clampLine(static_cast<int32_t>(baseLine) + v));
                else
                    lines.push_back(clampLine(v));

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
                setAllowedList(directive, std::move(lines));
            // else keep default exact(baseLine)

            return i;
        }

        // @+N / @-N / @+ / @- / @+A..+B
        {
            const size_t save    = i;
            int          offA    = 0;
            bool         hasSign = false;

            if (!parseSignedOrAbs(comment, i, offA, hasSign) || !hasSign)
            {
                // For this form we require a sign; otherwise treat as malformed and keep default exact(baseLine).
                i = save;
                return i;
            }

            const uint32_t lineA = clampLine(static_cast<int32_t>(baseLine) + offA);

            // range?
            if (i + 1 < comment.size() && comment[i] == '.' && comment[i + 1] == '.')
            {
                i += 2;

                int  offB     = 0;
                bool hasSignB = false;
                if (!parseSignedOrAbs(comment, i, offB, hasSignB) || !hasSignB)
                {
                    // malformed range end -> just treat as exact lineA
                    setExact(directive, lineA);
                    return i;
                }

                const uint32_t lineB = clampLine(static_cast<int32_t>(baseLine) + offB);
                setRange(directive, lineA, lineB);
                return i;
            }

            setExact(directive, lineA);
            return i;
        }
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

            if (!directive.matchesLine(loc.line))
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

            VerifyDirective dir = directive;
            dir.match           = comment.substr(open + 2, close - (open + 2));
            dir.match           = Utf8Helper::trim(dir.match);
            directives_.emplace_back(std::move(dir));

            i = close + 2;
        }

        pos = i;
    }
}

SWC_END_NAMESPACE();
