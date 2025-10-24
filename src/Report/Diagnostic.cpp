#include "pch.h"
#include "Diagnostic.h"
#include "Core/Utf8Helpers.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"
#include "Main/Global.h"
#include "Report/DiagnosticElement.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"

SWC_BEGIN_NAMESPACE()

DiagnosticElement* Diagnostic::addElement(DiagnosticSeverity kind, DiagnosticId id)
{
    auto       ptr = std::make_unique<DiagnosticElement>(kind, id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return raw;
}

Utf8 Diagnostic::build(CompilerContext& ctx) const
{
    Utf8 result;

    for (auto& e : elements_)
    {
        const auto severity = e->severity();
        const auto idName   = e->idName();

        // Colorize severity level
        result += Color::toAnsi(ctx, LogColor::Bold);
        switch (severity)
        {
            case DiagnosticSeverity::Error:
                result += Color::toAnsi(ctx, LogColor::BrightRed);
                break;
            case DiagnosticSeverity::Warning:
                result += Color::toAnsi(ctx, LogColor::BrightYellow);
                break;
            case DiagnosticSeverity::Note:
                result += Color::toAnsi(ctx, LogColor::BrightCyan);
                break;
            case DiagnosticSeverity::Hint:
                result += Color::toAnsi(ctx, LogColor::BrightGreen);
                break;
        }

        result += idName;
        result += Color::toAnsi(ctx, LogColor::Reset);
        result += "\n";

        if (e->file_ != nullptr)
        {
            // File path
            result += Color::toAnsi(ctx, LogColor::Bold);
            result += Color::toAnsi(ctx, LogColor::Cyan);
            result += e->file_->path().string();
            result += ":";

            // Location
            SourceCodeLocation loc;
            if (e->len_ != 0)
            {
                loc = e->location(ctx);
                result += std::format("{}:{}", loc.line, loc.column);
                result += "\n";
            }

            result += Color::toAnsi(ctx, LogColor::Reset);

            // Code line
            if (e->len_ != 0)
            {
                const auto code = e->file_->codeLine(ctx, loc.line);
                result += code;
                result += "\n";
            }

            // Carets
            if (e->len_ != 0)
            {
                result += Color::toAnsi(ctx, LogColor::Bold);
                switch (severity)
                {
                    case DiagnosticSeverity::Error:
                        result += Color::toAnsi(ctx, LogColor::BrightRed);
                        break;
                    case DiagnosticSeverity::Warning:
                        result += Color::toAnsi(ctx, LogColor::BrightYellow);
                        break;
                    default:
                        result += Color::toAnsi(ctx, LogColor::BrightCyan);
                        break;
                }

                for (uint32_t i = 1; i < loc.column; ++i)
                    result += " ";

                std::string_view tokenStr = e->file_->codeView(e->offset_, e->len_);
                uint32_t         tokenLen = Utf8Helpers::countChars(tokenStr);
                for (uint32_t i = 0; i < tokenLen; ++i)
                    result += "^";
            }

            result += Color::toAnsi(ctx, LogColor::Reset);
            result += "\n";
        }

        // Message text
        const auto msg = e->message();
        result += msg;
        result += "\n";
    }

    return result;
}

void Diagnostic::report(CompilerContext& ctx) const
{
    const auto msg     = build(ctx);
    bool       dismiss = false;

    if (fileOwner_ != nullptr)
    {
        dismiss = fileOwner_->verifier().verify(ctx, *this);
    }

    if (ctx.cmdLine()->verboseErrors)
    {
        dismiss = false;
        if (!ctx.cmdLine()->verboseErrorsFilter.empty() && msg.find(ctx.cmdLine()->verboseErrorsFilter) == Utf8::npos)
            dismiss = true;
    }

    if (!dismiss)
    {
        auto& logger = ctx.global()->logger();
        logger.lock();
        Logger::printEol(ctx);
        Logger::print(ctx, msg);
        logger.unlock();
    }
}

SWC_END_NAMESPACE()
