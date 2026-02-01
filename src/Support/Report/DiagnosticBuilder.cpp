#include "pch.h"
#include "Support/Report/DiagnosticBuilder.h"
#include "Core/Utf8Helper.h"
#include "Lexer/Lexer.h"
#include "Lexer/SyntaxColor.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticElement.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/LogSymbol.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // tag → severity mapping
    std::optional<DiagnosticSeverity> tagToSeverity(std::string_view s)
    {
        if (Utf8Helper::startsWith(s, "[note]"))
            return DiagnosticSeverity::Note;
        if (Utf8Helper::startsWith(s, "[help]"))
            return DiagnosticSeverity::Help;
        return std::nullopt;
    }

    // remove a header like [note] or [help]
    std::string_view stripLeadingTagHeader(std::string_view s)
    {
        auto t = Utf8Helper::trim(s);
        if (!t.empty() && t.front() == '[')
        {
            const auto close = t.find(']');
            if (close != std::string_view::npos)
                t.remove_prefix(close + 1);
        }
        t = Utf8Helper::trimLeft(t);
        return t;
    }

    std::string_view severityStr(DiagnosticSeverity s)
    {
        switch (s)
        {
            case DiagnosticSeverity::Error:
                return "error";
            case DiagnosticSeverity::Warning:
                return "warning";
            case DiagnosticSeverity::Note:
                return "note";
            case DiagnosticSeverity::Help:
                return "help";
            default:
                SWC_UNREACHABLE();
        }
    }

    // Generic digit counter (no hard cap)
    uint32_t digits(uint32_t n)
    {
        return static_cast<uint32_t>(std::to_string(n).size());
    }
}

DiagnosticBuilder::DiagnosticBuilder(const TaskContext& ctx, const Diagnostic& diag) :
    ctx_(&ctx),
    diag_(&diag)
{
}

Utf8 DiagnosticBuilder::build()
{
    if (diag_->elements().empty())
        return {};

    // Make a copy of elements to modify them if necessary
    SmallVector<std::unique_ptr<DiagnosticElement>> elements;
    elements.reserve(diag_->elements().size());
    for (auto& e : diag_->elements())
        elements.push_back(std::make_unique<DiagnosticElement>(*e));

    // Add elements by splitting messages parts
    expandMessageParts(elements);

    // Compute a unified gutter width based on the maximum line number among all located elements
    uint32_t maxLine = 0;
    for (const auto& e : elements)
    {
        if (e->hasCodeLocation())
        {
            for (uint32_t i = 0; i < e->spans().size(); ++i)
                maxLine = std::max(e->location(i, *ctx_).line, maxLine);
        }
    }

    gutterW_ = maxLine ? digits(maxLine) : 0;

    // Primary element: the first one
    const auto& primary = *elements.front();

    if (ctx_->cmdLine().diagOneLine)
    {
        writeLocation(primary);
        out_ += ": ";
        writeLabelMsg(primary);
        return out_;
    }

    // Render primary element body (location/code) if any
    writeLabelMsg(primary);
    if (primary.hasCodeLocation())
        writeCodeBlock(primary);

    // Now render all secondary elements as part of the same diagnostic
    for (size_t i = 1; i < elements.size(); ++i)
    {
        const auto& el = *elements[i];
        out_.append(gutterW_, ' ');
        writeLabelMsg(el);
        if (el.hasCodeLocation())
            writeCodeBlock(el);
    }

    // single blank line after the whole diagnostic
    out_ += "\n";
    return out_;
}

// split message on ';' ignoring ';' inside quotes and escaped quotes
SmallVector<std::string_view> DiagnosticBuilder::splitMessage(std::string_view msg)
{
    SmallVector<std::string_view> parts;
    size_t                        start   = 0;
    bool                          inQuote = false;

    for (size_t i = 0; i < msg.size(); ++i)
    {
        const char c = msg[i];
        if (inQuote)
        {
            if (c == '\\')
            {
                if (i + 1 < msg.size())
                    ++i;
            }
            else if (c == '\'')
            {
                inQuote = false;
            }
        }
        else
        {
            if (c == '\'')
                inQuote = true;
            else if (c == ';')
            {
                auto p = Utf8Helper::trim(msg.substr(start, i - start));
                if (!p.empty())
                    parts.emplace_back(p);
                start = i + 1;
            }
        }
    }

    if (start <= msg.size())
    {
        auto p = Utf8Helper::trim(msg.substr(start));
        if (!p.empty())
            parts.emplace_back(p);
    }

    return parts;
}

