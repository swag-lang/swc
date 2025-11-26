#include "pch.h"

#include "ConstantManager.h"
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
    auto&          ctx            = job.ctx();
    const AstNode* nodeLiteralPtr = job.node(nodeLiteral);
    const AstNode* nodeSuffixPtr  = job.node(nodeSuffix);

    const TypeInfoRef type     = nodeSuffixPtr->getNodeTypeRef(ctx);
    bool              overflow = false;
    const ConstantRef newCst   = ctx.compiler().constMgr().convert(ctx, nodeLiteralPtr->getSemaConstant(ctx), type, overflow);
    setSemaConstant(newCst);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
