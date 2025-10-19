#include "pch.h"

#include "Main/CompilerContext.h"
#include "Report/Diagnostic.h"
#include "Report/Reporter.h"

Reporter::Reporter()
{
    initErrors();
}

std::string_view Reporter::diagMessage(DiagnosticId id) const
{
    SWAG_ASSERT(static_cast<size_t>(id) < diagMsgs_.size());
    return diagMsgs_[static_cast<size_t>(id)];
}

void Reporter::report(const CompilerInstance& ci, const CompilerContext& ctx, const Diagnostic& diag)
{
    diag.log(ci);
}