SmallVector<DiagnosticBuilder::Part> DiagnosticBuilder::parseParts(std::string_view msg)
{
    SmallVector<Part> out;
    for (auto raw : splitMessage(msg))
    {
        if (raw.empty())
            continue;
        const auto sev  = tagToSeverity(raw);
        auto       body = stripLeadingTagHeader(raw);
        out.push_back({.tag = sev, .text = Utf8(body)});
    }

    return out;
}

// Centralized palette for all diagnostic colors
DiagnosticBuilder::AnsiSeq DiagnosticBuilder::diagPalette(DiagPart p, std::optional<DiagnosticSeverity> sev)
{
    using enum LogColor;
    switch (p)
    {
        case DiagPart::FileLocationArrow:
        case DiagPart::FileLocationPath:
        case DiagPart::FileLocationSep:
            return {Gray};
        case DiagPart::GutterBar:
            return {BrightCyan};
        case DiagPart::LineNumber:
            return {Gray};
        case DiagPart::CodeText:
            return {White};
        case DiagPart::Ellipsis:
            return {Gray};

        case DiagPart::LabelMsgText:
            if (!sev)
                return {White};
            switch (*sev)
            {
                case DiagnosticSeverity::Error:
                    return {BrightRed};
                case DiagnosticSeverity::Warning:
                    return {BrightMagenta};
                case DiagnosticSeverity::Note:
                case DiagnosticSeverity::Help:
                    return {White};
                default:
                    SWC_UNREACHABLE();
            }

        case DiagPart::LabelMsgPrefix:
        case DiagPart::Severity:
            if (!sev)
                return {White};
            switch (*sev)
            {
                case DiagnosticSeverity::Error:
                    return {BrightRed};
                case DiagnosticSeverity::Warning:
                    return {BrightMagenta};
                case DiagnosticSeverity::Note:
                    return {BrightCyan};
                case DiagnosticSeverity::Help:
                    return {BrightGreen};
                default:
                    SWC_UNREACHABLE();
            }

        case DiagPart::QuoteText:
            if (!sev)
                return {White};
            switch (*sev)
            {
                case DiagnosticSeverity::Error:
                    return {BrightMagenta};
                case DiagnosticSeverity::Warning:
                    return {BrightBlue};
                case DiagnosticSeverity::Note:
                    return {Gray};
                case DiagnosticSeverity::Help:
                    return {Gray};
                default:
                    SWC_UNREACHABLE();
            }

        case DiagPart::Reset:
            return {Reset};
    }

    return {White};
}

Utf8 DiagnosticBuilder::toAnsiSeq(const AnsiSeq& s) const
{
    Utf8 result;
    for (const auto c : s.seq)
        result += LogColorHelper::toAnsi(*ctx_, c);
    return result;
}

Utf8 DiagnosticBuilder::partStyle(DiagPart p) const
{
    return toAnsiSeq(diagPalette(p, std::nullopt));
}

Utf8 DiagnosticBuilder::partStyle(DiagPart p, DiagnosticSeverity sev) const
{
    return toAnsiSeq(diagPalette(p, sev));
}

