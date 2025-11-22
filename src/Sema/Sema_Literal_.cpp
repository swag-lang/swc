#include "pch.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Sema/ConstantManager.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBoolLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok = job.token(srcViewRef(), tokRef());
    if (tok.is(TokenId::KwdTrue))
        setConstant(job.constMgr().boolTrue());
    else if (tok.is(TokenId::KwdFalse))
        setConstant(job.constMgr().boolFalse());
    else
        SWC_UNREACHABLE();

    return AstVisitStepResult::SkipChildren;
}

SWC_END_NAMESPACE()
