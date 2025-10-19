#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticElement.h"
#include "Report/Logger.h"

std::unique_ptr<Diagnostic> Diagnostic::instance()
{
    return std::make_unique<Diagnostic>();
}

DiagnosticElement* Diagnostic::addElement(DiagnosticKind kind, DiagnosticId id)
{
    auto ptr = std::make_unique<DiagnosticElement>(kind, id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return raw;
}

void Diagnostic::log(const Reporter& reporter, Logger& logger) const
{
    logger.lock();

    for (auto& e : elements_)
    {
        if (e->file_ != nullptr)
            logger.log(e->file_->fullName().string());

        if (e->len_ != 0)
        {
            const auto loc = e->getLocation();
            std::string s = std::format("{}:{}", loc.line, loc.column);
            logger.log(s);
        }
            
        const auto errMsg = e->format(reporter);
        logger.log(errMsg);
    }

    logger.unlock();
}
