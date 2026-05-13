#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool intrinsicInitPreservesAliasType(const TypeInfo& rawType)
    {
        return rawType.isEnum() ||
               rawType.isBool() ||
               rawType.isIntLike() ||
               rawType.isFloat() ||
               rawType.isAnyPointer() ||
               rawType.isReference() ||
               rawType.isCString() ||
               rawType.isTypeInfo() ||
               (rawType.isFunction() && !rawType.isLambdaClosure());
    }

    TypeRef normalizeIntrinsicInitTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (!typeInfo.isAlias())
            return typeRef;

        const TypeRef rawTypeRef = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        if (rawTypeRef.isValid() && !intrinsicInitPreservesAliasType(sema.typeMgr().get(rawTypeRef)))
            return rawTypeRef;
        return typeRef;
    }

    TypeRef intrinsicInitFillTypeRef(Sema& sema, TypeRef whatTypeRef)
    {
        whatTypeRef = normalizeIntrinsicInitTypeRef(sema, whatTypeRef);
        if (!whatTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& whatType = sema.typeMgr().get(whatTypeRef);
        if (whatType.isReference() || whatType.isAnyPointer())
            whatTypeRef = normalizeIntrinsicInitTypeRef(sema, whatType.payloadTypeRef());

        while (whatTypeRef.isValid())
        {
            const TypeInfo& currentType = sema.typeMgr().get(whatTypeRef);
            if (!currentType.isArray())
                break;
            whatTypeRef = normalizeIntrinsicInitTypeRef(sema, currentType.payloadArrayElemTypeRef());
        }

        return whatTypeRef;
    }

    void collectIntrinsicInitArgs(SmallVector<AstNodeRef>& outArgs, const Ast& ast, const AstIntrinsicInit& node)
    {
        ast.appendNodes(outArgs, node.spanArgsRef);
    }

    bool intrinsicInitTreatsArgsAsStructTuple(Sema& sema, TypeRef fillTypeRef, const SmallVector<AstNodeRef>& args)
    {
        if (args.empty() || !fillTypeRef.isValid())
            return false;

        const TypeInfo& fillType = sema.typeMgr().get(fillTypeRef);
        if (!fillType.isStruct())
            return false;
        if (args.size() != 1)
            return true;

        const SemaNodeView argView = sema.viewType(args.front());
        if (!argView.type())
            return true;
        if (argView.typeRef() == fillTypeRef)
            return false;

        return !argView.type()->isStruct() && !argView.type()->isAggregateStruct();
    }

    LoopSemaPayload& ensureLoopSemaPayload(Sema& sema, AstNodeRef nodeRef)
    {
        if (auto* payload = sema.semaPayload<LoopSemaPayload>(nodeRef))
            return *payload;

        auto* payload = sema.compiler().allocate<LoopSemaPayload>();
        sema.setSemaPayload(nodeRef, payload);
        return *payload;
    }

    const TypeInfo* normalizedIntrinsicOperandType(Sema& sema, const SemaNodeView& operandView)
    {
        if (!operandView.type())
            return nullptr;

        const TypeRef typeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), operandView.typeRef());
        return &sema.typeMgr().get(typeRef);
    }

    void markIntrinsicOperandAddressableStorage(Sema& sema, const SemaNodeView& operandView)
    {
        const TypeInfo* operandType = normalizedIntrinsicOperandType(sema, operandView);
        if (!operandView.sym() || !operandView.sym()->isVariable() || !operandType || operandType->isReference() || operandType->isAnyPointer())
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

        const TypeInfo* whatType = normalizedIntrinsicOperandType(sema, whatView);
        if (countRef.isValid())
        {
            SemaNodeView countView = sema.viewNodeTypeConstant(countRef);
            SWC_RESULT(SemaCheck::isValue(sema, countView.nodeRef()));
            SWC_RESULT(Cast::cast(sema, countView, sema.typeMgr().typeU64(), CastKind::Implicit));

            if (!whatType || (!whatType->isAnyPointer() && !whatType->isReference()))
                return SemaError::raiseRequestedTypeFam(sema, whatView.nodeRef(), whatView.typeRef(), sema.typeMgr().typeBlockPtrVoid());
            return Result::Continue;
        }

        if (whatType && (whatType->isAnyPointer() || whatType->isReference()))
            return Result::Continue;

        SWC_ASSERT(whatView.node() != nullptr);
        if (!sema.isLValue(*whatView.node()))
            return SemaError::raise(sema, DiagnosticId::sema_err_take_address_not_lvalue, whatView.nodeRef());

        markIntrinsicOperandAddressableStorage(sema, whatView);
        return Result::Continue;
    }

}

