#include "pch.h"

#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagReporter.h"
#include "Report/Diagnostic.h"

DiagReporter::DiagReporter()
{
    initErrors();
}

std::unique_ptr<Diagnostic> DiagReporter::diagnostic()
{
    return std::make_unique<Diagnostic>();
}

std::string_view DiagReporter::diagMessage(DiagnosticId id) const
{
    return diagMsgs_[static_cast<int>(id)];
}

void DiagReporter::report(CompilerInstance& ci, const CompilerContext& ctx, Diagnostic& diag)
{
    diag.log(*this, ci.logger());
}
