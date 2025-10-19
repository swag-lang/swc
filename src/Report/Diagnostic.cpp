#include "pch.h"

#include "DiagReporter.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticElement.h"
#include "Report/Logger.h"

DiagnosticElement* Diagnostic::addElement(DiagnosticKind kind, DiagnosticId id)
{
    auto ptr = std::make_unique<DiagnosticElement>(kind, id);
    elements_.emplace_back(std::move(ptr));
    return ptr.get();
}

void Diagnostic::log(const DiagReporter& reporter, Logger& logger) const
{
    logger.lock();

    for (auto& e : elements_)
    {
        const auto errMsg = e->format(reporter);
        logger.log(errMsg);
    }

    logger.unlock();
}
