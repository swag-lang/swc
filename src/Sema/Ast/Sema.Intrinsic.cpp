#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

Result AstIntrinsicValue::semaPostNode(Sema& sema)
{
    SemaInfo::setIsValue(*this);

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

Result AstIntrinsicCallUnary::semaPostNode(Sema& sema)
{
    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicKindOf:
        case TokenId::IntrinsicDataOf:
            // TODO
            sema.setType(sema.curNodeRef(), sema.typeMgr().typePtrVoid());
            SemaInfo::setIsValue(*this);
            break;

        default:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            break;
    }

    return Result::Continue;
}

namespace
{
    Result semaIntrinsicContext(Sema& sema, AstIntrinsicCallZero& node)
    {
        const TypeRef typeRef = sema.typeMgr().structContext();
        if (typeRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().nameContext(), node.srcViewRef(), node.tokRef());
        const TypeInfo ty = TypeInfo::makeValuePointer(typeRef, TypeInfoFlagsE::Const);
        sema.setType(sema.curNodeRef(), sema.typeMgr().addType(ty));
        SemaInfo::setIsValue(node);
        return Result::Continue;
    }
};

Result AstIntrinsicCallZero::semaPostNode(Sema& sema)
{
    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicGetContext:
            return semaIntrinsicContext(sema, *this);

        case TokenId::IntrinsicDbgAlloc:
        case TokenId::IntrinsicSysAlloc:
        case TokenId::IntrinsicBcBreakpoint:
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            return Result::SkipChildren;
        default:
            return SemaError::raiseInternal(sema, *this);
    }
}

SWC_END_NAMESPACE();