Result AstIntrinsicInit::semaPostNode(Sema& sema) const
{
    SWC_RESULT(semaIntrinsicLifecycleStmt(sema, nodeWhatRef, nodeCountRef));

    const TypeRef fillTypeRef = intrinsicInitFillTypeRef(sema, sema.viewType(nodeWhatRef).typeRef());
    SWC_ASSERT(fillTypeRef.isValid());
    if (fillTypeRef.isInvalid())
        return Result::Error;

    SmallVector<AstNodeRef> args;
    collectIntrinsicInitArgs(args, sema.ast(), *this);
    if (args.empty())
        return Result::Continue;

    if (intrinsicInitTreatsArgsAsStructTuple(sema, fillTypeRef, args))
    {
        const TypeInfo& fillType = sema.typeMgr().get(fillTypeRef);
        SWC_ASSERT(fillType.isStruct());
        SWC_RESULT(sema.waitSemaCompleted(&fillType, nodeWhatRef));

        const auto& fields = fillType.payloadSymStruct().fields();
        if (args.size() > fields.size())
            return SemaError::raise(sema, DiagnosticId::sema_err_too_many_arguments, sema.curNodeRef());

        for (size_t i = 0; i < args.size(); ++i)
        {
            SWC_ASSERT(fields[i] != nullptr);
            SemaNodeView argView = sema.viewNodeTypeConstant(args[i]);
            SWC_RESULT(Cast::cast(sema, argView, fields[i]->typeRef(), CastKind::Initialization));
        }

        if (sema.isCurrentFunction())
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, *this, fillTypeRef, "__intrinsic_runtime_storage"));
        return Result::Continue;
    }

    if (args.size() != 1)
        return SemaError::raise(sema, DiagnosticId::sema_err_too_many_arguments, sema.curNodeRef());

    SemaNodeView argView = sema.viewNodeTypeConstant(args.front());
    return Cast::cast(sema, argView, fillTypeRef, CastKind::Initialization);
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
        bool            handledSpecOp = false;
        SymbolFunction* calledFn      = nullptr;
        SWC_RESULT(SemaSpecOp::tryResolveDataOf(sema, children[0], calledFn, handledSpecOp));
        if (handledSpecOp)
        {
            if (calledFn != nullptr)
            {
                auto* payload = sema.semaPayload<DataOfSpecOpPayload>(sema.curNodeRef());
                if (!payload)
                {
                    payload = sema.compiler().allocate<DataOfSpecOpPayload>();
                    sema.setSemaPayload(sema.curNodeRef(), payload);
                }

                payload->calledFn = calledFn;
            }

            sema.setIsValue(node);
            return Result::Continue;
        }

        SemaNodeView view = sema.viewNodeTypeConstantSymbol(children[0]);
        if (view.sym() && view.sym()->isConstant() && view.cstRef().isInvalid())
        {
            SWC_RESULT(sema.waitSemaCompleted(view.sym(), sema.node(view.nodeRef()).codeRef()));
            view.compute(sema, children[0], SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        }

        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));

        TypeRef dataTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), view.typeRef());
        if (view.cstRef().isValid())
            dataTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(sema, dataTypeRef, view.cstRef());
        const TypeInfo* type  = &sema.typeMgr().get(dataTypeRef);
        TypeInfoFlags   flags = type->flags();
        flags.add(view.type()->flags());
        if (SemaCheck::isConstAssignmentTarget(sema, view.nodeRef(), view))
            flags.add(TypeInfoFlagsE::Const);

        TypeInfoFlags bindingFlags = flags;
        if (view.sym() && (view.sym()->isLetVariable() || view.sym()->isConstant()))
            bindingFlags.add(TypeInfoFlagsE::Const);

        TypeRef resultTypeRef = TypeRef::invalid();
        if (type->isString() || type->isCString())
        {
            resultTypeRef = sema.typeMgr().typeConstBlockPtrU8();
        }
        else if (type->isSlice())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->payloadTypeRef(), bindingFlags);
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isArray())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->payloadArrayElemTypeRef(), bindingFlags);
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isAny())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(sema.typeMgr().typeVoid(), flags);
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isInterface())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(sema.typeMgr().typeVoid(), flags);
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isAnyPointer())
        {
            resultTypeRef = dataTypeRef;
        }

        if (!resultTypeRef.isValid())
            return SemaError::raiseInvalidType(sema, view.nodeRef(), view.typeRef(), sema.typeMgr().typeBlockPtrVoid());

        const TypeRef sourceRuntimeStorageTypeRef = SemaHelpers::smallByValueArrayRuntimeStorageTypeRef(sema, view.nodeRef(), dataTypeRef, view.cstRef());
        if (sourceRuntimeStorageTypeRef.isValid() && sema.isCurrentFunction())
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, view.nodeRef(), sema.node(view.nodeRef()), sourceRuntimeStorageTypeRef, "__dataof_source_runtime_storage"));

        sema.setType(sema.curNodeRef(), resultTypeRef);
        ConstantIntrinsic::tryConstantFoldDataOf(sema, resultTypeRef, view);
        sema.setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicKindOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView view = sema.viewType(children[0]);

        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));

        if (!view.type())
            return SemaError::raiseRequestedTypeFam(sema, view.nodeRef(), view.typeRef(), sema.typeMgr().typeAny());

        const TypeRef   kindTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), view.typeRef());
        const TypeInfo& kindType    = sema.typeMgr().get(kindTypeRef);
        if (!kindType.isAny() && !kindType.isInterface())
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

    bool isTypeInfoOperand(Sema& sema, const SemaNodeView& view)
    {
        if (view.type() && (view.type()->isAnyTypeInfo(sema.ctx()) || view.type()->isTypeValue()))
            return true;
        return SemaHelpers::resolveRepresentedTypeRef(sema, view).isValid();
    }

    Result semaIntrinsicMakeAny(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView nodeViewPtr = sema.viewType(children[0]);
        SemaNodeView       viewType    = sema.viewTypeConstant(children[1]);

        SWC_RESULT(SemaCheck::isValue(sema, nodeViewPtr.nodeRef()));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, viewType));

        const TypeRef   ptrTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), nodeViewPtr.typeRef());
        const TypeInfo& ptrType    = sema.typeMgr().get(ptrTypeRef);
        if (!ptrType.isAnyPointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeViewPtr.nodeRef(), nodeViewPtr.typeRef(), sema.typeMgr().typeValuePtrVoid());
        if (!isTypeInfoOperand(sema, viewType))
            return SemaError::raiseRequestedTypeFam(sema, viewType.nodeRef(), viewType.typeRef(), sema.typeMgr().typeTypeInfo());

        // Check if the pointer is void or a pointer to the type defined in the right expression
        const TypeRef typeRefPointee  = ptrType.payloadTypeRef();
        const TypeRef typeRefTypeInfo = SemaHelpers::resolveRepresentedTypeRef(sema, viewType);
        if (!sema.typeMgr().get(typeRefPointee).isVoid() && typeRefTypeInfo.isValid())
        {
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
        if (ptrType.isConst())
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

        const TypeRef   ptrTypeRef   = SemaHelpers::unwrapAliasRefType(sema.ctx(), nodeViewPtr.typeRef());
        const TypeInfo& ptrType      = sema.typeMgr().get(ptrTypeRef);
        const bool      ptrIsCString = ptrType.isCString();
        if (!ptrType.isAnyPointer() && !ptrIsCString)
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
            const TypeRef elementTypeRef = ptrIsCString ? sema.typeMgr().typeU8() : ptrType.payloadTypeRef();
            TypeInfo      ty             = TypeInfo::makeSlice(elementTypeRef);
            if (ptrType.isConst() || ptrIsCString)
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
            if (!objectType.isNull() && !objectType.isPointerLikeAliasAware(sema.ctx()) && !objectType.isReference())
                objectStorageSize = objectType.sizeOf(sema.ctx());
        }

        constexpr uint64_t     interfaceStorageSize = sizeof(Runtime::Interface);
        SmallVector4<uint64_t> dims;
        dims.push_back(interfaceStorageSize + objectStorageSize);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
    }

    bool makeInterfaceObjectIsConst(Sema& sema, const SemaNodeView& objectView)
    {
        if (!objectView.type())
            return false;

        if (objectView.type()->isConst())
            return true;

        const TypeRef objectDataTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), objectView.typeRef());
        if (objectDataTypeRef.isValid() && sema.typeMgr().get(objectDataTypeRef).isConst())
            return true;

        return SemaCheck::isConstAssignmentTarget(sema, objectView.nodeRef(), objectView);
    }

    Result semaIntrinsicMakeInterface(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView objectView = sema.viewType(children[0]);
        SemaNodeView       typeView   = sema.viewTypeConstant(children[1]);
        SemaNodeView       itfView    = sema.viewTypeConstant(children[2]);

        SWC_RESULT(SemaCheck::isValue(sema, objectView.nodeRef()));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, typeView));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, itfView));

        if (!isTypeInfoOperand(sema, typeView))
            return SemaError::raiseRequestedTypeFam(sema, typeView.nodeRef(), typeView.typeRef(), sema.typeMgr().typeTypeInfo());
        if (!isTypeInfoOperand(sema, itfView))
            return SemaError::raiseRequestedTypeFam(sema, itfView.nodeRef(), itfView.typeRef(), sema.typeMgr().typeTypeInfo());

        const TypeRef interfaceTypeValueRef = SemaHelpers::resolveRepresentedTypeRef(sema, itfView);
        const TypeRef interfaceTypeRef      = interfaceTypeValueRef.isValid() ? sema.typeMgr().get(interfaceTypeValueRef).unwrapAliasEnum(sema.ctx(), interfaceTypeValueRef) : TypeRef::invalid();
        if (!interfaceTypeRef.isValid() || !sema.typeMgr().get(interfaceTypeRef).isInterface())
            return SemaError::raise(sema, DiagnosticId::sema_err_not_type, itfView.nodeRef());

        const TypeRef objectTypeValueRef = SemaHelpers::resolveRepresentedTypeRef(sema, typeView);
        const TypeRef objectTypeRef      = objectTypeValueRef.isValid() ? sema.typeMgr().get(objectTypeValueRef).unwrapAliasEnum(sema.ctx(), objectTypeValueRef) : TypeRef::invalid();
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

        TypeRef resultTypeRef = interfaceTypeRef;
        if (makeInterfaceObjectIsConst(sema, objectView))
        {
            auto* interfaceSym = &sema.typeMgr().get(interfaceTypeRef).payloadSymInterface();
            resultTypeRef      = sema.typeMgr().addType(TypeInfo::makeInterface(interfaceSym, TypeInfoFlagsE::Const));
        }

        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsValue(node);

        if (sema.isCurrentFunction())
        {
            const TypeRef storageTypeRef = intrinsicMakeInterfaceRuntimeStorageTypeRef(sema, objectView.typeRef(), resultTypeRef);
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

        if (!isTypeInfoOperand(sema, toTypeView))
            return SemaError::raiseRequestedTypeFam(sema, toTypeView.nodeRef(), toTypeView.typeRef(), sema.typeMgr().typeTypeInfo());
        if (!isTypeInfoOperand(sema, fromTypeView))
            return SemaError::raiseRequestedTypeFam(sema, fromTypeView.nodeRef(), fromTypeView.typeRef(), sema.typeMgr().typeTypeInfo());

        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
        sema.setIsValue(node);
        return SemaHelpers::attachRuntimeIsFunctionToNode(sema, sema.curNodeRef(), node.codeRef());
    }

    Result semaIntrinsicAs(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SemaNodeView toTypeView   = sema.viewTypeConstant(children[0]);
        SemaNodeView fromTypeView = sema.viewTypeConstant(children[1]);
        const auto   ptrView      = sema.viewType(children[2]);

        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, toTypeView));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, fromTypeView));
        SWC_RESULT(SemaCheck::isValue(sema, ptrView.nodeRef()));

        if (!isTypeInfoOperand(sema, toTypeView))
            return SemaError::raiseRequestedTypeFam(sema, toTypeView.nodeRef(), toTypeView.typeRef(), sema.typeMgr().typeTypeInfo());
        if (!isTypeInfoOperand(sema, fromTypeView))
            return SemaError::raiseRequestedTypeFam(sema, fromTypeView.nodeRef(), fromTypeView.typeRef(), sema.typeMgr().typeTypeInfo());

        if (!ptrView.type())
            return SemaError::raiseRequestedTypeFam(sema, ptrView.nodeRef(), ptrView.typeRef(), sema.typeMgr().typeValuePtrVoid());

        const TypeRef   ptrTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), ptrView.typeRef());
        const TypeInfo& ptrType    = sema.typeMgr().get(ptrTypeRef);
        if (!ptrType.isPointerOrReference())
            return SemaError::raiseRequestedTypeFam(sema, ptrView.nodeRef(), ptrView.typeRef(), sema.typeMgr().typeValuePtrVoid());

        const TypeRef resultTypeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(sema.typeMgr().typeVoid(), TypeInfoFlagsE::Nullable));
        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsValue(node);
        return SemaHelpers::attachRuntimeAsFunctionToNode(sema, sema.curNodeRef(), node.codeRef());
    }

    Result semaIntrinsicTableOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SemaNodeView objectTypeView    = sema.viewTypeConstant(children[0]);
        SemaNodeView interfaceTypeView = sema.viewTypeConstant(children[1]);

        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, objectTypeView));
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, interfaceTypeView));

        if (!isTypeInfoOperand(sema, objectTypeView))
            return SemaError::raiseRequestedTypeFam(sema, objectTypeView.nodeRef(), objectTypeView.typeRef(), sema.typeMgr().typeTypeInfo());
        if (!isTypeInfoOperand(sema, interfaceTypeView))
            return SemaError::raiseRequestedTypeFam(sema, interfaceTypeView.nodeRef(), interfaceTypeView.typeRef(), sema.typeMgr().typeTypeInfo());

        sema.setType(sema.curNodeRef(), sema.typeMgr().typeValuePtrVoid());
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
        case TokenId::IntrinsicMakeInterface:
            return semaIntrinsicMakeInterface(sema, *this, children);
        case TokenId::IntrinsicIs:
            return semaIntrinsicIs(sema, *this, children);
        case TokenId::IntrinsicAs:
            return semaIntrinsicAs(sema, *this, children);
        case TokenId::IntrinsicTableOf:
            return semaIntrinsicTableOf(sema, *this, children);

        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicCVaArg:
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
