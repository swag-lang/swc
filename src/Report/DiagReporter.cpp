#include "pch.h"

#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagReporter.h"
#include "Report/Diagnostic.h"

std::unique_ptr<Diagnostic> DiagReporter::diagnostic(DiagnosticId id)
{
    return std::make_unique<Diagnostic>(id);
}

void DiagReporter::report(CompilerInstance& ci, CompilerContext& cxt, Diagnostic& diag)
{
    diag.log(ci.logger());
}