void DiagnosticBuilder::writeHighlightedMessage(DiagnosticSeverity sev, std::string_view msg, const Utf8& reset)
{
    const Utf8 qColor  = partStyle(DiagPart::QuoteText, sev);
    bool       inQuote = false;
    Utf8       quotedBuf;
    quotedBuf.reserve(32);

    out_ += reset;
    for (size_t i = 0; i < msg.size(); ++i)
    {
        const char ch = msg[i];

        if (!inQuote)
        {
            if (ch == '\'')
            {
                inQuote   = true;
                quotedBuf = '\'';
            }
            else
            {
                out_ += ch;
            }
        }

        // Inside quotes
        else
        {
            // Watch for escaped '\'' and closing '\''
            if (ch == '\\')
            {
                // Lookahead for escaped quote
                if (i + 1 < msg.size() && msg[i + 1] == '\'')
                {
                    quotedBuf += '\''; // Keep a literal single quote in the content
                    ++i;               // Consume the escape
                }
                else
                {
                    // Preserve other escapes/backslashes verbatim inside the content
                    quotedBuf += '\\';
                }
            }
            else if (ch == '\'' && quotedBuf.back() == '\'' && quotedBuf.size() == 1)
            {
                quotedBuf += ch;
            }
            else if (ch == '\'')
            {
                quotedBuf += '\'';
                out_ += qColor;
                out_ += quotedBuf;
                out_ += reset;
                inQuote = false;
                quotedBuf.clear();
            }
            else
            {
                quotedBuf += ch;
            }
        }
    }

    // If the message ended while still "inQuote", emit what we have plainly with the opening quote.
    if (inQuote)
    {
        out_ += qColor;
        out_ += quotedBuf; // inside without a closing quote — still highlighted
        out_ += reset;
    }
}

void DiagnosticBuilder::writeLocation(const DiagnosticElement& el)
{
    const auto loc = el.location(0, *ctx_);

    SWC_ASSERT(el.srcView());
    if (el.srcView()->fileRef().isValid())
    {
        const auto& file = ctx_->compiler().file(el.srcView()->fileRef());
        Utf8        fileName;
        if (ctx_->cmdLine().diagAbsolute)
            fileName = file.path().string();
        else
            fileName = file.path().filename().string();
        out_ += partStyle(DiagPart::FileLocationPath);
        out_ += fileName;
        out_ += partStyle(DiagPart::Reset);
    }

    out_ += partStyle(DiagPart::FileLocationSep);
    out_ += ":";
    out_ += partStyle(DiagPart::Reset);
    out_ += std::to_string(loc.line);

    out_ += partStyle(DiagPart::FileLocationSep);
    out_ += ":";
    out_ += partStyle(DiagPart::Reset);
    out_ += std::to_string(loc.column);

    out_ += partStyle(DiagPart::FileLocationSep);
    out_ += "-";
    out_ += partStyle(DiagPart::Reset);
    out_ += std::to_string(loc.column + loc.len);
}

void DiagnosticBuilder::writeGutter(uint32_t gutter)
{
    out_.append(gutter, ' ');
    out_ += partStyle(DiagPart::GutterBar);
    out_ += " ";
    out_ += LogSymbolHelper::toString(*ctx_, LogSymbol::VerticalLine);
    out_ += partStyle(DiagPart::Reset);
    out_ += " ";
}

void DiagnosticBuilder::writeCodeLine(uint32_t lineNo, std::string_view startEllipsis, std::string_view code, std::string_view endEllipsis)
{
    out_.append(gutterW_ - digits(lineNo), ' ');
    out_ += partStyle(DiagPart::LineNumber);
    out_ += std::to_string(lineNo);
    out_ += partStyle(DiagPart::Reset);
    writeGutter(0);

    if (!startEllipsis.empty())
    {
        out_ += partStyle(DiagPart::Ellipsis);
        out_ += startEllipsis;
        out_ += partStyle(DiagPart::Reset);
        out_ += " ";
    }

    out_ += partStyle(DiagPart::CodeText);
    out_ += SyntaxColorHelper::colorize(*ctx_, SyntaxColorMode::ForLog, code);
    out_ += partStyle(DiagPart::Reset);

    if (!endEllipsis.empty())
    {
        out_ += " ";
        out_ += partStyle(DiagPart::Ellipsis);
        out_ += endEllipsis;
        out_ += partStyle(DiagPart::Reset);
    }

    out_ += "\n";
}

void DiagnosticBuilder::writeLabelMsg(const DiagnosticElement& el)
{
    out_ += partStyle(DiagPart::LabelMsgPrefix, el.severity());
    out_ += severityStr(el.severity());

    // Error/Warning id
    if (ctx_->cmdLine().errorId && !el.isNoteOrHelp())
        out_ += std::format("[{}]", Diagnostic::diagIdName(el.id()));

    out_ += ": ";
    out_ += partStyle(DiagPart::Reset);

    // Message
    out_ += partStyle(DiagPart::LabelMsgText, el.severity());
    writeHighlightedMessage(el.severity(), buildMessage(el.message(), &el), partStyle(DiagPart::LabelMsgText, el.severity()));
    out_ += partStyle(DiagPart::Reset);
    out_ += "\n";
}

