#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Type/Cast.h"

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
}

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

namespace
{
    Result semaIntrinsicStrLen(Sema& sema, AstIntrinsicCallUnary& node)
    {
        RESULT_VERIFY(SemaCheck::isValue(sema, node.nodeArgRef));
        const SemaNodeView nodeView(sema, node.nodeArgRef);

        if (!nodeView.type->isPointer())
        {
            return SemaError::raiseInvalidType(sema, node.nodeArgRef, sema.typeMgr().typePtrVoid(), nodeView.typeRef);
        }

        sema.setType(sema.curNodeRef(), sema.typeMgr().typeU64());
        SemaInfo::setIsValue(node);
        return Result::Continue;
    }
}

Result AstIntrinsicCallUnary::semaPostNode(Sema& sema)
{
    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicStrLen:
            return semaIntrinsicStrLen(sema, *this);

        case TokenId::IntrinsicKindOf:
        case TokenId::IntrinsicDataOf:
            // TODO
            sema.setType(sema.curNodeRef(), sema.typeMgr().typePtrVoid());
            SemaInfo::setIsValue(*this);
            return Result::Continue;

        case TokenId::IntrinsicAssert:
        case TokenId::IntrinsicSetContext:
        case TokenId::IntrinsicCountOf:
        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicMakeCallback:
        case TokenId::IntrinsicAlloc:
        case TokenId::IntrinsicFree:
        case TokenId::IntrinsicAbs:
        case TokenId::IntrinsicSqrt:
        case TokenId::IntrinsicSin:
        case TokenId::IntrinsicCos:
        case TokenId::IntrinsicTan:
        case TokenId::IntrinsicSinh:
        case TokenId::IntrinsicCosh:
        case TokenId::IntrinsicTanh:
        case TokenId::IntrinsicASin:
        case TokenId::IntrinsicACos:
        case TokenId::IntrinsicATan:
        case TokenId::IntrinsicLog:
        case TokenId::IntrinsicLog2:
        case TokenId::IntrinsicLog10:
        case TokenId::IntrinsicFloor:
        case TokenId::IntrinsicCeil:
        case TokenId::IntrinsicTrunc:
        case TokenId::IntrinsicRound:
        case TokenId::IntrinsicExp:
        case TokenId::IntrinsicExp2:
        case TokenId::IntrinsicByteSwap:
        case TokenId::IntrinsicBitCountNz:
        case TokenId::IntrinsicBitCountTz:
        case TokenId::IntrinsicBitCountLz:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            return Result::Continue;

        default:
            return SemaError::raiseInternal(sema, *this);
    }
}

namespace
{
    Result semaIntrinsicMakeSlice(Sema& sema, AstIntrinsicCallBinary& node, bool forString)
    {
        RESULT_VERIFY(SemaCheck::isValue(sema, node.nodeArg1Ref));
        RESULT_VERIFY(SemaCheck::isValue(sema, node.nodeArg2Ref));

        const SemaNodeView nodeViewPtr(sema, node.nodeArg1Ref);
        const SemaNodeView nodeViewSize(sema, node.nodeArg2Ref);

        if (!nodeViewPtr.type->isPointer())
            return SemaError::raiseRequestedTypeFam(sema, node.nodeArg1Ref, nodeViewPtr.typeRef, sema.typeMgr().typePtrVoid());

        if (nodeViewSize.typeRef != sema.typeMgr().typeU64())
        {
            CastContext castCtx(CastKind::Implicit);
            if (Cast::castAllowed(sema, castCtx, nodeViewSize.typeRef, sema.typeMgr().typeU64()) == Result::Continue)
                node.nodeArg2Ref = Cast::createImplicitCast(sema, sema.typeMgr().typeU64(), node.nodeArg2Ref);
            else
                return SemaError::raiseRequestedTypeFam(sema, node.nodeArg2Ref, nodeViewSize.typeRef, sema.typeMgr().typeInt(0, TypeInfo::Sign::Unknown));
        }

        TypeRef typeRef;
        if (forString)
        {
            TypeInfo ty = TypeInfo::makeString();
            typeRef     = sema.typeMgr().addType(ty);
        }
        else
        {
            TypeInfo ty = TypeInfo::makeSlice(nodeViewPtr.type->typeRef());
            if (nodeViewPtr.type->isConst())
                ty.addFlag(TypeInfoFlagsE::Const);
            typeRef = sema.typeMgr().addType(ty);
        }

        sema.setType(sema.curNodeRef(), typeRef);
        SemaInfo::setIsValue(node);
        return Result::Continue;
    }
}

Result AstIntrinsicCallBinary::semaPostNode(Sema& sema)
{
    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicMakeSlice:
            return semaIntrinsicMakeSlice(sema, *this, false);
        case TokenId::IntrinsicMakeString:
            return semaIntrinsicMakeSlice(sema, *this, true);
        case TokenId::IntrinsicMakeAny:
        case TokenId::IntrinsicCVaArg:
        case TokenId::IntrinsicRealloc:
        case TokenId::IntrinsicStrCmp:
        case TokenId::IntrinsicStringCmp:
        case TokenId::IntrinsicIs:
        case TokenId::IntrinsicTableOf:
        case TokenId::IntrinsicMin:
        case TokenId::IntrinsicMax:
        case TokenId::IntrinsicRol:
        case TokenId::IntrinsicRor:
        case TokenId::IntrinsicPow:
        case TokenId::IntrinsicATan2:
        case TokenId::IntrinsicAtomicXchg:
        case TokenId::IntrinsicAtomicXor:
        case TokenId::IntrinsicAtomicOr:
        case TokenId::IntrinsicAtomicAnd:
        case TokenId::IntrinsicAtomicAdd:
        case TokenId::IntrinsicCompilerError:
        case TokenId::IntrinsicCompilerWarning:
        case TokenId::IntrinsicPanic:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            return Result::Continue;

        default:
            return SemaError::raiseInternal(sema, *this);
    }
}

Result AstIntrinsicCallTernary::semaPostNode(Sema& sema) const
{
    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicMakeInterface:
        case TokenId::IntrinsicMemCmp:
        case TokenId::IntrinsicAs:
        case TokenId::CompilerGetTag:
        case TokenId::IntrinsicAtomicCmpXchg:
        case TokenId::IntrinsicTypeCmp:
        case TokenId::IntrinsicMulAdd:
        case TokenId::IntrinsicMemCpy:
        case TokenId::IntrinsicMemMove:
        case TokenId::IntrinsicMemSet:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            return Result::Continue;

        default:
            return SemaError::raiseInternal(sema, *this);
    }
}

SWC_END_NAMESPACE();
