#include "pch.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstAccessModifier::semaPostNode(Sema& sema) const
{
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
