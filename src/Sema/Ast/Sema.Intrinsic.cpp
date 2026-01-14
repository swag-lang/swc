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
    Result semaIntrinsicDataOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& childs)
    {
        const auto nodeArgRef = childs[0];
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeArgRef));
        const SemaNodeView nodeView(sema, nodeArgRef);
        const auto         type = nodeView.type;

        TypeRef resultTypeRef = TypeRef::invalid();
        if (type->isString() || type->isCString())
        {
            resultTypeRef = sema.typeMgr().typeConstBlockPtrU8();
        }
        else if (type->isSlice())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->underlyingTypeRef(), type->flags());
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isArray())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->arrayElemTypeRef(), type->flags());
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isAny())
        {
            resultTypeRef = sema.typeMgr().typeBlockPtrVoid();
        }
        else if (type->isPointer())
        {
            resultTypeRef = nodeView.typeRef;
        }

        if (!resultTypeRef.isValid())
            return SemaError::raiseInvalidType(sema, nodeArgRef, nodeView.typeRef, sema.typeMgr().typeBlockPtrVoid());

        sema.setType(sema.curNodeRef(), resultTypeRef);
        SemaInfo::setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicKindOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& childs)
    {
        // TODO
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBlockPtrVoid());
        SemaInfo::setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicMakeSlice(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& childs, bool forString)
    {
        auto nodeArg1Ref = childs[0];
        auto nodeArg2Ref = childs[1];

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeArg1Ref));
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeArg2Ref));

        const SemaNodeView nodeViewPtr(sema, nodeArg1Ref);
        SemaNodeView       nodeViewSize(sema, nodeArg2Ref);

        if (!nodeViewPtr.type->isPointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeArg1Ref, nodeViewPtr.typeRef, sema.typeMgr().typeBlockPtrVoid());

        RESULT_VERIFY(Cast::cast(sema, nodeViewSize, sema.typeMgr().typeU64(), CastKind::Implicit));
        // nodeArg2Ref = nodeViewSize.nodeRef; // Cannot update childs directly as it's a Span, but it doesn't matter for slice type determination

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

    Result semaIntrinsicContext(Sema& sema, AstIntrinsicCall& node)
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

Result AstIntrinsicCall::semaPostNode(Sema& sema)
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
    }

    SmallVector<AstNodeRef> childs;
    sema.ast().nodes(childs, spanChildrenRef);

    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
            return semaIntrinsicDataOf(sema, *this, childs);
        case TokenId::IntrinsicKindOf:
            return semaIntrinsicKindOf(sema, *this, childs);

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
    }

    switch (tok.id)
    {
        case TokenId::IntrinsicMakeSlice:
            return semaIntrinsicMakeSlice(sema, *this, childs, false);
        case TokenId::IntrinsicMakeString:
            return semaIntrinsicMakeSlice(sema, *this, childs, true);
            
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
    }

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
