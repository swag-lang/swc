#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
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
            SWC_INTERNAL_ERROR();
    }
}

namespace
{
    Result semaIntrinsicDataOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SemaNodeView view = sema.viewNodeTypeConstantSymbol(children[0]);
        if (view.sym() && view.sym()->isConstant() && view.cstRef().isInvalid())
        {
            RESULT_VERIFY(sema.waitSemaCompleted(view.sym(), sema.node(view.nodeRef()).codeRef()));
            view.compute(sema, children[0], SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        }

        RESULT_VERIFY(SemaCheck::isValue(sema, view.nodeRef()));

        const TypeInfo* type = view.type();

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
            resultTypeRef = view.typeRef();
        }

        if (!resultTypeRef.isValid())
            return SemaError::raiseInvalidType(sema, view.nodeRef(), view.typeRef(), sema.typeMgr().typeBlockPtrVoid());

        sema.setType(sema.curNodeRef(), resultTypeRef);
        ConstantIntrinsic::tryConstantFoldDataOf(sema, resultTypeRef, view);
        sema.setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicKindOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView view = sema.viewType(children[0]);

        RESULT_VERIFY(SemaCheck::isValue(sema, view.nodeRef()));

        if (!view.type() || !view.type()->isAny())
            return SemaError::raiseRequestedTypeFam(sema, view.nodeRef(), view.typeRef(), sema.typeMgr().typeAny());

        sema.setType(sema.curNodeRef(), sema.typeMgr().typeTypeInfo());
        sema.setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicCountOf(Sema& sema, const AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SWC_UNUSED(node);
        return SemaHelpers::intrinsicCountOf(sema, sema.curNodeRef(), children[0]);
    }

    Result semaIntrinsicMakeAny(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView nodeViewPtr = sema.viewType(children[0]);
        SemaNodeView       viewType    = sema.viewTypeConstant(children[1]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewPtr.nodeRef()));
        RESULT_VERIFY(SemaCheck::isValueOrTypeInfo(sema, viewType));

        if (!nodeViewPtr.type()->isValuePointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeViewPtr.nodeRef(), nodeViewPtr.typeRef(), sema.typeMgr().typeValuePtrVoid());
        if (!viewType.type()->isAnyTypeInfo(sema.ctx()))
            return SemaError::raiseRequestedTypeFam(sema, viewType.nodeRef(), viewType.typeRef(), sema.typeMgr().typeTypeInfo());

        // Check if the pointer is void* or a pointer to the type defined in the right expression
        const TypeRef typeRefPointee = nodeViewPtr.type()->payloadTypeRef();
        if (!sema.typeMgr().get(typeRefPointee).isVoid() && viewType.cstRef().isValid())
        {
            const TypeRef typeRefTypeInfo = sema.cstMgr().makeTypeValue(sema, viewType.cstRef());
            if (typeRefPointee != typeRefTypeInfo)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_mkany_ptr, nodeViewPtr.nodeRef());
                diag.addArgument(Diagnostic::ARG_TYPE, nodeViewPtr.typeRef());
                diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, typeRefTypeInfo);
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (nodeViewPtr.type()->isConst())
            flags.add(TypeInfoFlagsE::Const);

        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAny(flags));
        sema.setType(sema.curNodeRef(), typeRef);
        sema.setIsValue(node);

        return Result::Continue;
    }

    Result semaIntrinsicMakeSlice(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children, bool forString)
    {
        const SemaNodeView nodeViewPtr  = sema.viewType(children[0]);
        SemaNodeView       nodeViewSize = sema.viewNodeTypeConstant(children[1]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewPtr.nodeRef()));
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewSize.nodeRef()));

        if (!nodeViewPtr.type()->isAnyPointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeViewPtr.nodeRef(), nodeViewPtr.typeRef(), sema.typeMgr().typeBlockPtrVoid());

        RESULT_VERIFY(Cast::cast(sema, nodeViewSize, sema.typeMgr().typeU64(), CastKind::Implicit));

        TypeRef typeRef;
        if (forString)
        {
            TypeInfo ty = TypeInfo::makeString();
            typeRef     = sema.typeMgr().addType(ty);
        }
        else
        {
            TypeInfo ty = TypeInfo::makeSlice(nodeViewPtr.type()->payloadTypeRef());
            if (nodeViewPtr.type()->isConst())
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
    sema.ast().appendNodes(children, spanChildrenRef);

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
            SWC_INTERNAL_ERROR();

        default:
            SWC_INTERNAL_ERROR();
    }
}

Result AstCountOfExpr::semaPostNode(Sema& sema) const
{
    return SemaHelpers::intrinsicCountOf(sema, sema.curNodeRef(), nodeExprRef);
}

SWC_END_NAMESPACE();