void DiagnosticBuilder::writeCodeUnderline(const DiagnosticElement& el, const SmallVector<ColSpan>& underlines)
{
    writeGutter(gutterW_);

    // Track that underlines needs continuation lines
    std::vector<std::tuple<uint32_t, std::string, DiagnosticSeverity>> continuations;

    uint32_t currentPos = 1; // Current position in the output line
    for (const auto& [col, len, span] : underlines)
    {
        const uint32_t column       = std::max<uint32_t>(1, col);
        const uint32_t underlineLen = len == 0 ? 1 : len;

        // Add spaces from current position to start of underline
        for (uint32_t i = currentPos; i < column; ++i)
            out_ += ' ';

        // Determine the color for this underline
        const DiagnosticSeverity effectiveSeverity = (span.severity == DiagnosticSeverity::Zero) ? el.severity() : span.severity;

        // Apply color for this specific underline
        out_ += partStyle(DiagPart::Severity, effectiveSeverity);

        // Add underline characters
        for (uint32_t i = 0; i < underlineLen; ++i)
            out_.append(LogSymbolHelper::toString(*ctx_, LogSymbol::Underline));

        // Get message
        auto msg = span.message;
        if (msg.empty() && span.messageId != DiagnosticId::None)
            msg = Diagnostic::diagIdMessage(span.messageId);

        if (!msg.empty())
        {
            msg                        = buildMessage(msg, &el);
            const uint32_t msgStartPos = column + underlineLen + 1; // +1 for space before a message
            const uint32_t msgLength   = static_cast<uint32_t>(msg.length());

            // Check if a message fits on this line (consider next underline position if exists)
            bool fits = true;
            for (const auto& [nextCol, nextLen, nextSpan] : underlines)
            {
                // +2 to avoid being too close to the following one
                if (nextCol > col && msgStartPos + msgLength + 2 > nextCol)
                {
                    fits = false;
                    break;
                }
            }

            if (fits)
            {
                // Message fits on the same line
                out_ += " ";
                writeHighlightedMessage(DiagnosticSeverity::Note, msg, partStyle(DiagPart::LabelMsgText, DiagnosticSeverity::Note));
                currentPos = msgStartPos + msgLength;
            }
            else
            {
                // Message doesn't fit, schedule for continuation line
                continuations.emplace_back(column, msg, effectiveSeverity);
                currentPos = column + underlineLen;
            }
        }
        else
        {
            currentPos = column + underlineLen;
        }
    }

    out_ += partStyle(DiagPart::Reset);
    out_ += "\n";

    // Write continuation lines for messages that didn't fit
    for (const auto& [col, msg, severity] : continuations)
    {
        writeGutter(gutterW_);

        // Add spaces up to the column position
        for (uint32_t i = 1; i < col; ++i)
            out_ += ' ';

        // Add vertical bar in the underline color
        out_ += partStyle(DiagPart::Severity, severity);
        out_.append(LogSymbolHelper::toString(*ctx_, LogSymbol::VerticalLine));
        out_ += " ";

        // Write the message
        writeHighlightedMessage(DiagnosticSeverity::Note, msg, partStyle(DiagPart::LabelMsgText, DiagnosticSeverity::Note));

        out_ += partStyle(DiagPart::Reset);
        out_ += "\n";
    }
}

