#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result          completeIndexRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    SymbolVariable& registerUniqueIndexRuntimeStorageSymbol(Sema& sema, const AstNode& node);

    Result checkIndex(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeArgView, int64_t& constIndex, bool& hasConstIndex)
    {
        if (!nodeArgView.type()->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_not_int, nodeArgRef);
            diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (nodeArgView.cst())
        {
            const auto& idxInt = nodeArgView.cst()->getInt();
            if (!idxInt.fits64())
            {
                return SemaError::raise(sema, DiagnosticId::sema_err_index_too_large, nodeArgRef);
            }

            if (nodeArgView.type()->isIntSigned() && idxInt.isNegative())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_negative, nodeArgRef);
                diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
                diag.report(sema.ctx());
                return Result::Error;
            }

            hasConstIndex = true;
            constIndex    = idxInt.asI64();
        }

        return Result::Continue;
    }

    Result checkSliceBound(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeArgView, int64_t& constIndex, bool& hasConstIndex)
    {
        if (nodeArgRef.isInvalid())
            return Result::Continue;
        return checkIndex(sema, nodeArgRef, nodeArgView, constIndex, hasConstIndex);
    }

    TypeRef sliceResultTypeRef(Sema& sema, const SemaNodeView& indexedView)
    {
        const TypeInfo& indexedType = *indexedView.type();

        if (indexedType.isArray())
        {
            const TypeInfoFlags flags = indexedType.flags();
            return sema.typeMgr().addType(TypeInfo::makeSlice(indexedType.payloadArrayElemTypeRef(), flags));
        }

        if (indexedType.isSlice())
            return indexedView.typeRef();
        if (indexedType.isString())
            return sema.typeMgr().typeString();
        if (indexedType.isCString())
            return sema.typeMgr().typeString();
        if (indexedType.isAnyPointer())
            return sema.typeMgr().addType(TypeInfo::makeSlice(indexedType.payloadTypeRef(), indexedType.flags()));

        return TypeRef::invalid();
    }

    TypeRef sliceRuntimeStorageTypeRef(Sema& sema, TypeRef resultTypeRef, ConstantRef resultConstRef)
    {
        if (!resultTypeRef.isValid() || resultConstRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& resultType = sema.typeMgr().get(resultTypeRef);
        if (resultType.isSlice() || resultType.isString())
            return resultTypeRef;

        return TypeRef::invalid();
    }

    Result completeSliceRuntimeStorage(Sema& sema, TypeRef storageTypeRef)
    {
        if (storageTypeRef.isInvalid() || SemaHelpers::isGlobalScope(sema))
            return Result::Continue;

        if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
        {
            auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
            if (!payload)
            {
                payload = sema.compiler().allocate<CodeGenNodePayload>();
                sema.setCodeGenPayload(sema.curNodeRef(), payload);
            }

            payload->runtimeStorageSym = boundStorage;
            return Result::Continue;
        }

        auto& storageSym = registerUniqueIndexRuntimeStorageSymbol(sema, sema.node(sema.curNodeRef()));
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT(Match::ghosting(sema, storageSym));
        SWC_RESULT(completeIndexRuntimeStorageSymbol(sema, storageSym, storageTypeRef));

        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeStorageSym = &storageSym;
        return Result::Continue;
    }

    Result semaSliceIndex(Sema& sema, const AstIndexExpr& node, const SemaNodeView& nodeExprView)
    {
        const auto&        range        = sema.node(node.nodeArgRef).cast<AstRangeExpr>();
        const SemaNodeView nodeDownView = sema.viewTypeConstant(range.nodeExprDownRef);
        const SemaNodeView nodeUpView   = sema.viewTypeConstant(range.nodeExprUpRef);
        int64_t            constDown    = 0;
        int64_t            constUp      = 0;
        bool               hasConstDown = false;
        bool               hasConstUp   = false;
        SWC_RESULT(checkSliceBound(sema, range.nodeExprDownRef, nodeDownView, constDown, hasConstDown));
        SWC_RESULT(checkSliceBound(sema, range.nodeExprUpRef, nodeUpView, constUp, hasConstUp));

        const TypeRef resultTypeRef = sliceResultTypeRef(sema, nodeExprView);
        if (!resultTypeRef.isValid())
            return SemaError::raiseTypeNotIndexable(sema, node.nodeExprRef, nodeExprView.typeRef());

        if (!range.nodeExprUpRef.isValid() && (nodeExprView.type()->isAnyPointer() || nodeExprView.type()->isCString()))
            return SemaError::raiseTypeNotIndexable(sema, node.nodeExprRef, nodeExprView.typeRef());

        if (hasConstDown && hasConstUp)
        {
            const bool ok = range.hasFlag(AstRangeExprFlagsE::Inclusive) ? constDown <= constUp : constDown < constUp;
            if (!ok)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_range_invalid_bounds, node.nodeArgRef);
                diag.addArgument(Diagnostic::ARG_LEFT, nodeDownView.cstRef());
                diag.addArgument(Diagnostic::ARG_RIGHT, nodeUpView.cstRef());
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsValue(sema.node(sema.curNodeRef()));
        SWC_RESULT(completeSliceRuntimeStorage(sema, sliceRuntimeStorageTypeRef(sema, resultTypeRef, ConstantRef::invalid())));
        return Result::Continue;
    }

    TypeRef indexRuntimeStorageTypeRef(Sema& sema, const SemaNodeView& indexedView, AstNodeRef indexedRef)
    {
        if (!indexedView.type() || !indexedView.type()->isArray())
            return TypeRef::invalid();
        if (indexedView.hasConstant())
            return TypeRef::invalid();

        bool needsRuntimeStorage = !sema.isLValue(indexedRef);
        if (!needsRuntimeStorage)
        {
            const SemaNodeView indexedSymbolView = sema.viewSymbol(indexedRef);
            if (indexedSymbolView.sym() && indexedSymbolView.sym()->isVariable())
            {
                const auto& symVar  = indexedSymbolView.sym()->cast<SymbolVariable>();
                needsRuntimeStorage = symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter);
            }
        }

        if (!needsRuntimeStorage)
            return TypeRef::invalid();

        const uint64_t valueSize = indexedView.type()->sizeOf(sema.ctx());
        if (valueSize != 1 && valueSize != 2 && valueSize != 4 && valueSize != 8)
            return TypeRef::invalid();

        SmallVector<uint64_t> dims;
        dims.push_back(8);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), sema.typeMgr().typeU8()));
    }

    Result completeIndexRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, symVar, typeRef));

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SymbolVariable& registerUniqueIndexRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        TaskContext&        ctx         = sema.ctx();
        const auto          privateName = Utf8("__index_runtime_storage");
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();

        auto* sym = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(sym);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, sym, true);
        }

        return *(sym);
    }
}

