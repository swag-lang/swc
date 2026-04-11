#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    LoopSemaPayload& ensureLoopSemaPayload(Sema& sema, AstNodeRef nodeRef)
    {
        if (auto* payload = sema.semaPayload<LoopSemaPayload>(nodeRef))
            return *payload;

        auto* payload = sema.compiler().allocate<LoopSemaPayload>();
        sema.setSemaPayload(nodeRef, payload);
        return *payload;
    }

    void markIntrinsicOperandAddressableStorage(const SemaNodeView& operandView)
    {
        if (!operandView.sym() || !operandView.sym()->isVariable() || !operandView.type() || operandView.type()->isReference() || operandView.type()->isAnyPointer())
            return;

        auto& symVar = operandView.sym()->cast<SymbolVariable>();
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            symVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
    }

    Result semaIntrinsicLifecycleStmt(Sema& sema, AstNodeRef whatRef, AstNodeRef countRef)
    {
        const SemaNodeView whatView = sema.viewNodeTypeSymbol(whatRef);
        SWC_RESULT(SemaCheck::isValue(sema, whatView.nodeRef()));

        if (countRef.isValid())
        {
            SemaNodeView countView = sema.viewNodeTypeConstant(countRef);
            SWC_RESULT(SemaCheck::isValue(sema, countView.nodeRef()));
            SWC_RESULT(Cast::cast(sema, countView, sema.typeMgr().typeU64(), CastKind::Implicit));

            if (!whatView.type() || !whatView.type()->isAnyPointer())
                return SemaError::raiseRequestedTypeFam(sema, whatView.nodeRef(), whatView.typeRef(), sema.typeMgr().typeBlockPtrVoid());
            return Result::Continue;
        }

        if (whatView.type() && (whatView.type()->isAnyPointer() || whatView.type()->isReference()))
            return Result::Continue;

        SWC_ASSERT(whatView.node() != nullptr);
        if (!sema.isLValue(*whatView.node()))
            return SemaError::raise(sema, DiagnosticId::sema_err_take_address_not_lvalue, whatView.nodeRef());

        markIntrinsicOperandAddressableStorage(whatView);
        return Result::Continue;
    }

}

Result AstIntrinsicValue::semaPostNode(Sema& sema)
{
    sema.setIsValue(*this);

    const Token& tok = sema.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicIndex:
        {
            const TypeRef indexTypeRef = sema.frame().currentLoopIndexTypeRef();
            if (!indexTypeRef.isValid())
                return SemaError::raise(sema, DiagnosticId::sema_err_index_outside_loop, sema.curNodeRef());

            const AstNodeRef ownerRef = sema.frame().currentLoopIndexOwnerRef();
            if (ownerRef.isValid())
                ensureLoopSemaPayload(sema, ownerRef).usesLoopIndex = true;

            sema.setType(sema.curNodeRef(), indexTypeRef);
            return Result::Continue;
        }

        default:
            SWC_INTERNAL_ERROR();
    }
}

Result AstIntrinsicDrop::semaPostNode(Sema& sema) const
{
    return semaIntrinsicLifecycleStmt(sema, nodeWhatRef, nodeCountRef);
}

Result AstIntrinsicPostCopy::semaPostNode(Sema& sema) const
{
    return semaIntrinsicLifecycleStmt(sema, nodeWhatRef, nodeCountRef);
}

Result AstIntrinsicPostMove::semaPostNode(Sema& sema) const
{
    return semaIntrinsicLifecycleStmt(sema, nodeWhatRef, nodeCountRef);
}

