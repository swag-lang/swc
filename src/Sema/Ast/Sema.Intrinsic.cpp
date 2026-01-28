#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaInfo.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Enum.h"

SWC_BEGIN_NAMESPACE();

Result AstIntrinsicValue::semaPostNode(Sema& sema)
{
    SemaInfo::setIsValue(*this);

    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicIndex:
            return Result::Continue;

        default:
            return SemaError::raiseInternal(sema, *this);
    }
}

namespace
{
    Result semaIntrinsicDataOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const AstNodeRef   nodeArgRef = children[0];
        const SemaNodeView nodeView(sema, nodeArgRef);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));

        const TypeInfo* type = nodeView.type;

        TypeRef resultTypeRef = TypeRef::invalid();
        if (type->isString() || type->isCString())
        {
            resultTypeRef = sema.typeMgr().typeConstBlockPtrU8();
        }
        else if (type->isSlice())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->nestedTypeRef(), type->flags());
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
        else if (type->isAnyPointer())
        {
            resultTypeRef = nodeView.typeRef;
        }

        if (!resultTypeRef.isValid())
            return SemaError::raiseInvalidType(sema, nodeArgRef, nodeView.typeRef, sema.typeMgr().typeBlockPtrVoid());

        sema.setType(sema.curNodeRef(), resultTypeRef);
        SemaInfo::setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicKindOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const AstNodeRef   nodeArgRef = children[0];
        const SemaNodeView nodeView(sema, nodeArgRef);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));

        if (!nodeView.type || !nodeView.type->isAny())
            return SemaError::raiseRequestedTypeFam(sema, nodeArgRef, nodeView.typeRef, sema.typeMgr().typeAny());

        sema.setType(sema.curNodeRef(), sema.typeMgr().typeTypeInfo());
        SemaInfo::setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicCountOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        auto               ctx        = sema.ctx();
        const AstNodeRef   nodeArgRef = children[0];
        const SemaNodeView nodeView(sema, nodeArgRef);

        if (!nodeView.type)
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_countof, nodeArgRef);

        // Compile time
        if (nodeView.cst)
        {
            if (nodeView.cst->isString())
            {
                sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(ctx, nodeView.cst->getString().length()));
                return Result::Continue;
            }

            if (nodeView.cst->isSlice())
            {
                sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(ctx, nodeView.cst->getSliceCount()));
                return Result::Continue;
            }
        }

        if (nodeView.type->isEnum())
        {
            if (!nodeView.type->isCompleted(ctx))
                return sema.waitCompleted(nodeView.type, nodeArgRef);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(ctx, nodeView.type->symEnum().count()));
            return Result::Continue;
        }

        if (nodeView.type->isAnyString())
        {
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeU64());
            SemaInfo::setIsValue(node);
            return Result::Continue;
        }

        if (nodeView.type->isArray())
        {
            const uint64_t  sizeOf     = nodeView.type->sizeOf(ctx);
            const TypeRef   typeRef    = nodeView.type->arrayElemTypeRef();
            const TypeInfo& ty         = sema.typeMgr().get(typeRef);
            const uint64_t  sizeOfElem = ty.sizeOf(ctx);
            SWC_ASSERT(sizeOfElem > 0);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(ctx, sizeOf / sizeOfElem));
            return Result::Continue;
        }

        if (nodeView.type->isSlice())
        {
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeU64());
            SemaInfo::setIsValue(node);
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, nodeArgRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
        diag.report(ctx);
        return Result::Error;
    }

    Result semaIntrinsicMakeSlice(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children, bool forString)
    {
        auto nodeArg1Ref = children[0];
        auto nodeArg2Ref = children[1];

        const SemaNodeView nodeViewPtr(sema, nodeArg1Ref);
        SemaNodeView       nodeViewSize(sema, nodeArg2Ref);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewPtr.nodeRef));
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewSize.nodeRef));

        if (!nodeViewPtr.type->isAnyPointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeArg1Ref, nodeViewPtr.typeRef, sema.typeMgr().typeBlockPtrVoid());

        RESULT_VERIFY(Cast::cast(sema, nodeViewSize, sema.typeMgr().typeU64(), CastKind::Implicit));

        TypeRef typeRef;
        if (forString)
        {
            TypeInfo ty = TypeInfo::makeString();
            typeRef     = sema.typeMgr().addType(ty);
        }
        else
        {
            TypeInfo ty = TypeInfo::makeSlice(nodeViewPtr.type->nestedTypeRef());
            if (nodeViewPtr.type->isConst())
                ty.addFlag(TypeInfoFlagsE::Const);
            typeRef = sema.typeMgr().addType(ty);
        }

        sema.setType(sema.curNodeRef(), typeRef);
        SemaInfo::setIsValue(node);
        return Result::Continue;
    }
}

Result AstIntrinsicCall::semaPostNode(Sema& sema)
{
    const Token&            tok = sema.token(srcViewRef(), tokRef());
    SmallVector<AstNodeRef> children;
    sema.ast().nodes(children, spanChildrenRef);

    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
            return semaIntrinsicDataOf(sema, *this, children);
        case TokenId::IntrinsicKindOf:
            return semaIntrinsicKindOf(sema, *this, children);
        case TokenId::IntrinsicCountOf:
            return semaIntrinsicCountOf(sema, *this, children);
        case TokenId::IntrinsicMakeSlice:
            return semaIntrinsicMakeSlice(sema, *this, children, false);
        case TokenId::IntrinsicMakeString:
            return semaIntrinsicMakeSlice(sema, *this, children, true);

        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicCVaArg:
        case TokenId::IntrinsicMakeCallback:
        case TokenId::IntrinsicMakeInterface:
        case TokenId::IntrinsicMakeAny:
        case TokenId::IntrinsicIs:
        case TokenId::IntrinsicAs:
        case TokenId::IntrinsicTableOf:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            return Result::Continue;

        default:
            return SemaError::raiseInternal(sema, *this);
    }
}

SWC_END_NAMESPACE();
