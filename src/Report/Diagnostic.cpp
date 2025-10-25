#include "pch.h"

#include "Core/Utf8Helper.h"
#include "Lexer/SourceFile.h"
#include "LogSymbol.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticElement.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // whitespace helpers
    static inline std::string_view ltrim(std::string_view s)
    {
        while (!s.empty() && (s.front() == ' ' || s.front() == '\t'))
            s.remove_prefix(1);
        return s;
    }
    static inline std::string_view rtrim(std::string_view s)
    {
        while (!s.empty() && (s.back() == ' ' || s.back() == '\t'))
            s.remove_suffix(1);
        return s;
    }
    static inline std::string_view trim(std::string_view s)
    {
        return rtrim(ltrim(s));
    }

    // ASCII-case-insensitive starts-with
    static bool istarts_with(std::string_view s, std::string_view pfx)
    {
        if (s.size() < pfx.size())
            return false;
        for (size_t i = 0; i < pfx.size(); ++i)
        {
            char a = s[i], b = pfx[i];
            if ('A' <= a && a <= 'Z')
                a = char(a - 'A' + 'a');
            if ('A' <= b && b <= 'Z')
                b = char(b - 'A' + 'a');
            if (a != b)
                return false;
        }
        return true;
    }

    // tag → severity mapping
    static std::optional<DiagnosticSeverity> tagToSeverity(std::string_view s)
    {
        if (istarts_with(s, "[note]"))
            return DiagnosticSeverity::Note;
        if (istarts_with(s, "[help]"))
            return DiagnosticSeverity::Help;
        return std::nullopt;
    }

    // remove header like [note] or note:
    static std::string_view stripLeadingTagHeader(std::string_view s)
    {
        auto t = trim(s);
        if (!t.empty() && t.front() == '[')
        {
            auto close = t.find(']');
            if (close != std::string_view::npos)
                t.remove_prefix(close + 1);
        }
        t = ltrim(t);
        if (istarts_with(t, "note:"))
        {
            t.remove_prefix(5);
            t = ltrim(t);
        }
        else if (istarts_with(t, "help:"))
        {
            t.remove_prefix(5);
            t = ltrim(t);
        }
        else if (istarts_with(t, "warning:"))
        {
            t.remove_prefix(8);
            t = ltrim(t);
        }
        else if (istarts_with(t, "error:"))
        {
            t.remove_prefix(6);
            t = ltrim(t);
        }
        return t;
    }

    // split message on ';' ignoring ';' inside quotes and escaped quotes
    static std::vector<std::string_view> splitMessageSafe(std::string_view msg)
    {
        std::vector<std::string_view> parts;
        size_t                        start   = 0;
        bool                          inQuote = false;

        for (size_t i = 0; i < msg.size(); ++i)
        {
            char c = msg[i];
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
                    parts.emplace_back(trim(msg.substr(start, i - start)));
                    start = i + 1;
                }
            }
        }
        if (start <= msg.size())
            parts.emplace_back(trim(msg.substr(start)));
        return parts;
    }

    struct Part
    {
        std::optional<DiagnosticSeverity> tag;
        std::string                       text;
    };

    std::vector<Part> parseParts(std::string_view msg)
    {
        std::vector<Part> out;
        for (auto raw : splitMessageSafe(msg))
        {
            if (raw.empty())
                continue;
            const auto sev  = tagToSeverity(raw);
            auto       body = stripLeadingTagHeader(raw);
            out.push_back({sev, std::string(body)});
        }
        return out;
    }

} // namespace

// Centralized palette for all diagnostic colors
Diagnostic::AnsiSeq Diagnostic::diagPalette(DiagPart p)
{
    using enum LogColor;
    switch (p)
    {
        case DiagPart::FileLocationArrow:
            return {BrightBlack};
        case DiagPart::FileLocationPath:
            return {BrightBlack};
        case DiagPart::FileLocationSep:
            return {BrightBlack};
        case DiagPart::GutterBar:
            return {BrightCyan};
        case DiagPart::LineNumber:
            return {BrightBlack};
        case DiagPart::CodeText:
            return {White};
        case DiagPart::SubLabelPrefix:
            return {BrightMagenta, Bold};
        case DiagPart::Reset:
            return {Reset};
    }

    return {White};
}