namespace
{
    Result semaIntrinsicDataOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SemaNodeView view = sema.viewNodeTypeConstantSymbol(children[0]);
        if (view.sym() && view.sym()->isConstant() && view.cstRef().isInvalid())
        {
            SWC_RESULT(sema.waitSemaCompleted(view.sym(), sema.node(view.nodeRef()).codeRef()));
            view.compute(sema, children[0], SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        }

        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));

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
        else if (type->isInterface())
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

        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));

        if (!view.type() || (!view.type()->isAny() && !view.type()->isInterface()))
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

        SWC_RESULT(SemaCheck::isValue(sema, nodeViewPtr.nodeRef()));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, viewType));

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

        if (sema.isCurrentFunction())
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, node, typeRef, "__intrinsic_runtime_storage"));

        return Result::Continue;
    }

    Result semaIntrinsicMakeSlice(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children, bool forString)
    {
        const SemaNodeView nodeViewPtr  = sema.viewType(children[0]);
        SemaNodeView       nodeViewSize = sema.viewNodeTypeConstant(children[1]);

        SWC_RESULT(SemaCheck::isValue(sema, nodeViewPtr.nodeRef()));
        SWC_RESULT(SemaCheck::isValue(sema, nodeViewSize.nodeRef()));

        if (!nodeViewPtr.type()->isAnyPointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeViewPtr.nodeRef(), nodeViewPtr.typeRef(), sema.typeMgr().typeBlockPtrVoid());

        SWC_RESULT(Cast::cast(sema, nodeViewSize, sema.typeMgr().typeU64(), CastKind::Implicit));

        TypeRef typeRef;
        if (forString)
        {
            const TypeInfo ty = TypeInfo::makeString();
            typeRef           = sema.typeMgr().addType(ty);
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

        if (sema.isCurrentFunction())
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, node, typeRef, "__intrinsic_runtime_storage"));

        return Result::Continue;
    }

    TypeRef intrinsicMakeInterfaceRuntimeStorageTypeRef(Sema& sema, TypeRef objectTypeRef, TypeRef interfaceTypeRef)
    {
        if (interfaceTypeRef.isInvalid())
            return TypeRef::invalid();

        const TypeInfo& interfaceType = sema.typeMgr().get(interfaceTypeRef);
        SWC_ASSERT(interfaceType.isInterface());

        uint64_t objectStorageSize = 0;
        if (objectTypeRef.isValid())
        {
            const TypeInfo& objectType = sema.typeMgr().get(objectTypeRef);
            if (!objectType.isNull() && !objectType.isPointerLike() && !objectType.isReference())
                objectStorageSize = objectType.sizeOf(sema.ctx());
        }

        constexpr uint64_t     interfaceStorageSize = sizeof(Runtime::Interface);
        SmallVector4<uint64_t> dims;
        dims.push_back(interfaceStorageSize + objectStorageSize);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
    }

    bool isMakeInterfaceTypeInfoOperand(Sema& sema, const SemaNodeView& view)
    {
        if (view.type() && (view.type()->isAnyTypeInfo(sema.ctx()) || view.type()->isTypeValue()))
            return true;
        if (!view.cstRef().isValid())
            return false;
        return sema.cstMgr().makeTypeValue(sema, view.cstRef()).isValid();
    }

    TypeRef makeInterfaceTypeValueRef(Sema& sema, const SemaNodeView& view)
    {
        if (view.type() && view.type()->isTypeValue())
            return sema.typeMgr().get(view.type()->payloadTypeRef()).unwrapAliasEnum(sema.ctx(), view.type()->payloadTypeRef());

        if (!view.cstRef().isValid())
            return TypeRef::invalid();

        const TypeRef typeRef = sema.cstMgr().makeTypeValue(sema, view.cstRef());
        if (!typeRef.isValid())
            return TypeRef::invalid();

        return sema.typeMgr().get(typeRef).unwrapAliasEnum(sema.ctx(), typeRef);
    }

    Result semaIntrinsicMakeInterface(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView objectView = sema.viewType(children[0]);
        SemaNodeView       typeView   = sema.viewTypeConstant(children[1]);
        SemaNodeView       itfView    = sema.viewTypeConstant(children[2]);

        SWC_RESULT(SemaCheck::isValue(sema, objectView.nodeRef()));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, typeView));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, itfView));

        if (!isMakeInterfaceTypeInfoOperand(sema, typeView))
            return SemaError::raiseRequestedTypeFam(sema, typeView.nodeRef(), typeView.typeRef(), sema.typeMgr().typeTypeInfo());
        if (!isMakeInterfaceTypeInfoOperand(sema, itfView))
            return SemaError::raiseRequestedTypeFam(sema, itfView.nodeRef(), itfView.typeRef(), sema.typeMgr().typeTypeInfo());

        const TypeRef interfaceTypeRef = makeInterfaceTypeValueRef(sema, itfView);
        if (!interfaceTypeRef.isValid() || !sema.typeMgr().get(interfaceTypeRef).isInterface())
            return SemaError::raise(sema, DiagnosticId::sema_err_not_type, itfView.nodeRef());

        const TypeRef objectTypeRef = makeInterfaceTypeValueRef(sema, typeView);
        if (objectTypeRef.isValid())
        {
            const TypeInfo& objectType = sema.typeMgr().get(objectTypeRef);
            if (objectType.isStruct())
            {
                const TypeInfo& interfaceType = sema.typeMgr().get(interfaceTypeRef);
                SWC_RESULT(sema.waitSemaCompleted(&objectType, typeView.nodeRef()));
                SWC_RESULT(sema.waitSemaCompleted(&interfaceType, itfView.nodeRef()));
                if (!objectType.payloadSymStruct().implementsInterfaceOrUsingFields(sema, interfaceType.payloadSymInterface()))
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_cast_to_interface, typeView.nodeRef());
                    diag.addArgument(Diagnostic::ARG_TYPE, objectTypeRef);
                    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, interfaceTypeRef);
                    diag.report(sema.ctx());
                    return Result::Error;
                }
            }
        }

        sema.setType(sema.curNodeRef(), interfaceTypeRef);
        sema.setIsValue(node);

        if (sema.isCurrentFunction())
        {
            const TypeRef storageTypeRef = intrinsicMakeInterfaceRuntimeStorageTypeRef(sema, objectView.typeRef(), interfaceTypeRef);
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, node, storageTypeRef, "__intrinsic_runtime_storage"));
        }

        return Result::Continue;
    }

    Result semaIntrinsicIs(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SemaNodeView toTypeView   = sema.viewTypeConstant(children[0]);
        SemaNodeView fromTypeView = sema.viewTypeConstant(children[1]);

        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, toTypeView));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, fromTypeView));

        if (!isMakeInterfaceTypeInfoOperand(sema, toTypeView))
            return SemaError::raiseRequestedTypeFam(sema, toTypeView.nodeRef(), toTypeView.typeRef(), sema.typeMgr().typeTypeInfo());
        if (!isMakeInterfaceTypeInfoOperand(sema, fromTypeView))
            return SemaError::raiseRequestedTypeFam(sema, fromTypeView.nodeRef(), fromTypeView.typeRef(), sema.typeMgr().typeTypeInfo());

        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
        sema.setIsValue(node);
        return SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), IdentifierManager::RuntimeFunctionKind::Is, node.codeRef());
    }

    Result semaIntrinsicAs(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SemaNodeView toTypeView   = sema.viewTypeConstant(children[0]);
        SemaNodeView fromTypeView = sema.viewTypeConstant(children[1]);
        const auto   ptrView      = sema.viewType(children[2]);

        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, toTypeView));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, fromTypeView));
        SWC_RESULT(SemaCheck::isValue(sema, ptrView.nodeRef()));

        if (!isMakeInterfaceTypeInfoOperand(sema, toTypeView))
            return SemaError::raiseRequestedTypeFam(sema, toTypeView.nodeRef(), toTypeView.typeRef(), sema.typeMgr().typeTypeInfo());
        if (!isMakeInterfaceTypeInfoOperand(sema, fromTypeView))
            return SemaError::raiseRequestedTypeFam(sema, fromTypeView.nodeRef(), fromTypeView.typeRef(), sema.typeMgr().typeTypeInfo());
        if (!ptrView.type() || !ptrView.type()->isPointerOrReference())
            return SemaError::raiseRequestedTypeFam(sema, ptrView.nodeRef(), ptrView.typeRef(), sema.typeMgr().typeValuePtrVoid());

        const TypeRef resultTypeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(sema.typeMgr().typeVoid(), TypeInfoFlagsE::Nullable));
        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsValue(node);
        return SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), IdentifierManager::RuntimeFunctionKind::As, node.codeRef());
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
        case TokenId::IntrinsicMakeInterface:
            return semaIntrinsicMakeInterface(sema, *this, children);
        case TokenId::IntrinsicIs:
            return semaIntrinsicIs(sema, *this, children);
        case TokenId::IntrinsicAs:
            return semaIntrinsicAs(sema, *this, children);

        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicCVaArg:
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
