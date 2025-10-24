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

    uint32_t digits(uint32_t n)
    {
        if (n < 10)
            return 1;
        if (n < 100)
            return 2;
        if (n < 1000)
            return 3;
        if (n < 10000)
            return 4;
        if (n < 100000)
            return 5;
        return 6;
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
}

Utf8 Diagnostic::build(EvalContext& ctx) const
{
    Utf8 out;

    for (auto& e : elements_)
    {
        const auto sev     = e->severity();
        const auto idName  = e->idName();
        const auto msg     = e->message();
        const bool has_loc = (e->file_ != nullptr) && (e->len_ != 0);

        if (has_loc)
        {
            const auto loc = e->location(ctx);

            out += Color::toAnsi(ctx, LogColor::Bold);
            out += e->file_->path().string();
            out += ":";
            out += std::to_string(loc.line);
            out += ":";
            out += std::to_string(loc.column);
            out += ": ";
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

            // === rust-style context
            writeArrowLine(out, ctx, e->file_->path().string(), loc.line, loc.column);

            const uint32_t gutter_w = digits(loc.line);
            writeGutterSep(out, gutter_w);

            const auto codeLine = e->file_->codeLine(ctx, loc.line);
            writeCodeLine(out, gutter_w, loc.line, codeLine);

            // underline the entire span with carets
            std::string_view tokenView     = e->file_->codeView(e->offset_, e->len_);
            uint32_t         tokenLenChars = Utf8Helpers::countChars(tokenView);
            writeFullUnderline(out, ctx, sev, gutter_w, loc.column, tokenLenChars);

            writeGutterSep(out, gutter_w);
        }
        else
        {
            // No location: simplified header
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

        out += "\n"; // blank line between diagnostics
    }

    return out;
}

DiagnosticElement* Diagnostic::addElement(DiagnosticSeverity kind, DiagnosticId id)
{
    auto       ptr = std::make_unique<DiagnosticElement>(kind, id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return raw;
}

void Diagnostic::report(EvalContext& ctx) const
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
