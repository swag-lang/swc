#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticElement.h"
#include "Report/Logger.h"
#include "Reporter.h"

DiagnosticElement* Diagnostic::addElement(DiagnosticKind kind, DiagnosticId id)
{
    auto       ptr = std::make_unique<DiagnosticElement>(kind, id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return raw;
}

Result Diagnostic::report(const CompilerInstance& ci) const
{
    auto&       logger   = ci.logger();
    const auto& reporter = ci.diagReporter();

    logger.lock();

    logger.logEol();
    for (auto& e : elements_)
    {
        if (e->file_ != nullptr)
        {
            logger.log(e->file_->fullName().string());
            logger.log(": ");
            if (e->len_ != 0)
            {
                const auto  loc = e->getLocation(ci);
                Utf8 s   = std::format("{}:{}", loc.line, loc.column);
                logger.log(s);
                logger.logEol();
                const auto code = e->file_->codeLine(ci, loc.line);
                logger.log(code);
                logger.logEol();
                for (uint32_t i = 1; i < loc.column; ++i)
                    logger.log(" ");
                for (uint32_t i = 0; i < e->len_; ++i)
                    logger.log("^");
                logger.logEol();
            }
        }

        const auto errMsg = e->format(reporter);
        logger.log(errMsg);
        logger.logEol();
    }

    logger.unlock();
    return Result::Error;   
}
