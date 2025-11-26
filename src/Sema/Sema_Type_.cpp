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
            return AstVisitStepResult::Continue;

        default:
            break;
    }

    job.raiseInternalError(this);
    return AstVisitStepResult::Stop;
}

AstVisitStepResult AstSuffixLiteral::semaPostNode(SemaJob& job)
{
    const auto& ctx            = job.ctx();
    const auto& nodeLiteralPtr = job.node(nodeLiteral);
    const auto& nodeSuffixPtr  = job.node(nodeSuffix);

    setSemaConstant(nodeLiteralPtr->getSemaConstantRef(ctx));
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