Utf8 Diagnostic::toAnsiSeq(const Context& ctx, const AnsiSeq& s)
{
    Utf8 out;
    for (const auto c : s.seq)
        out += LogColorHelper::toAnsi(ctx, c);
    return out;
}

Utf8 Diagnostic::partStyle(const Context& ctx, DiagPart p)
{
    return toAnsiSeq(ctx, diagPalette(p));
}

std::string_view Diagnostic::severityStr(DiagnosticSeverity s)
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

Utf8 Diagnostic::severityColor(const Context& ctx, DiagnosticSeverity s)
{
    switch (s)
    {
        case DiagnosticSeverity::Error:
            return LogColorHelper::toAnsi(ctx, LogColor::BrightRed);
        case DiagnosticSeverity::Warning:
            return LogColorHelper::toAnsi(ctx, LogColor::BrightYellow);
        case DiagnosticSeverity::Note:
            return LogColorHelper::toAnsi(ctx, LogColor::BrightCyan);
        case DiagnosticSeverity::Help:
            return LogColorHelper::toAnsi(ctx, LogColor::BrightGreen);
    }
    return {};
}

Utf8 Diagnostic::quoteColor(const Context& ctx, DiagnosticSeverity sev)
{
    using enum LogColor;

    // Chosen to complement the base severity colors:
    // - Error   (BrightRed)    -> BrightMagenta for quotes
    // - Warning (BrightYellow) -> BrightBlue
    // - Note    (BrightCyan)   -> BrightWhite
    // - Help    (BrightGreen)  -> BrightWhite
    switch (sev)
    {
        case DiagnosticSeverity::Error:
            return LogColorHelper::toAnsi(ctx, BrightMagenta);
        case DiagnosticSeverity::Warning:
            return LogColorHelper::toAnsi(ctx, BrightBlue);
        case DiagnosticSeverity::Note:
            return LogColorHelper::toAnsi(ctx, BrightBlack);
        case DiagnosticSeverity::Help:
            return LogColorHelper::toAnsi(ctx, BrightBlack);
    }

    return LogColorHelper::toAnsi(ctx, LogColor::White);
}

// Generic digit counter (no hard cap)
uint32_t Diagnostic::digits(uint32_t n)
{
    return static_cast<uint32_t>(std::to_string(n).size());
}

void Diagnostic::writeHighlightedMessage(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg, Utf8 reset)
{
    const Utf8  qColor  = quoteColor(ctx, sev);
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
                out += ch;
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
                out += qColor;
                out += quotedBuf;
                out += reset;
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
        out += qColor;
        out += quotedBuf; // inside without a closing quote — still highlighted
        out += reset;
    }
}

// Short label line used for secondary elements (note/help/etc.)
void Diagnostic::writeSubLabel(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg, uint32_t gutterW)
{
    out.append(gutterW, ' ');
    out += partStyle(ctx, DiagPart::SubLabelPrefix);
    out += severityColor(ctx, sev);
    out += severityStr(sev);
    out += partStyle(ctx, DiagPart::Reset);
    out += ": ";

    writeHighlightedMessage(out, ctx, sev, msg, severityColor(ctx, sev));

    out += "\n";
}

