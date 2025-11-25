#include "pch.h"
#include "Parser/AstVisit.h"
#include "Sema/SemaJob.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBuiltinType::semaPostNode(SemaJob& job)
{
    const auto& tok = job.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::TypeS32:
            setSemaType(job.typeMgr().getTypeInt(32, true));
            break;
        default:
            job.raiseUnsupported(this);
            break;
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
