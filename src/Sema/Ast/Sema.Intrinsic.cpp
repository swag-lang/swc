#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstIntrinsicValue::semaPostNode(Sema& sema)
{
    SemaInfo::addSemaFlags(*this, NodeSemaFlags::ValueExpr);

    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicCompiler:
            return AstVisitStepResult::Continue;

        case TokenId::IntrinsicErr:
            sema.semaInfo().setType(sema.curNodeRef(), sema.typeMgr().typeAny());
            return AstVisitStepResult::Continue;
        case TokenId::IntrinsicByteCode:
            sema.semaInfo().setType(sema.curNodeRef(), sema.typeMgr().typeBool());
            return AstVisitStepResult::Continue;

        case TokenId::IntrinsicArgs:
        case TokenId::IntrinsicProcessInfos:
        case TokenId::IntrinsicIndex:
        case TokenId::IntrinsicRtFlags:
        case TokenId::IntrinsicModules:
        case TokenId::IntrinsicGvtd:
            return AstVisitStepResult::Continue;

        default:
            SemaError::raiseInternal(sema, *this);
            return AstVisitStepResult::Stop;
    }
}

SWC_END_NAMESPACE()