void Diagnostic::writeFileLocation(Utf8& out, const Context& ctx, const std::string& path, uint32_t line, uint32_t col, uint32_t len, uint32_t gutterW)
{
    out.append(gutterW, ' ');
    out += partStyle(ctx, DiagPart::FileLocationArrow);
    out += "--> ";
    out += partStyle(ctx, DiagPart::FileLocationPath);
    out += path;
    out += partStyle(ctx, DiagPart::Reset);

    out += partStyle(ctx, DiagPart::FileLocationSep);
    out += ":";
    out += partStyle(ctx, DiagPart::Reset);
    out += std::to_string(line);

    out += partStyle(ctx, DiagPart::FileLocationSep);
    out += ":";
    out += partStyle(ctx, DiagPart::Reset);
    out += std::to_string(col);

    out += partStyle(ctx, DiagPart::FileLocationSep);
    out += "-";
    out += partStyle(ctx, DiagPart::Reset);
    out += std::to_string(col + len);

    out += "\n";
}

void Diagnostic::writeGutter(Utf8& out, const Context& ctx, uint32_t gutterW)
{
    out.append(gutterW, ' ');
    out += partStyle(ctx, DiagPart::GutterBar);
    out += " ";
    out += LogSymbolHelper::toString(ctx, LogSymbol::VerticalLine);
    out += partStyle(ctx, DiagPart::Reset);
    out += " ";
}

void Diagnostic::writeGutterSep(Utf8& out, const Context& ctx, uint32_t gutterW)
{
    writeGutter(out, ctx, gutterW);
    out += "\n";
}

void Diagnostic::writeCodeLine(Utf8& out, const Context& ctx, uint32_t gutterW, uint32_t lineNo, std::string_view code)
{
    out.append(gutterW - digits(lineNo), ' ');
    out += partStyle(ctx, DiagPart::LineNumber);
    out += std::to_string(lineNo);
    out += partStyle(ctx, DiagPart::Reset);

    writeGutter(out, ctx, 0);

    out += partStyle(ctx, DiagPart::CodeText);
    out += code;
    out += partStyle(ctx, DiagPart::Reset);
    out += "\n";
}

void Diagnostic::writeFullUnderline(Utf8& out, const Context& ctx, DiagnosticSeverity sev, const Utf8& msg, uint32_t gutterW, uint32_t columnOneBased, uint32_t underlineLen)
{
    writeGutter(out, ctx, gutterW);

    out += severityColor(ctx, sev);

    const uint32_t col = std::max<uint32_t>(1, columnOneBased);
    for (uint32_t i = 1; i < col; ++i)
        out += ' ';

    const uint32_t len = underlineLen == 0 ? 1u : underlineLen;
    out.append(len, '^');

    out += " ";
    out += severityStr(sev);
    out += ": ";

    writeHighlightedMessage(out, ctx, sev, std::string_view(msg), severityColor(ctx, sev));

    out += partStyle(ctx, DiagPart::Reset);
    out += "\n";
}

// Renders a single element's location/code/underline block
// NOTE: gutterW is computed once per diagnostic (max line number across all elements)
void Diagnostic::writeCodeBlock(Utf8& out, const Context& ctx, const DiagnosticElement& el, uint32_t gutterW)
{
    const auto loc = el.location(ctx);

    Utf8 fileName;
    if (ctx.cmdLine().errorAbsolute)
        fileName = el.location(ctx).file->path().string();
    else
        fileName = el.location(ctx).file->path().filename().string();
    writeFileLocation(out, ctx, fileName, loc.line, loc.column, loc.len, gutterW);

    writeGutterSep(out, ctx, gutterW);

    const auto codeLine = el.location(ctx).file->codeLine(ctx, loc.line);
    writeCodeLine(out, ctx, gutterW, loc.line, codeLine);

    // underline the entire span with carets
    const std::string_view tokenView     = el.location(ctx).file->codeView(el.location(ctx).offset, el.location(ctx).len);
    const uint32_t         tokenLenChars = Utf8Helper::countChars(tokenView);
    writeFullUnderline(out, ctx, el.severity(), el.message(), gutterW, loc.column, tokenLenChars);

    writeGutterSep(out, ctx, gutterW);
}