void DiagnosticBuilder::writeCodeTrunc(const DiagnosticElement&  elToUse,
                                       const SourceCodeLocation& loc,
                                       const DiagnosticSpan&     span,
                                       uint32_t                  tokenLenChars,
                                       const Utf8&               currentFullCodeLine,
                                       uint32_t                  currentFullCharCount)
{
    constexpr std::string_view ellipsis    = "...";
    constexpr uint32_t         lenEllipsis = static_cast<uint32_t>(ellipsis.length()) + 1; // keep your "+1"
    constexpr uint32_t         leftContext = 8;

    const uint32_t diagMax = ctx_->cmdLine().diagMaxColumn;

    // The initial window anchored with a small left context.
    const uint32_t rawStart    = (loc.column > leftContext) ? (loc.column - leftContext) : 0u;
    uint32_t       windowStart = rawStart;

    uint32_t   visibleWidth = diagMax;
    const bool addPrefix    = (windowStart > 0);
    if (addPrefix && visibleWidth >= lenEllipsis)
        visibleWidth -= lenEllipsis;

    uint32_t windowEnd = std::min(windowStart + visibleWidth, currentFullCharCount);

    bool addSuffix = (windowEnd < currentFullCharCount);
    if (addSuffix && visibleWidth >= lenEllipsis)
    {
        if (windowEnd > windowStart + lenEllipsis)
            windowEnd -= lenEllipsis;
    }

    // We compute on the provisional slice first
    const Utf8 provisional = currentFullCodeLine.substr(windowStart, windowEnd - windowStart);

    // Underline start relative to provisional slice
    const uint32_t underlineStart0 = (loc.column > windowStart) ? (loc.column - windowStart) : 0u;

    uint32_t ltrim = 0;
    if (addPrefix && underlineStart0 > 0)
    {
        // Only trim blanks strictly before the underline, so we never shift the token itself.
        ltrim = Utf8Helper::countLeadingBlanks(*ctx_, provisional, underlineStart0);
        if (ltrim > 0)
        {
            windowStart += ltrim;

            // Try to keep the visible width constant by extending rightwards if possible.
            const uint32_t canExtend = std::min<uint32_t>(ltrim, currentFullCharCount - windowEnd);
            windowEnd += canExtend;

            // Re-evaluate suffix after extension
            addSuffix = (windowEnd < currentFullCharCount);
        }
    }

    const Utf8 codeSlice = currentFullCodeLine.substr(windowStart, windowEnd - windowStart);
    writeCodeLine(loc.line, addPrefix ? ellipsis : "", codeSlice, addSuffix ? ellipsis : "");

    const uint32_t prefixCols            = addPrefix ? lenEllipsis : 0;
    const uint32_t sliceVisible          = (windowEnd - windowStart);
    const uint32_t underlineStartInSlice = (loc.column > windowStart) ? (loc.column - windowStart) : 0u;
    const uint32_t rightAvail            = (underlineStartInSlice < sliceVisible) ? (sliceVisible - underlineStartInSlice) : 0u;
    const uint32_t adjustedLen           = std::min(tokenLenChars, rightAvail);
    const uint32_t adjustedCol           = prefixCols + underlineStartInSlice;

    SmallVector<ColSpan> one;
    one.emplace_back(adjustedCol, adjustedLen, span);
    writeCodeUnderline(elToUse, one);
}

void DiagnosticBuilder::writeCodeBlock(const DiagnosticElement& el)
{
    // Loc
    out_.append(gutterW_, ' ');
    out_ += partStyle(DiagPart::FileLocationArrow);
    out_ += "--> ";
    writeLocation(el);
    out_ += "\n";

    // Sort underlines by column to process them in order
    auto sortedSpans = el.spans();
    std::ranges::sort(sortedSpans, [&](const auto& a, const auto& b) {
        const auto loc1 = el.location(a, *ctx_);
        const auto loc2 = el.location(b, *ctx_);
        return loc1.column < loc2.column;
    });

    const uint32_t diagMax = ctx_->cmdLine().diagMaxColumn;

    SmallVector<ColSpan> underlinesOnCurrentLine;

    uint32_t currentLine = std::numeric_limits<uint32_t>::max();
    Utf8     currentFullCodeLine;
    uint32_t currentFullCharCount   = 0;
    bool     currentLineIsTruncated = false;

    for (const auto& span : sortedSpans)
    {
        const auto loc = el.location(span, *ctx_);

        if (loc.line != currentLine)
        {
            // Flush the previous underline row if needed
            if (!currentLineIsTruncated)
            {
                if (!underlinesOnCurrentLine.empty())
                {
                    writeCodeUnderline(el, underlinesOnCurrentLine);
                    underlinesOnCurrentLine.clear();
                }
            }

            // Prepare a new line
            currentFullCodeLine    = el.srcView()->codeLine(*ctx_, loc.line);
            currentFullCharCount   = Utf8Helper::countChars(currentFullCodeLine);
            currentLineIsTruncated = (currentFullCharCount > diagMax);

            if (!currentLineIsTruncated)
                writeCodeLine(loc.line, "", currentFullCodeLine, "");

            currentLine = loc.line;
        }

        const std::string_view tokenView     = el.srcView()->codeView(loc.offset, loc.len);
        const uint32_t         tokenLenChars = Utf8Helper::countChars(tokenView);

        if (currentLineIsTruncated)
            writeCodeTrunc(el, loc, span, tokenLenChars, currentFullCodeLine, currentFullCharCount);
        else
            underlinesOnCurrentLine.emplace_back(loc.column, tokenLenChars, span);
    }

    if (!underlinesOnCurrentLine.empty())
        writeCodeUnderline(el, underlinesOnCurrentLine);

    out_ += partStyle(DiagPart::Reset);
}

