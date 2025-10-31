#include "pch.h"
#include "Report/DiagnosticEngine.h"
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
    // Enum for colorable diagnostic parts
    enum class DiagPart : uint8_t
    {
        FileLocationArrow, // "-->"
        FileLocationPath,  // file path or filename
        FileLocationSep,   // ":" between file/line/col
        GutterBar,         // " |"
        LineNumber,        // left-hand line numbers
        CodeText,          // source code line
        LabelMsgPrefix,    // secondary label ("note", "help", etc.)
        LabelMsgText,      // secondary label message
        Severity,          // color for severity labels/underlines
        QuoteText,         // color for quoted text based on severity
        Reset,             // reset sequence
    };

    struct AnsiSeq
    {
        std::vector<LogColor> seq;
        AnsiSeq(std::initializer_list<LogColor> s) :
            seq(s)
        {
        }
    };

    struct Part
    {
        std::optional<DiagnosticSeverity> tag;
        std::string                       text;
    };

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

    // split message on ';' ignoring ';' inside quotes and escaped quotes
    SmallVector<std::string_view> splitMessage(std::string_view msg)
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

    SmallVector<Part> parseParts(std::string_view msg)
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
    AnsiSeq diagPalette(DiagPart p, std::optional<DiagnosticSeverity> sev)
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

    Utf8 toAnsiSeq(const Context& ctx, const AnsiSeq& s)
    {
        Utf8 out;
        for (const auto c : s.seq)
            out += LogColorHelper::toAnsi(ctx, c);
        return out;
    }

    Utf8 partStyle(const Context& ctx, DiagPart p)
    {
        return toAnsiSeq(ctx, diagPalette(p, std::nullopt));
    }

    Utf8 partStyle(const Context& ctx, DiagPart p, DiagnosticSeverity sev)
    {
        return toAnsiSeq(ctx, diagPalette(p, sev));
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

    void writeHighlightedMessage(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg, const Utf8& reset)
    {
        const Utf8  qColor  = partStyle(ctx, DiagPart::QuoteText, sev);
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

    void writeFileLocation(Utf8& out, const Context& ctx, const std::string& path, uint32_t line, uint32_t col, uint32_t len, uint32_t gutterW)
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

    void writeGutter(Utf8& out, const Context& ctx, uint32_t gutterW)
    {
        out.append(gutterW, ' ');
        out += partStyle(ctx, DiagPart::GutterBar);
        out += " ";
        out += LogSymbolHelper::toString(ctx, LogSymbol::VerticalLine);
        out += partStyle(ctx, DiagPart::Reset);
        out += " ";
    }

    void writeCodeLine(Utf8& out, const Context& ctx, uint32_t gutterW, uint32_t lineNo, std::string_view code)
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

    void writeLabelMsg(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg)
    {
        out += partStyle(ctx, DiagPart::LabelMsgPrefix, sev);
        out += severityStr(sev);
        out += ": ";
        out += partStyle(ctx, DiagPart::Reset);

        out += partStyle(ctx, DiagPart::LabelMsgText, sev);
        writeHighlightedMessage(out, ctx, sev, msg, partStyle(ctx, DiagPart::LabelMsgText, sev));
        out += partStyle(ctx, DiagPart::Reset);
        out += "\n";
    }

    void writeCodeUnderline(Utf8& out, const Context& ctx, DiagnosticSeverity sev, const Utf8& msg, uint32_t gutterW, uint32_t columnOneBased, uint32_t underlineLen)
    {
        writeGutter(out, ctx, gutterW);

        // Underline
        out += partStyle(ctx, DiagPart::Severity, sev);
        const uint32_t col = std::max<uint32_t>(1, columnOneBased);
        for (uint32_t i = 1; i < col; ++i)
            out += ' ';

        const uint32_t len = underlineLen == 0 ? 1u : underlineLen;
        for (uint32_t i = 0; i < len; ++i)
            out.append(LogSymbolHelper::toString(ctx, LogSymbol::Underline));

        // Message
        if (!msg.empty())
        {
            out += " ";
            writeLabelMsg(out, ctx, sev, msg);
        }
        else
            out += "\n";
    }

    // Helper function to convert variant argument to string
    Utf8 argumentToString(const Diagnostic::Argument& arg)
    {
        auto toUtf8 = []<typename T0>(const T0& v) -> Utf8 {
            using T = std::decay_t<T0>;
            if constexpr (std::same_as<T, Utf8>)
                return v;
            else if constexpr (std::integral<T>)
                return Utf8{std::to_string(v)};
            else
                std::unreachable();
        };

        Utf8 s = std::visit(toUtf8, arg.val);

        if (!arg.quoted)
            return s;

        Utf8 out;
        out.reserve(s.size() + 2);
        out.push_back('\'');
        out += s;
        out.push_back('\'');
        return out;
    }

    Utf8 message(const Diagnostic& diag, const DiagnosticElement& el)
    {
        auto result = el.message();

        // Replace placeholders
        for (const auto& arg : diag.arguments())
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
        result = std::regex_replace(result, std::regex{R"(\{[^{}]+\})"}, "");
        result.replaceOutsideQuotes(" , ", ", ");
        result.replaceOutsideQuotes("  ", " ", true);

        return result;
    }

    // Renders a single element's location/code/underline block
    // NOTE: gutterW is computed once per diagnostic (max line number across all elements)
    void writeCodeBlock(Utf8& out, const Context& ctx, const Diagnostic& diag, const DiagnosticElement& el, uint32_t gutterW, bool writeMsg)
    {
        const auto loc = el.location(ctx);

        Utf8 fileName;
        if (ctx.cmdLine().errorAbsolute)
            fileName = el.location(ctx).file->path().string();
        else
            fileName = el.location(ctx).file->path().filename().string();
        writeFileLocation(out, ctx, fileName, loc.line, loc.column, loc.len, gutterW);

        // writeGutterSep(out, ctx, gutterW);

        const auto codeLine = el.location(ctx).file->codeLine(ctx, loc.line);
        writeCodeLine(out, ctx, gutterW, loc.line, codeLine);

        // underline the entire span with carets
        const std::string_view tokenView     = el.location(ctx).file->codeView(el.location(ctx).offset, el.location(ctx).len);
        const uint32_t         tokenLenChars = Utf8Helper::countChars(tokenView);
        writeCodeUnderline(out, ctx, el.severity(), writeMsg ? message(diag, el) : "", gutterW, loc.column, tokenLenChars);

        // writeGutterSep(out, ctx, gutterW);

        out += partStyle(ctx, DiagPart::Reset);
    }

    void expandMessageParts(const Diagnostic& diag, SmallVector<std::unique_ptr<DiagnosticElement>>& elements)
    {
        if (elements.empty())
            return;

        const auto front = elements.front().get();
        const Utf8 msg   = message(diag, *front);
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
}

Utf8 DiagnosticEngine::build(const Context& ctx, const Diagnostic& diag)
{
    if (diag.elements().empty())
        return {};

    // Make a copy of elements to modify them if necessary
    SmallVector<std::unique_ptr<DiagnosticElement>> elements;
    elements.reserve(diag.elements().size());
    for (auto& e : diag.elements())
        elements.push_back(std::make_unique<DiagnosticElement>(*e));
    expandMessageParts(diag, elements);

    // Compute a unified gutter width based on the maximum line number among all located elements
    uint32_t maxLine = 0;
    for (const auto& e : elements)
    {
        if (e->hasCodeLocation())
            maxLine = std::max(e->location(ctx).line, maxLine);
    }

    const uint32_t gutterW = maxLine ? digits(maxLine) : 0;

    // Primary element: the first one
    const auto& primary = elements.front();
    const auto  pMsg    = message(diag, *primary);

    // Render primary element body (location/code) if any
    Utf8 out;
    writeLabelMsg(out, ctx, primary->severity(), pMsg);
    const bool pHasLoc = primary->hasCodeLocation();
    if (pHasLoc)
        writeCodeBlock(out, ctx, diag, *primary, gutterW, false);
    else
    {
        out += partStyle(ctx, DiagPart::Severity, primary->severity());
        out += severityStr(primary->severity());
        out += ": ";
        writeHighlightedMessage(out, ctx, primary->severity(), pMsg, partStyle(ctx, DiagPart::Severity, primary->severity()));
        out += partStyle(ctx, DiagPart::Reset);
        out += "\n";
    }

    // Now render all secondary elements as part of the same diagnostic
    for (size_t i = 1; i < elements.size(); ++i)
    {
        const auto& e       = elements[i];
        const auto  sev     = e->severity();
        const auto  msg     = message(diag, *e);
        const bool  eHasLoc = e->hasCodeLocation();

        // Optional location/code block
        if (eHasLoc)
            writeCodeBlock(out, ctx, diag, *e, gutterW, true);
        else
        {
            out.append(gutterW, ' ');
            writeLabelMsg(out, ctx, sev, msg);
        }
    }

    // single blank line after the whole diagnostic
    out += "\n";
    return out;
}

SWC_END_NAMESPACE()