Utf8 Diagnostic::build(const Context& ctx) const
{
    Utf8 out;

    if (elements_.empty())
        return out;

    // Make a copy of elements to modify them if necessary
    std::vector<std::unique_ptr<DiagnosticElement>> elements;
    elements.reserve(elements_.size());
    for (auto &e : elements_)
        elements.push_back(std::make_unique<DiagnosticElement>(*e.get()));
    expandMessageParts(elements);

    // Compute a unified gutter width based on the maximum line number among all located elements
    uint32_t maxLine = 0;
    for (const auto& e : elements)
    {
        if (e->hasCodeLocation())
        {
            const auto locLine = e->location(ctx).line;
            maxLine            = std::max(locLine, maxLine);
        }
    }

    const uint32_t gutterW = maxLine ? digits(maxLine) : 0;

    // Primary element: the first one
    const auto& primary = elements.front();
    const auto  pMsg    = primary->message();

    // Render primary element body (location/code) if any
    const bool pHasLoc = primary->hasCodeLocation();
    if (pHasLoc)
        writeCodeBlock(out, ctx, *primary, gutterW);
    else
    {
        out += severityColor(ctx, primary->severity());
        out += severityStr(primary->severity());
        out += ": ";
        writeHighlightedMessage(out, ctx, primary->severity(), pMsg, severityColor(ctx, primary->severity()));
        out += partStyle(ctx, DiagPart::Reset);
    }

    // Now render all secondary elements as part of the same diagnostic
    for (size_t i = 1; i < elements.size(); ++i)
    {
        const auto& e       = elements[i];
        const auto  sev     = e->severity();
        const auto  msg     = e->message();
        const bool  eHasLoc = e->hasCodeLocation();

        // Sub label line
        writeSubLabel(out, ctx, sev, msg, gutterW);

        // Optional location/code block
        if (eHasLoc)
            writeCodeBlock(out, ctx, *e, gutterW);
    }

    // single blank line after the whole diagnostic
    out += partStyle(ctx, DiagPart::Reset);
    out += "\n";
    return out;
}

void Diagnostic::expandMessageParts(std::vector<std::unique_ptr<DiagnosticElement>>& elements)
{
    const auto front = elements.front().get();
    const Utf8 msg   = front->message();
    const auto parts = parseParts(std::string_view(msg));
    if (parts.size() <= 1)
        return;

    // base element keeps first
    front->setMessage(Utf8(parts[0].text));

    for (size_t i = 1; i < parts.size(); ++i)
    {
        const auto&        p   = parts[i];
        DiagnosticSeverity sev = p.tag.value_or(DiagnosticSeverity::Note);

        auto extra = std::make_unique<DiagnosticElement>(sev, front->id());
        extra->inheritLocationFrom(*front);
        extra->setMessage(Utf8(p.text));
        elements.emplace_back(std::move(extra));
    }
}

DiagnosticElement* Diagnostic::addElement(DiagnosticSeverity kind, DiagnosticId id)
{
    auto       ptr = std::make_unique<DiagnosticElement>(kind, id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return raw;
}

void Diagnostic::report(const Context& ctx) const
{
    const auto msg     = build(ctx);
    bool       dismiss = false;

    // Check that diagnostic was not awaited
    if (fileOwner_ != nullptr)
    {
        dismiss = fileOwner_->verifier().verify(ctx, *this);
    }

    // In tests, suppress diagnostics unless verbose errors are explicitly requested and match the filter.
    if (dismiss && ctx.cmdLine().verboseErrors)
    {
        const auto& filter = ctx.cmdLine().verboseErrorsFilter;
        if (filter.empty() || msg.find(filter) != Utf8::npos)
            dismiss = false;
    }

    // Log diagnostic
    if (!dismiss)
    {
        auto& logger = ctx.global().logger();
        logger.lock();
        Logger::print(ctx, msg);
        logger.unlock();
    }
}

SWC_END_NAMESPACE();
