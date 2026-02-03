#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"

SWC_BEGIN_NAMESPACE();

Result AstIntrinsicValue::semaPostNode(Sema& sema)
{
    sema.setIsValue(*this);

    const Token& tok = sema.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicIndex:
            return Result::Continue;

        default:
            return SemaError::raiseInternal(sema, sema.curNodeRef());
    }
}

namespace
{
    Result semaIntrinsicDataOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView nodeView(sema, children[0]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));

        const TypeInfo* type = nodeView.type;

        TypeRef resultTypeRef = TypeRef::invalid();
        if (type->isString() || type->isCString())
        {
            resultTypeRef = sema.typeMgr().typeConstBlockPtrU8();
        }
        else if (type->isSlice())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->payloadTypeRef(), type->flags());
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isArray())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->payloadArrayElemTypeRef(), type->flags());
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
            return SemaError::raiseInvalidType(sema, nodeView.nodeRef, nodeView.typeRef, sema.typeMgr().typeBlockPtrVoid());

        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicKindOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView nodeView(sema, children[0]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));

        if (!nodeView.type || !nodeView.type->isAny())
            return SemaError::raiseRequestedTypeFam(sema, nodeView.nodeRef, nodeView.typeRef, sema.typeMgr().typeAny());

        sema.setType(sema.curNodeRef(), sema.typeMgr().typeTypeInfo());
        sema.setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicCountOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        auto               ctx = sema.ctx();
        const SemaNodeView nodeView(sema, children[0]);

        if (!nodeView.type)
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_countof, nodeView.nodeRef);

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
                sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(ctx, nodeView.cst->getSlice().size()));
                return Result::Continue;
            }
        }

        if (nodeView.type->isEnum())
        {
            if (!nodeView.type->isCompleted(ctx))
                return sema.waitCompleted(nodeView.type, nodeView.nodeRef);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(ctx, nodeView.type->payloadSymEnum().count()));
            return Result::Continue;
        }

        if (nodeView.type->isAnyString())
        {
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeU64());
            sema.setIsValue(node);
            return Result::Continue;
        }

        if (nodeView.type->isArray())
        {
            const uint64_t  sizeOf     = nodeView.type->sizeOf(ctx);
            const TypeRef   typeRef    = nodeView.type->payloadArrayElemTypeRef();
            const TypeInfo& ty         = sema.typeMgr().get(typeRef);
            const uint64_t  sizeOfElem = ty.sizeOf(ctx);
            SWC_ASSERT(sizeOfElem > 0);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(ctx, sizeOf / sizeOfElem));
            return Result::Continue;
        }

        if (nodeView.type->isSlice())
        {
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeU64());
            sema.setIsValue(node);
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, nodeView.nodeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
        diag.report(ctx);
        return Result::Error;
    }

    Result semaIntrinsicMakeAny(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView nodeViewPtr(sema, children[0]);
        SemaNodeView       nodeViewType(sema, children[1]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewPtr.nodeRef));
        RESULT_VERIFY(SemaCheck::isValueOrTypeInfo(sema, nodeViewType));

        if (!nodeViewPtr.type->isValuePointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeViewPtr.nodeRef, nodeViewPtr.typeRef, sema.typeMgr().typeValuePtrVoid());
        if (!nodeViewType.type->isAnyTypeInfo(sema.ctx()))
            return SemaError::raiseRequestedTypeFam(sema, nodeViewType.nodeRef, nodeViewType.typeRef, sema.typeMgr().typeTypeInfo());

        // Check if the pointer is void* or a pointer to the type defined in the right expression
        const TypeRef typeRefPointee  = nodeViewPtr.type->payloadTypeRef();
        const TypeRef typeRefTypeInfo = sema.cstMgr().makeTypeValue(sema, nodeViewType.cstRef);
        if (!sema.typeMgr().get(typeRefPointee).isVoid())
        {
            if (typeRefPointee != typeRefTypeInfo)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_mkany_ptr, nodeViewPtr.nodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeViewPtr.typeRef);
                diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, typeRefTypeInfo);
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (nodeViewPtr.type->isConst())
            flags.add(TypeInfoFlagsE::Const);

        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAny(flags));
        sema.setType(sema.curNodeRef(), typeRef);
        sema.setIsValue(node);

        return Result::Continue;
    }

    Result semaIntrinsicMakeSlice(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children, bool forString)
    {
        const SemaNodeView nodeViewPtr(sema, children[0]);
        SemaNodeView       nodeViewSize(sema, children[1]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewPtr.nodeRef));
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewSize.nodeRef));

        if (!nodeViewPtr.type->isAnyPointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeViewPtr.nodeRef, nodeViewPtr.typeRef, sema.typeMgr().typeBlockPtrVoid());

        RESULT_VERIFY(Cast::cast(sema, nodeViewSize, sema.typeMgr().typeU64(), CastKind::Implicit));

        TypeRef typeRef;
        if (forString)
        {
            TypeInfo ty = TypeInfo::makeString();
            typeRef     = sema.typeMgr().addType(ty);
        }
        else
        {
            TypeInfo ty = TypeInfo::makeSlice(nodeViewPtr.type->payloadTypeRef());
            if (nodeViewPtr.type->isConst())
                ty.addFlag(TypeInfoFlagsE::Const);
            typeRef = sema.typeMgr().addType(ty);
        }

        sema.setType(sema.curNodeRef(), typeRef);
        sema.setIsValue(node);
        return Result::Continue;
    }
}

Result AstIntrinsicCall::semaPostNode(Sema& sema)
{
    const Token&            tok = sema.token(codeRef());
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
        case TokenId::IntrinsicMakeAny:
            return semaIntrinsicMakeAny(sema, *this, children);
        case TokenId::IntrinsicMakeSlice:
            return semaIntrinsicMakeSlice(sema, *this, children, false);
        case TokenId::IntrinsicMakeString:
            return semaIntrinsicMakeSlice(sema, *this, children, true);

        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicCVaArg:
        case TokenId::IntrinsicMakeCallback:
        case TokenId::IntrinsicMakeInterface:
        case TokenId::IntrinsicIs:
        case TokenId::IntrinsicAs:
        case TokenId::IntrinsicTableOf:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            return Result::Continue;

        default:
            return SemaError::raiseInternal(sema, sema.curNodeRef());
    }
}

SWC_END_NAMESPACE();