Utf8 DiagnosticBuilder::buildMessage(const Utf8& msg, const DiagnosticElement* el) const
{
    auto result = msg;

    auto replaceArgs = [&](const DiagnosticArguments& arguments) {
        for (const auto& arg : arguments)
        {
            const Utf8 raw = argumentToString(arg);
            size_t     pos = 0;
            while ((pos = result.find(arg.name, pos)) != Utf8::npos)
            {
                result.replace(pos, arg.name.length(), raw);
                pos += raw.length();
            }
        }
    };

    // Replace placeholders from the element first
    if (el)
        replaceArgs(el->arguments());

    // Then from the diagnostic
    replaceArgs(diag_->arguments());

    // Clean some stuff
    result = std::regex_replace(result, std::regex{R"(\{\w+\})"}, "");
    result = std::regex_replace(result, std::regex{R"(\'\')"}, "");
    result.replace_loop(" , ", ", ");
    result.replace_loop("  ", " ", true);

    return result;
}

// Helper function to convert variant argument to string
Utf8 DiagnosticBuilder::argumentToString(const DiagnosticArgument& arg) const
{
    auto toUtf8 = [&]<typename T0>(const T0& v) -> Utf8 {
        using T = std::decay_t<T0>;
        if constexpr (std::same_as<T, Utf8>)
            return v;
        else if constexpr (std::same_as<T, TokenId>)
            return Token::toName(v);
        else if constexpr (std::same_as<T, DiagnosticId>)
            return Diagnostic::diagIdMessage(v);
        else if constexpr (std::integral<T>)
            return Utf8{std::to_string(v)};
        else if constexpr (std::same_as<T, TypeRef>)
            return ctx_->compiler().typeMgr().get(v).toName(*ctx_);
        else if constexpr (std::same_as<T, ConstantRef>)
            return ctx_->compiler().cstMgr().get(v).toString(*ctx_);
        else if constexpr (std::same_as<T, IdentifierRef>)
            return ctx_->compiler().idMgr().get(v).name;
        else
            SWC_UNREACHABLE();
    };

    return std::visit(toUtf8, arg.val);
}

void DiagnosticBuilder::expandMessageParts(SmallVector<std::unique_ptr<DiagnosticElement>>& elements) const
{
    if (elements.empty())
        return;

    // Process elements from back to front to avoid invalidating iterators
    // and to maintain proper ordering when inserting new elements
    for (size_t idx = elements.size(); idx-- > 0;)
    {
        const auto element = elements[idx].get();
        const Utf8 msg     = buildMessage(element->message(), element);
        auto       parts   = parseParts(std::string_view(msg));

        // Base element keeps the first part
        element->setMessage(Utf8(parts[0].text));
        parts.erase(parts.begin());
        if (parts.empty())
            continue;

        // Insert additional parts right after the current element
        auto insertPos = idx + 1;
        for (const auto& p : parts)
        {
            DiagnosticSeverity sev = p.tag.value_or(DiagnosticSeverity::Note);

            auto extra = std::make_unique<DiagnosticElement>(sev, element->id());
            extra->setMessage(Utf8(p.text));

            elements.insert(elements.begin() + insertPos, std::move(extra));
            ++insertPos;
        }
    }
}

SWC_END_NAMESPACE();