Result AstIndexExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewTypeConstant(nodeExprRef);
    const SemaNodeView nodeArgView  = sema.viewTypeConstant(nodeArgRef);

    if (sema.node(nodeArgRef).is(AstNodeId::RangeExpr))
        return semaSliceIndex(sema, *this, nodeExprView);

    int64_t constIndex    = 0;
    bool    hasConstIndex = false;
    SWC_RESULT(checkIndex(sema, nodeArgRef, nodeArgView, constIndex, hasConstIndex));

    if (nodeExprView.type()->isAggregateArray())
    {
        if (!hasConstIndex)
            return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef());

        const auto& elemTypes = nodeExprView.type()->payloadAggregate().types;
        if (std::cmp_greater_equal(constIndex, elemTypes.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, elemTypes.size());

        sema.setType(sema.curNodeRef(), elemTypes[constIndex]);
        sema.setIsValue(*this);

        if (nodeExprView.cst() && nodeExprView.cst()->isAggregateArray())
        {
            const auto& values = nodeExprView.cst()->getAggregateArray();
            if (std::cmp_greater_equal(constIndex, values.size()))
                return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, values.size());
            sema.setConstant(sema.curNodeRef(), values[constIndex]);
        }

        return Result::Continue;
    }

    if (nodeExprView.type()->isArray())
    {
        const auto&    arrayDims   = nodeExprView.type()->payloadArrayDims();
        const uint64_t numExpected = arrayDims.size();
        if (numExpected > 1)
        {
            SmallVector4<uint64_t> dims;
            for (size_t i = 1; i < numExpected; i++)
                dims.push_back(arrayDims[i]);
            const auto typeArray = TypeInfo::makeArray(dims, nodeExprView.type()->payloadArrayElemTypeRef(), nodeExprView.type()->flags());
            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(typeArray));
        }
        else
        {
            sema.setType(sema.curNodeRef(), nodeExprView.type()->payloadArrayElemTypeRef());
        }
    }
    else if (nodeExprView.type()->isBlockPointer())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type()->payloadTypeRef());
    }
    else if (nodeExprView.type()->isSlice())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type()->payloadTypeRef());
    }
    else if (nodeExprView.type()->isVariadic())
    {
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeAny());
    }
    else if (nodeExprView.type()->isTypedVariadic())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type()->payloadTypeRef());
    }
    else if (nodeExprView.type()->isString() || nodeExprView.type()->isCString())
    {
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeU8());
    }
    else if (nodeExprView.type()->isValuePointer())
    {
        return SemaError::raisePointerArithmeticValuePointer(sema, sema.curNodeRef(), nodeExprRef, nodeExprView.typeRef());
    }
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef());
    }

    sema.setIsValue(*this);

    // Constant extract
    if (nodeExprView.cst() && hasConstIndex)
    {
        SWC_RESULT(ConstantExtract::atIndex(sema, *nodeExprView.cst(), constIndex, nodeArgRef));
    }
    else
    {
        sema.setIsLValue(*this);
    }

    const TypeRef runtimeStorageTypeRef = indexRuntimeStorageTypeRef(sema, nodeExprView, nodeExprRef);
    if (runtimeStorageTypeRef.isValid() && SemaHelpers::isCurrentFunction(sema))
    {
        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
        {
            payload->runtimeStorageSym = boundStorage;
        }
        else
        {
            auto& storageSym = registerUniqueIndexRuntimeStorageSymbol(sema, *this);
            storageSym.registerAttributes(sema);
            storageSym.setDeclared(sema.ctx());
            SWC_RESULT(Match::ghosting(sema, storageSym));
            SWC_RESULT(completeIndexRuntimeStorageSymbol(sema, storageSym, runtimeStorageTypeRef));
            payload->runtimeStorageSym = &storageSym;
        }
    }

    return Result::Continue;
}

