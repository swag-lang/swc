#include "pch.h"

#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagReporter.h"
#include "Report/Diagnostic.h"

namespace
{
#define SWAG_DIAG(__id, __txt) __txt,
    std::string_view g_DiagnosticIdMessages[] =
    {
#include "Report/DiagnosticList.h"

    };
#undef SWAG_DIAG
};

std::unique_ptr<Diagnostic> DiagReporter::diagnostic(DiagnosticKind kind, DiagnosticId id)
{
    return std::make_unique<Diagnostic>(kind, id);
}

std::string_view DiagReporter::diagnosticMessage(DiagnosticId id)
{
    return g_DiagnosticIdMessages[static_cast<int>(id)];
}

void DiagReporter::report(CompilerInstance& ci, const CompilerContext& cxt, Diagnostic& diag)
{
    diag.log(ci.logger());
}
