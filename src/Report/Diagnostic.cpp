#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticElement.h"
#include "Report/Logger.h"

DiagnosticElement* Diagnostic::addElement(DiagnosticKind kind, DiagnosticId id)
{
    auto       ptr = std::make_unique<DiagnosticElement>(kind, id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return raw;
}

Utf8 Diagnostic::build(const CompilerInstance& ci) const
{
    const auto& ids = ci.diagIds();
    Utf8        result;

    for (auto& e : elements_)
    {
        const auto idName = e->idName(ci);
        result += idName;
        result += "\n";

        if (e->file_ != nullptr)
        {
            result += e->file_->fullName().string();
            result += ": ";
            if (e->len_ != 0)
            {
                const auto loc = e->location(ci);
                Utf8       s   = std::format("{}:{}", loc.line, loc.column);
                result += s;
                result += "\n";
                const auto code = e->file_->codeLine(ci, loc.line);
                result += code;
                result += "\n";
                for (uint32_t i = 1; i < loc.column; ++i)
                    result += " ";
                for (uint32_t i = 0; i < e->len_; ++i)
                    result += "^";
                result += "\n";
            }
        }

        const auto msg = e->message(ci);
        result += msg;
        result += "\n";
    }

    return result;
}

void Diagnostic::report(const CompilerInstance& ci) const
{
    const auto msg     = build(ci);
    bool       dismiss = false;

    if (fileOwner_ != nullptr)
    {
        dismiss = fileOwner_->verifier().verify(ci, *this);
    }

    if (!dismiss)
    {
        auto& logger = ci.logger();
        logger.lock();
        logger.logEol();
        logger.log(msg);
        logger.unlock();
    }
}