Result AstIndexListExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewTypeConstant(nodeExprRef);

    SmallVector<AstNodeRef> children;
    sema.ast().appendNodes(children, spanChildrenRef);

    if (nodeExprView.type()->isArray())
    {
        const auto&    arrayDims   = nodeExprView.type()->payloadArrayDims();
        const uint64_t numExpected = arrayDims.size();
        const size_t   numGot      = children.size();

        if (numGot > numExpected)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_num_dims, children[numExpected]);
            diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(numExpected));
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(numGot));
            diag.report(sema.ctx());
            return Result::Error;
        }

        bool                            allConstant = nodeExprView.cst() != nullptr;
        SmallVector<int64_t>            constIndexes;
        const std::vector<ConstantRef>* curValues = allConstant ? &nodeExprView.cst()->getAggregateArray() : nullptr;

        for (size_t i = 0; i < numGot; i++)
        {
            const auto         nodeRef     = children[i];
            const SemaNodeView nodeArgView = sema.viewTypeConstant(nodeRef);

            int64_t constIndex    = 0;
            bool    hasConstIndex = false;
            SWC_RESULT(checkIndex(sema, nodeRef, nodeArgView, constIndex, hasConstIndex));

            if (hasConstIndex)
            {
                constIndexes.push_back(constIndex);
                if (allConstant)
                {
                    if (std::cmp_greater_equal(constIndex, curValues->size()))
                        return SemaError::raiseIndexOutOfRange(sema, nodeRef, constIndex, curValues->size());

                    const ConstantValue& nextCst = sema.cstMgr().get((*curValues)[constIndex]);
                    if (i < numGot - 1)
                    {
                        if (nextCst.isAggregateArray())
                            curValues = &nextCst.getAggregateArray();
                        else
                            allConstant = false;
                    }
                    else
                    {
                        sema.setConstant(sema.curNodeRef(), (*curValues)[constIndex]);
                    }
                }
            }
            else
            {
                allConstant = false;
            }
        }

        if (numGot < numExpected)
        {
            SmallVector<uint64_t> dims;
            for (size_t i = numGot; i < numExpected; i++)
                dims.push_back(arrayDims[i]);
            const auto typeArray = TypeInfo::makeArray(dims, nodeExprView.type()->payloadArrayElemTypeRef(), nodeExprView.type()->flags());
            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(typeArray));
        }
        else
        {
            sema.setType(sema.curNodeRef(), nodeExprView.type()->payloadArrayElemTypeRef());
        }

        if (sema.isLValue(nodeExprRef))
            sema.setIsLValue(*this);
    }
    else if (nodeExprView.type()->isSlice() || nodeExprView.type()->isAnyVariadic())
    {
        const size_t numGot = children.size();
        if (numGot > 1)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_num_dims, children[1]);
            diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(1));
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(numGot));
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (numGot == 1)
        {
            const SemaNodeView nodeArgView   = sema.viewTypeConstant(children[0]);
            int64_t            constIndex    = 0;
            bool               hasConstIndex = false;
            SWC_RESULT(checkIndex(sema, children[0], nodeArgView, constIndex, hasConstIndex));
        }

        if (nodeExprView.type()->isVariadic())
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeAny());
        else
            sema.setType(sema.curNodeRef(), nodeExprView.type()->payloadTypeRef());
        if (sema.isLValue(nodeExprRef))
            sema.setIsLValue(*this);
    }
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef());
    }

    sema.setIsValue(*this);
    return Result::Continue;
}

SWC_END_NAMESPACE();
