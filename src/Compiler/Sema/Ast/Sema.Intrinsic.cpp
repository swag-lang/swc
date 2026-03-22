#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef currentLoopIndexTypeRef(Sema& sema)
    {
        const SemaFrame::BreakContext& breakContext = sema.frame().currentBreakContext();
        if (breakContext.kind != SemaFrame::BreakContextKind::Loop || breakContext.nodeRef.isInvalid())
            return TypeRef::invalid();

        const AstNode& breakNode = sema.node(breakContext.nodeRef);
        if (breakNode.is(AstNodeId::ForeachStmt))
            return sema.typeMgr().typeU64();

        if (breakNode.is(AstNodeId::ForStmt))
        {
            const auto&        forNode  = breakNode.cast<AstForStmt>();
            const SemaNodeView exprView = sema.viewType(forNode.nodeExprRef);
            return exprView.typeRef();
        }

        return TypeRef::invalid();
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
            const TypeRef indexTypeRef = currentLoopIndexTypeRef(sema);
            if (!indexTypeRef.isValid())
                return SemaError::raise(sema, DiagnosticId::sema_err_index_outside_loop, sema.curNodeRef());

            sema.setType(sema.curNodeRef(), indexTypeRef);
            return Result::Continue;
        }

        default:
            SWC_INTERNAL_ERROR();
    }
}

namespace
{
    SymbolVariable& registerUniqueIntrinsicRuntimeStorageSymbol(Sema& sema, const AstNode& node, const Utf8& privateName)
    {
        TaskContext&        ctx         = sema.ctx();
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();
        auto*               symVariable = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(symVariable);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, symVariable, true);
        }

        return *symVariable;
    }

    Result completeIntrinsicRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, symVar, typeRef));

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

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

        if (SemaHelpers::isCurrentFunction(sema))
        {
            auto& storageSym = registerUniqueIntrinsicRuntimeStorageSymbol(sema, node, Utf8("__intrinsic_runtime_storage"));
            storageSym.registerAttributes(sema);
            storageSym.setDeclared(sema.ctx());
            SWC_RESULT(Match::ghosting(sema, storageSym));
            SWC_RESULT(completeIntrinsicRuntimeStorageSymbol(sema, storageSym, typeRef));

            auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
            if (!payload)
            {
                payload = sema.compiler().allocate<CodeGenNodePayload>();
                sema.setCodeGenPayload(sema.curNodeRef(), payload);
            }

            payload->runtimeStorageSym = &storageSym;
        }

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

        if (SemaHelpers::isCurrentFunction(sema))
        {
            auto& storageSym = registerUniqueIntrinsicRuntimeStorageSymbol(sema, node, Utf8("__intrinsic_runtime_storage"));
            storageSym.registerAttributes(sema);
            storageSym.setDeclared(sema.ctx());
            SWC_RESULT(Match::ghosting(sema, storageSym));
            SWC_RESULT(completeIntrinsicRuntimeStorageSymbol(sema, storageSym, typeRef));

            auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
            if (!payload)
            {
                payload = sema.compiler().allocate<CodeGenNodePayload>();
                sema.setCodeGenPayload(sema.curNodeRef(), payload);
            }

            payload->runtimeStorageSym = &storageSym;
        }

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

        if (SemaHelpers::isCurrentFunction(sema))
        {
            const TypeRef storageTypeRef = intrinsicMakeInterfaceRuntimeStorageTypeRef(sema, objectView.typeRef(), interfaceTypeRef);
            auto&         storageSym     = registerUniqueIntrinsicRuntimeStorageSymbol(sema, node, Utf8("__intrinsic_runtime_storage"));
            storageSym.registerAttributes(sema);
            storageSym.setDeclared(sema.ctx());
            SWC_RESULT(Match::ghosting(sema, storageSym));
            SWC_RESULT(completeIntrinsicRuntimeStorageSymbol(sema, storageSym, storageTypeRef));

            auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
            if (!payload)
            {
                payload = sema.compiler().allocate<CodeGenNodePayload>();
                sema.setCodeGenPayload(sema.curNodeRef(), payload);
            }

            payload->runtimeStorageSym = &storageSym;
        }

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

        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicCVaArg:
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
