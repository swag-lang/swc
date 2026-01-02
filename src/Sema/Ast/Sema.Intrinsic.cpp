#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

Result AstIntrinsicValue::semaPostNode(Sema& sema)
{
    SemaInfo::addSemaFlags(*this, NodeSemaFlags::ValueExpr);

    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicCompiler:
            return Result::Continue;

        case TokenId::IntrinsicErr:
            sema.semaInfo().setType(sema.curNodeRef(), sema.typeMgr().typeAny());
            return Result::Continue;
        case TokenId::IntrinsicByteCode:
            sema.semaInfo().setType(sema.curNodeRef(), sema.typeMgr().typeBool());
            return Result::Continue;

        case TokenId::IntrinsicArgs:
        case TokenId::IntrinsicProcessInfos:
        case TokenId::IntrinsicIndex:
        case TokenId::IntrinsicRtFlags:
        case TokenId::IntrinsicModules:
        case TokenId::IntrinsicGvtd:
            return Result::Continue;

        default:
            return SemaError::raiseInternal(sema, *this);
    }
}

SWC_END_NAMESPACE()
