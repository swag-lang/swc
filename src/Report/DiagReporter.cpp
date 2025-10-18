#include "pch.h"

#include "Report/Diagnostic.h"
#include "Report/DiagReporter.h"

std::unique_ptr<Diagnostic> DiagReporter::diagnostic(DiagnosticId id)
{
    return std::make_unique<Diagnostic>(id);
}

void DiagReporter::report(const std::unique_ptr<Diagnostic>& diag)
{
}
