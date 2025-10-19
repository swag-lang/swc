#include "pch.h"

#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Diagnostic.h"
#include "Report/Reporter.h"

Reporter::Reporter()
{
    initErrors();
}

std::unique_ptr<Diagnostic> Reporter::diagnostic()
{
    return std::make_unique<Diagnostic>();
}

std::string_view Reporter::diagMessage(DiagnosticId id) const
{
    return diagMsgs_[static_cast<int>(id)];
}

void Reporter::report(const CompilerInstance& ci, const CompilerContext& ctx, const Diagnostic& diag) const
{
    diag.log(*this, ci.logger());
}
