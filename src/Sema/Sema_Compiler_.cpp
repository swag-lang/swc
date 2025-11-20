#include "pch.h"
#include "ConstantManager.h"
#include "Parser/AstNodes.h"
#include "SemaJob.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstCompilerIf::semaPreChild(SemaJob& job, AstNodeRef& childRef)
{
    if (childRef == nodeCondition)
        return AstVisitStepResult::Continue;

    const auto nodeCond = job.node(nodeCondition);
    if (!nodeCond->isConstant())
        return AstVisitStepResult::Stop;

    const auto& constant = job.constMgr().get(nodeCond->getConstant());
    const auto& type     = job.typeMgr().get(constant.typeRef);
    if (!type.isBool())
        return AstVisitStepResult::Stop;

    if (childRef == nodeIfBlock && !constant.b)
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlock && constant.b)
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
