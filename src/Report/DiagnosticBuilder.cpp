#include "pch.h"
#include "Report/DiagnosticBuilder.h"
#include "Core/Utf8Helper.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticElement.h"
#include "Report/LogColor.h"
#include "Report/LogSymbol.h"

SWC_BEGIN_NAMESPACE()

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
        }

        return "unknown";
    }

    // Generic digit counter (no hard cap)
    uint32_t digits(uint32_t n)
    {
        return static_cast<uint32_t>(std::to_string(n).size());
    }
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
        return {BrightBlack};
    case DiagPart::GutterBar:
        return {BrightCyan};
    case DiagPart::LineNumber:
        return {BrightBlack};
    case DiagPart::CodeText:
        return {White};

    case DiagPart::LabelMsgText:
        if (!sev)
            return {White};
        switch (*sev)
        {
        case DiagnosticSeverity::Error:
            return {BrightRed};
        case DiagnosticSeverity::Warning:
            return {BrightYellow};
        case DiagnosticSeverity::Note:
        case DiagnosticSeverity::Help:
            return {White};
        }
        break;

    case DiagPart::LabelMsgPrefix:
    case DiagPart::Severity:
        if (!sev)
            return {White};
        switch (*sev)
        {
        case DiagnosticSeverity::Error:
            return {BrightRed};
        case DiagnosticSeverity::Warning:
            return {BrightYellow};
        case DiagnosticSeverity::Note:
            return {BrightCyan};
        case DiagnosticSeverity::Help:
            return {BrightGreen};
        }
        break;

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
            return {BrightBlack};
        case DiagnosticSeverity::Help:
            return {BrightBlack};
        }
        break;

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
    const Utf8  qColor  = partStyle(DiagPart::QuoteText, sev);
    bool        inQuote = false;
    std::string quotedBuf;
    quotedBuf.reserve(32);

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
        else
        {
            // Inside quotes: watch for escaped '\'' and closing '\''
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

void DiagnosticBuilder::writeFileLocation(const std::string& path, uint32_t line, uint32_t col, uint32_t len)
{
    out_.append(gutterW_, ' ');
    out_ += partStyle(DiagPart::FileLocationArrow);
    out_ += "--> ";
    out_ += partStyle(DiagPart::FileLocationPath);
    out_ += path;
    out_ += partStyle(DiagPart::Reset);

    out_ += partStyle(DiagPart::FileLocationSep);
    out_ += ":";
    out_ += partStyle(DiagPart::Reset);
    out_ += std::to_string(line);

    out_ += partStyle(DiagPart::FileLocationSep);
    out_ += ":";
    out_ += partStyle(DiagPart::Reset);
    out_ += std::to_string(col);

    out_ += partStyle(DiagPart::FileLocationSep);
    out_ += "-";
    out_ += partStyle(DiagPart::Reset);
    out_ += std::to_string(col + len);

    out_ += "\n";
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

void DiagnosticBuilder::writeCodeLine(uint32_t lineNo, std::string_view code)
{
    out_.append(gutterW_ - digits(lineNo), ' ');
    out_ += partStyle(DiagPart::LineNumber);
    out_ += std::to_string(lineNo);
    out_ += partStyle(DiagPart::Reset);

    writeGutter(0);

    out_ += partStyle(DiagPart::CodeText);
    out_ += code;
    out_ += partStyle(DiagPart::Reset);
    out_ += "\n";
}

void DiagnosticBuilder::writeLabelMsg(DiagnosticSeverity sev, std::string_view msg)
{
    out_ += partStyle(DiagPart::LabelMsgPrefix, sev);
    out_ += severityStr(sev);
    out_ += ": ";
    out_ += partStyle(DiagPart::Reset);

    out_ += partStyle(DiagPart::LabelMsgText, sev);
    writeHighlightedMessage(sev, msg, partStyle(DiagPart::LabelMsgText, sev));
    out_ += partStyle(DiagPart::Reset);
    out_ += "\n";
}

void DiagnosticBuilder::writeCodeUnderline(DiagnosticSeverity sev, const Utf8& msg, uint32_t columnOneBased, uint32_t underlineLen)
{
    writeGutter(gutterW_);

    // Underline
    out_ += partStyle(DiagPart::Severity, sev);
    const uint32_t col = std::max<uint32_t>(1, columnOneBased);
    for (uint32_t i = 1; i < col; ++i)
        out_ += ' ';

    const uint32_t len = underlineLen == 0 ? 1u : underlineLen;
    for (uint32_t i = 0; i < len; ++i)
        out_.append(LogSymbolHelper::toString(*ctx_, LogSymbol::Underline));

    // Message
    if (!msg.empty())
    {
        out_ += " ";
        writeLabelMsg(sev, msg);
    }
    else
        out_ += "\n";
}

// Helper function to convert variant argument to string
Utf8 DiagnosticBuilder::argumentToString(const Diagnostic::Argument& arg) const
{
    auto toUtf8 = []<typename T0>(const T0& v) -> Utf8 {
        using T = std::decay_t<T0>;
        if constexpr (std::same_as<T, Utf8>)
            return v;
        else if constexpr (std::same_as<T, TokenId>)
            return Token::toName(v);
        else if constexpr (std::same_as<T, DiagnosticId>)
            return Diagnostic::diagIdMessage(v);
        else if constexpr (std::integral<T>)
            return Utf8{std::to_string(v)};
        else
            std::unreachable();
    };

    Utf8 s = std::visit(toUtf8, arg.val);
    if (!arg.quoted)
        return s;

    Utf8 result;
    result.reserve(s.size() + 2);
    result.push_back('\'');
    result += s;
    result.push_back('\'');
    return result;
}

// Renders a single element's location/code/underline block
// NOTE: gutterW is computed once per diagnostic (max line number across all elements)
void DiagnosticBuilder::writeCodeBlock(const DiagnosticElement& el, bool writeMsg)
{
    const auto loc = el.location(*ctx_);

    Utf8 fileName;
    if (ctx_->cmdLine().errorAbsolute)
        fileName = el.location(*ctx_).file->path().string();
    else
        fileName = el.location(*ctx_).file->path().filename().string();
    writeFileLocation(fileName, loc.line, loc.column, loc.len);

    // writeGutterSep(out, ctx, gutterW);

    const auto codeLine = el.location(*ctx_).file->codeLine(*ctx_, loc.line);
    writeCodeLine(loc.line, codeLine);

    // underline the entire span with carets
    const std::string_view tokenView     = el.location(*ctx_).file->codeView(el.location(*ctx_).offset, el.location(*ctx_).len);
    const uint32_t         tokenLenChars = Utf8Helper::countChars(tokenView);
    writeCodeUnderline(el.severity(), writeMsg ? message(el) : "", loc.column, tokenLenChars);

    // writeGutterSep(out, ctx, gutterW);

    out_ += partStyle(DiagPart::Reset);
}

Utf8 DiagnosticBuilder::message(const DiagnosticElement& el) const
{
    auto result = el.message();

    // Replace placeholders
    for (const auto& arg : diag_->arguments())
    {
        Utf8   replacement = argumentToString(arg);
        size_t pos         = 0;
        while ((pos = result.find(arg.name, pos)) != Utf8::npos)
        {
            result.replace(pos, arg.name.length(), replacement);
            pos += replacement.length();
        }
    }

    // Clean some stuff
    result = std::regex_replace(result, std::regex{R"(\{\w+\})"}, "");
    result.replaceOutsideQuotes(" , ", ", ");
    result.replaceOutsideQuotes("  ", " ", true);

    return result;
}

void DiagnosticBuilder::expandMessageParts(SmallVector<std::unique_ptr<DiagnosticElement>>& elements) const
{
    if (elements.empty())
        return;

    const auto front = elements.front().get();
    const Utf8 msg   = message(*front);
    const auto parts = parseParts(std::string_view(msg));

    // base element keeps first
    front->setMessage(Utf8(parts[0].text));

    if (parts.size() <= 1)
        return;

    // Reserve capacity upfront to avoid reallocations during emplace_back
    elements.reserve(elements.size() + parts.size() - 1);

    for (size_t i = 1; i < parts.size(); ++i)
    {
        const auto&        p   = parts[i];
        DiagnosticSeverity sev = p.tag.value_or(DiagnosticSeverity::Note);

        auto extra = std::make_unique<DiagnosticElement>(sev, front->id());
        extra->setMessage(Utf8(p.text));
        elements.emplace_back(std::move(extra));
    }
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
    expandMessageParts(elements);

    // Compute a unified gutter width based on the maximum line number among all located elements
    uint32_t maxLine = 0;
    for (const auto& e : elements)
    {
        if (e->hasCodeLocation())
            maxLine = std::max(e->location(*ctx_).line, maxLine);
    }

    gutterW_ = maxLine ? digits(maxLine) : 0;

    // Primary element: the first one
    const auto& primary = elements.front();
    const auto  pMsg    = message(*primary);

    // Render primary element body (location/code) if any
    writeLabelMsg(primary->severity(), pMsg);
    if (primary->hasCodeLocation())
        writeCodeBlock(*primary, false);

    // Now render all secondary elements as part of the same diagnostic
    for (size_t i = 1; i < elements.size(); ++i)
    {
        const auto& el = elements[i];
        if (el->hasCodeLocation())
            writeCodeBlock(*el, true);
        else
        {
            out_.append(gutterW_, ' ');
            writeLabelMsg(el->severity(), message(*el));
        }
    }

    // single blank line after the whole diagnostic
    out_ += "\n";
    return out_;
}

SWC_END_NAMESPACE()
