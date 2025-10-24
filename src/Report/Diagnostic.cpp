#include "pch.h"
#include "Diagnostic.h"
#include "Core/Utf8Helpers.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/EvalContext.h"
#include "Main/Global.h"
#include "Report/DiagnosticElement.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
            case DiagnosticSeverity::Hint:
                return "help";
        }
        return "unknown";
    }

    Utf8 severityColor(const EvalContext& ctx, DiagnosticSeverity s)
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

    // Factorized header for the primary element
    void writeHeader(Utf8& out, const EvalContext& ctx, DiagnosticSeverity sev, std::string_view idName, std::string_view msg)
    {
        out += severityColor(ctx, sev);
        out += severityStr(sev);
        if (!idName.empty())
        {
            out += "[";
            out += idName;
            out += "]";
        }

        out += Color::toAnsi(ctx, LogColor::Reset);
        out += ": ";
        out += msg;
        out += "\n";
    }

    // Short label line used for secondary elements (note/help/etc.)
    void writeSubLabel(Utf8& out, const EvalContext& ctx, DiagnosticSeverity sev, std::string_view idName, std::string_view msg)
    {
        out += "  "; // slight indent to visually group under the header
        out += severityColor(ctx, sev);
        out += severityStr(sev);
        out += Color::toAnsi(ctx, LogColor::Reset);
        out += ": ";
        out += msg;
        out += "\n";
    }

    // Generic digit counter (no hard cap)
    uint32_t digits(uint32_t n)
    {
        return static_cast<uint32_t>(std::to_string(n).size());
    }

    void writeArrowLine(Utf8& out, const EvalContext& ctx, const std::string& path, uint32_t line, uint32_t col)
    {
        out += "  ";
        out += Color::toAnsi(ctx, LogColor::Bold);
        out += "--> ";
        out += Color::toAnsi(ctx, LogColor::Cyan);
        out += path;
        out += Color::toAnsi(ctx, LogColor::Reset);
        out += ":";
        out += std::to_string(line);
        out += ":";
        out += std::to_string(col);
        out += "\n";
    }

    void writeGutterSep(Utf8& out, uint32_t gutterW)
    {
        out.append(gutterW, ' ');
        out += " |\n";
    }

    void writeCodeLine(Utf8& out, uint32_t gutterW, uint32_t lineNo, std::string_view code)
    {
        out.append(gutterW - digits(lineNo), ' ');
        out += std::to_string(lineNo);
        out += " | ";
        out += code;
        out += "\n";
    }

    void writeFullUnderline(Utf8& out, const EvalContext& ctx, DiagnosticSeverity sev, uint32_t gutterW, uint32_t columnOneBased, uint32_t underlineLen)
    {
        out.append(gutterW, ' ');
        out += " | ";
        out += severityColor(ctx, sev);
        out += Color::toAnsi(ctx, LogColor::Bold);

        // column is 1-based, so indent by (column - 1) spaces
        for (uint32_t i = 1; i < columnOneBased; ++i)
            out += ' ';

        // underline entire span with '^'
        const uint32_t len = underlineLen == 0 ? 1u : underlineLen;
        out.append(len, '^');

        out += Color::toAnsi(ctx, LogColor::Reset);
        out += "\n";
    }

    // Renders a single element's location/code/underline block
    void writeCodeBlock(Utf8& out, const EvalContext& ctx, const DiagnosticElement& el)
    {
        const auto loc = el.location(ctx);

        Utf8 fileName;
        if (ctx.cmdLine().errorAbsolute)
            fileName = el.location(ctx).file->path().string();
        else
            fileName = el.location(ctx).file->path().filename().string();
        writeArrowLine(out, ctx, fileName, loc.line, loc.column);

        const uint32_t gutterW = digits(loc.line);
        writeGutterSep(out, gutterW);

        const auto codeLine = el.location(ctx).file->codeLine(ctx, loc.line);
        writeCodeLine(out, gutterW, loc.line, codeLine);

        // underline the entire span with carets
        const std::string_view tokenView     = el.location(ctx).file->codeView(el.location(ctx).offset, el.location(ctx).len);
        const uint32_t         tokenLenChars = Utf8Helpers::countChars(tokenView);
        writeFullUnderline(out, ctx, el.severity(), gutterW, loc.column, tokenLenChars);
    }
}

Utf8 Diagnostic::build(const EvalContext& ctx) const
{
    Utf8 out;
    if (elements_.empty())
        return out;

    // Primary element: the first one
    const auto& primary = elements_.front();
    const auto  pSev    = primary->severity();
    const auto  pId     = primary->idName();
    const auto  pMsg    = primary->message();

    // Header for the whole diagnostic
    writeHeader(out, ctx, pSev, pId, pMsg);

    // Render primary element body (location/code) if any
    const bool pHasLoc = primary->hasCodeLocation();
    if (pHasLoc)
        writeCodeBlock(out, ctx, *primary);

    // Now render all secondary elements as part of the same diagnostic
    for (size_t i = 1; i < elements_.size(); ++i)
    {
        const auto& e       = elements_[i];
        const auto  sev     = e->severity();
        const auto  id      = e->idName();
        const auto  msg     = e->message();
        const bool  eHasLoc = e->hasCodeLocation();

        // Sub label line
        writeSubLabel(out, ctx, sev, id, msg);

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
