#include "pch.h"
#include "Report/Diagnostic.h"
#include "Core/Utf8Helpers.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/EvalContext.h"
#include "Main/Global.h"
#include "Report/DiagnosticElement.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"

SWC_BEGIN_NAMESPACE();

// Centralized palette for all diagnostic colors
Diagnostic::AnsiSeq Diagnostic::diagPalette(DiagPart p)
{
    using enum LogColor;
    switch (p)
    {
        case DiagPart::FileLocationArrow:
            return {BrightBlue};
        case DiagPart::FileLocationPath:
            return {BrightCyan};
        case DiagPart::FileLocationSep:
            return {BrightBlack};
        case DiagPart::GutterBar:
            return {BrightBlack};
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

Utf8 Diagnostic::toAnsiSeq(const EvalContext& ctx, const AnsiSeq& s)
{
    Utf8 out;
    for (const auto c : s.seq)
        out += Color::toAnsi(ctx, c);
    return out;
}

Utf8 Diagnostic::partStyle(const EvalContext& ctx, DiagPart p)
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
        case DiagnosticSeverity::Hint:
            return "help";
    }

    return "unknown";
}

Utf8 Diagnostic::severityColor(const EvalContext& ctx, DiagnosticSeverity s)
{
    switch (s)
    {
        case DiagnosticSeverity::Error:
            return Color::toAnsi(ctx, LogColor::BrightRed);
        case DiagnosticSeverity::Warning:
            return Color::toAnsi(ctx, LogColor::BrightYellow);
        case DiagnosticSeverity::Note:
            return Color::toAnsi(ctx, LogColor::BrightCyan);
        case DiagnosticSeverity::Hint:
            return Color::toAnsi(ctx, LogColor::BrightGreen);
    }
    return {};
}

// Generic digit counter (no hard cap)
uint32_t Diagnostic::digits(uint32_t n)
{
    return static_cast<uint32_t>(std::to_string(n).size());
}

// Short label line used for secondary elements (note/help/etc.)
void Diagnostic::writeSubLabel(Utf8& out, const EvalContext& ctx, DiagnosticSeverity sev, std::string_view msg)
{
    out += "  ";
    out += partStyle(ctx, DiagPart::SubLabelPrefix);
    out += severityColor(ctx, sev);
    out += severityStr(sev);
    out += partStyle(ctx, DiagPart::Reset);
    out += ": ";
    out += msg;
    out += "\n";
}

void Diagnostic::writeFileLocation(Utf8& out, const EvalContext& ctx, const std::string& path, uint32_t line, uint32_t col, uint32_t len)
{
    out += "  ";
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
    out += ":";
    out += partStyle(ctx, DiagPart::Reset);
    out += std::to_string(line);

    out += partStyle(ctx, DiagPart::FileLocationSep);
    out += ":";
    out += partStyle(ctx, DiagPart::Reset);
    out += std::to_string(col + len);

    out += "\n";
}

void Diagnostic::writeGutterSep(Utf8& out, const EvalContext& ctx, uint32_t gutterW)
{
    out.append(gutterW, ' ');
    out += partStyle(ctx, DiagPart::GutterBar);
    out += " |";
    out += partStyle(ctx, DiagPart::Reset);
    out += "\n";
}

void Diagnostic::writeCodeLine(Utf8& out, const EvalContext& ctx, uint32_t gutterW, uint32_t lineNo, std::string_view code)
{
    out.append(gutterW - digits(lineNo), ' ');
    out += partStyle(ctx, DiagPart::LineNumber);
    out += std::to_string(lineNo);
    out += partStyle(ctx, DiagPart::Reset);

    out += partStyle(ctx, DiagPart::GutterBar);
    out += " | ";
    out += partStyle(ctx, DiagPart::Reset);

    out += partStyle(ctx, DiagPart::CodeText);
    out += code;
    out += partStyle(ctx, DiagPart::Reset);
    out += "\n";
}

void Diagnostic::writeFullUnderline(Utf8& out, const EvalContext& ctx, DiagnosticSeverity sev, const Utf8& msg, uint32_t gutterW, uint32_t columnOneBased, uint32_t underlineLen)
{
    out.append(gutterW, ' ');
    out += partStyle(ctx, DiagPart::GutterBar);
    out += " | ";
    out += partStyle(ctx, DiagPart::Reset);

    // Carets use severity color + caret style
    out += severityColor(ctx, sev);

    for (uint32_t i = 1; i < columnOneBased; ++i)
        out += ' ';

    const uint32_t len = underlineLen == 0 ? 1u : underlineLen;
    out.append(len, '^');

    // Label message
    out += " ";
    out += severityStr(sev);
    out += ": ";
    out += msg;

    out += partStyle(ctx, DiagPart::Reset);
    out += "\n";
}

// Renders a single element's location/code/underline block
void Diagnostic::writeCodeBlock(Utf8& out, const EvalContext& ctx, const DiagnosticElement& el)
{
    const auto loc = el.location(ctx);

    Utf8 fileName;
    if (ctx.cmdLine().errorAbsolute)
        fileName = el.location(ctx).file->path().string();
    else
        fileName = el.location(ctx).file->path().filename().string();
    writeFileLocation(out, ctx, fileName, loc.line, loc.column, loc.len);

    const uint32_t gutterW = digits(loc.line);
    writeGutterSep(out, ctx, gutterW);

    const auto codeLine = el.location(ctx).file->codeLine(ctx, loc.line);
    writeCodeLine(out, ctx, gutterW, loc.line, codeLine);

    // underline the entire span with carets
    const std::string_view tokenView     = el.location(ctx).file->codeView(el.location(ctx).offset, el.location(ctx).len);
    const uint32_t         tokenLenChars = Utf8Helpers::countChars(tokenView);
    writeFullUnderline(out, ctx, el.severity(), el.message(), gutterW, loc.column, tokenLenChars);

    writeGutterSep(out, ctx, gutterW);
}

Utf8 Diagnostic::build(const EvalContext& ctx) const
{
    Utf8 out;
    if (elements_.empty())
        return out;

    // Primary element: the first one
    const auto& primary = elements_.front();
    const auto  pMsg    = primary->message();

    // Render primary element body (location/code) if any
    const bool pHasLoc = primary->hasCodeLocation();
    if (pHasLoc)
        writeCodeBlock(out, ctx, *primary);

    // Now render all secondary elements as part of the same diagnostic
    for (size_t i = 1; i < elements_.size(); ++i)
    {
        const auto& e       = elements_[i];
        const auto  sev     = e->severity();
        const auto  msg     = e->message();
        const bool  eHasLoc = e->hasCodeLocation();

        // Sub label line
        writeSubLabel(out, ctx, sev, msg);

        // Optional location/code block
        if (eHasLoc)
            writeCodeBlock(out, ctx, *e);
    }

    // single blank line after the whole diagnostic
    out += "\n";
    return out;
}

DiagnosticElement* Diagnostic::addElement(DiagnosticSeverity kind, DiagnosticId id)
{
    auto       ptr = std::make_unique<DiagnosticElement>(kind, id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return raw;
}

void Diagnostic::report(const EvalContext& ctx) const
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
