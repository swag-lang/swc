#include "pch.h"

#include "Core/Utf8Helpers.h"
#include "Lexer/SourceFile.h"
#include "LogColor.h"
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"
#include "Main/Global.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticElement.h"
#include "Report/Logger.h"

DiagnosticElement* Diagnostic::addElement(DiagnosticSeverity kind, DiagnosticId id)
{
    auto       ptr = std::make_unique<DiagnosticElement>(kind, id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return raw;
}

Utf8 Diagnostic::build(CompilerContext& ctx) const
{
    const auto& glb      = Global::get();
    const auto  cmdLine = glb.cmdLine();
    Utf8        result;

    for (auto& e : elements_)
    {
        const auto severity = e->severity();
        const auto idName   = e->idName();

        // Colorize severity level
        result += Color::toAnsi(LogColor::Bold);
        switch (severity)
        {
            case DiagnosticSeverity::Error:
                result += Color::toAnsi(LogColor::BrightRed);
                break;
            case DiagnosticSeverity::Warning:
                result += Color::toAnsi(LogColor::BrightYellow);
                break;
            case DiagnosticSeverity::Note:
                result += Color::toAnsi(LogColor::BrightCyan);
                break;
            case DiagnosticSeverity::Hint:
                result += Color::toAnsi(LogColor::BrightGreen);
                break;
        }

        result += idName;
        result += Color::toAnsi(LogColor::Reset);
        result += "\n";

        if (e->file_ != nullptr)
        {
            // File path
            result += Color::toAnsi(LogColor::Bold);
            result += Color::toAnsi(LogColor::Cyan);
            result += e->file_->path().string();
            result += ":";

            // Location
            SourceCodeLocation loc;
            if (e->len_ != 0)
            {
                loc = e->location();
                result += std::format("{}:{}", loc.line, loc.column);
                result += "\n";
            }

            result += Color::toAnsi(LogColor::Reset);

            // Code line
            if (e->len_ != 0)
            {
                const auto code = e->file_->codeLine(loc.line);
                result += code;
                result += "\n";
            }

            // Carets
            if (e->len_ != 0)
            {
                result += Color::toAnsi(LogColor::Bold);
                switch (severity)
                {
                    case DiagnosticSeverity::Error:
                        result += Color::toAnsi(LogColor::BrightRed);
                        break;
                    case DiagnosticSeverity::Warning:
                        result += Color::toAnsi(LogColor::BrightYellow);
                        break;
                    default:
                        result += Color::toAnsi(LogColor::BrightCyan);
                        break;
                }

                for (uint32_t i = 1; i < loc.column; ++i)
                    result += " ";

                std::string_view tokenStr = e->file_->codeView(e->offset_, e->len_);
                uint32_t         tokenLen = Utf8Helpers::countChars(tokenStr);
                for (uint32_t i = 0; i < tokenLen; ++i)
                    result += "^";
            }

            result += Color::toAnsi(LogColor::Reset);
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
    const auto& glb      = Global::get();
    const auto& cmdLine = glb.cmdLine();
    const auto  msg     = build(ctx);
    bool        dismiss = false;

    if (fileOwner_ != nullptr)
    {
        dismiss = fileOwner_->verifier().verify(*this);
    }

    if (cmdLine.verboseErrors)
    {
        dismiss = false;
        if (!cmdLine.verboseErrorsFilter.empty() && msg.find(cmdLine.verboseErrorsFilter) == Utf8::npos)
            dismiss = true;
    }

    if (!dismiss)
    {
        auto& logger = glb.logger();
        logger.lock();
        logger.printEol();
        logger.print(msg);
        logger.unlock();
    }
}
