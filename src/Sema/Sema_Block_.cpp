#include "pch.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstFile::semaPreNode(Sema& sema)
{
    sema.pushScope(SemaScopeFlagsE::TopLevel);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstFile::semaPostNode(Sema& sema)
{
    sema.popScope();
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
