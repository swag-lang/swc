#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Index.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result resolveIndexOperandTypeRef(Sema& sema, TypeRef& outTypeRef, AstNodeRef nodeArgRef, const SemaNodeView& nodeArgView)
    {
        outTypeRef                 = nodeArgView.typeRef();
        const TypeRef aliasTypeRef = nodeArgView.type()->unwrap(sema.ctx(), nodeArgView.typeRef(), TypeExpandE::Alias);
        if (aliasTypeRef.isValid())
            outTypeRef = aliasTypeRef;

        const TypeInfo& indexType = sema.typeMgr().get(outTypeRef);
        if (indexType.isEnum())
        {
            SWC_RESULT(sema.waitSemaCompleted(&indexType, nodeArgRef));
            if (indexType.payloadSymEnum().attributes().hasRtFlag(RtAttributeFlagsE::EnumIndex))
                outTypeRef = indexType.payloadSymEnum().underlyingTypeRef();
        }

        return Result::Continue;
    }

    ConstantRef resolveIndexOperandConstantRef(const SemaNodeView& nodeArgView)
    {
        if (nodeArgView.cstRef().isInvalid())
            return ConstantRef::invalid();
        if (!nodeArgView.cst() || !nodeArgView.cst()->isEnumValue())
            return nodeArgView.cstRef();
        return nodeArgView.cst()->getEnumValue();
    }

    TypeRef resolveIndexedExprTypeRef(Sema& sema, const SemaNodeView& indexedView)
    {
        return SemaHelpers::unwrapAliasRefType(sema.ctx(), indexedView.typeRef());
    }

    Result setupIndexBoundCheck(Sema& sema, AstNodeRef nodeRef, const TypeInfo& indexedType, const SourceCodeRef& codeRef)
    {
        if (!indexedType.isIndexable())
            return Result::Continue;
        return SemaHelpers::setupRuntimeSafetyPanic(sema, nodeRef, Runtime::SafetyWhat::BoundCheck, codeRef);
    }

    uint32_t resolveMaxSequentialIndexCount(Sema& sema, TypeRef indexedTypeRef)
    {
        uint32_t count          = 0;
        TypeRef  currentTypeRef = indexedTypeRef;
        while (currentTypeRef.isValid())
        {
            const TypeInfo& currentType = sema.typeMgr().get(currentTypeRef);
            if (currentType.isArray())
            {
                count += static_cast<uint32_t>(currentType.payloadArrayDims().size());
                currentTypeRef = currentType.payloadArrayElemTypeRef();
                continue;
            }

            if (currentType.isSlice())
            {
                count++;
                currentTypeRef = currentType.payloadTypeRef();
                continue;
            }

            if (currentType.isVariadic())
            {
                count++;
                currentTypeRef = sema.typeMgr().typeAny();
                continue;
            }

            if (currentType.isTypedVariadic())
            {
                count++;
                currentTypeRef = currentType.payloadTypeRef();
                continue;
            }

            if (currentType.isString() || currentType.isCString())
            {
                count++;
                currentTypeRef = sema.typeMgr().typeU8();
                continue;
            }

            if (currentType.isBlockPointer())
            {
                count++;
                currentTypeRef = currentType.payloadTypeRef();
                continue;
            }

            break;
        }

        return count;
    }

    Result checkIndex(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeArgView, int64_t& constIndex, bool& hasConstIndex)
    {
        TypeRef indexTypeRef;
        SWC_RESULT(resolveIndexOperandTypeRef(sema, indexTypeRef, nodeArgRef, nodeArgView));
        const TypeInfo* indexType = &sema.typeMgr().get(indexTypeRef);
        if (indexType->isReference())
            indexType = &sema.typeMgr().get(indexType->payloadTypeRef());

        if (!indexType->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_not_int, nodeArgRef);
            diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (nodeArgView.cst())
        {
            const ConstantRef resolvedCstRef = resolveIndexOperandConstantRef(nodeArgView);
            SWC_ASSERT(resolvedCstRef.isValid());
            const auto& idxInt = sema.cstMgr().get(resolvedCstRef).getInt();
            if (!idxInt.fits64())
            {
                return SemaError::raise(sema, DiagnosticId::sema_err_index_too_large, nodeArgRef);
            }

            if (idxInt.isUnsigned() && idxInt.as64() > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()))
                constIndex = std::numeric_limits<int64_t>::max();
            else
                constIndex = idxInt.asI64();

            if (indexType->isIntSigned() && idxInt.isNegative())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_negative, nodeArgRef);
                diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
                diag.report(sema.ctx());
                return Result::Error;
            }

            hasConstIndex = true;
        }

        return Result::Continue;
    }

    Result checkSliceBound(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeArgView, int64_t& constIndex, bool& hasConstIndex)
    {
        if (nodeArgRef.isInvalid())
            return Result::Continue;
        return checkIndex(sema, nodeArgRef, nodeArgView, constIndex, hasConstIndex);
    }

    bool hasVoidPointerPayload(Sema& sema, const TypeInfo& pointerType)
    {
        if (!pointerType.isAnyPointer())
            return false;

        const TypeRef payloadTypeRef = pointerType.payloadTypeRef();
        if (payloadTypeRef == sema.typeMgr().typeVoid())
            return true;

        const TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), payloadTypeRef);
        return unwrappedTypeRef == sema.typeMgr().typeVoid();
    }

    Result checkVoidPointerIndex(Sema& sema, AstNodeRef atNodeRef, AstNodeRef indexedNodeRef, const SemaNodeView& indexedView, const TypeInfo& indexedType)
    {
        if (hasVoidPointerPayload(sema, indexedType))
            return SemaError::raisePointerArithmeticVoidPointer(sema, atNodeRef, indexedNodeRef, indexedView.typeRef());
        return Result::Continue;
    }

    TypeRef sliceResultTypeRef(Sema& sema, const SemaNodeView& indexedView)
    {
        const TypeRef   indexedTypeRef = resolveIndexedExprTypeRef(sema, indexedView);
        const TypeInfo& indexedType    = sema.typeMgr().get(indexedTypeRef);

        if (indexedType.isArray())
        {
            const TypeInfoFlags flags = indexedType.flags();
            return sema.typeMgr().addType(TypeInfo::makeSlice(indexedType.payloadArrayElemTypeRef(), flags));
        }

        if (indexedType.isSlice())
            return indexedTypeRef;
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

    Result indexRuntimeStorageTypeRef(TypeRef& outRuntimeStorageTypeRef, Sema& sema, const SemaNodeView& indexedView, AstNodeRef indexedRef);

    Result completeSliceRuntimeStorage(Sema& sema, TypeRef storageTypeRef)
    {
        if (sema.isGlobalScope())
            return Result::Continue;
        return SemaHelpers::attachRuntimeStorageIfNeeded(sema, sema.node(sema.curNodeRef()), storageTypeRef, "__index_runtime_storage");
    }

    Result completeIndexedValueRuntimeStorage(Sema& sema, AstNodeRef indexedRef, const SemaNodeView& indexedView)
    {
        if (!sema.isCurrentFunction())
            return Result::Continue;

        TypeRef storageTypeRef = TypeRef::invalid();
        SWC_RESULT(indexRuntimeStorageTypeRef(storageTypeRef, sema, indexedView, indexedRef));
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        return SemaHelpers::attachRuntimeStorageIfNeeded(sema, indexedRef, sema.node(indexedRef), storageTypeRef, "__index_runtime_storage");
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

        const TypeRef   indexedTypeRef = resolveIndexedExprTypeRef(sema, nodeExprView);
        const TypeInfo& indexedType    = sema.typeMgr().get(indexedTypeRef);
        SWC_RESULT(checkVoidPointerIndex(sema, sema.curNodeRef(), node.nodeExprRef, nodeExprView, indexedType));
        const TypeRef resultTypeRef = sliceResultTypeRef(sema, nodeExprView);
        if (!resultTypeRef.isValid())
            return SemaError::raiseTypeNotIndexable(sema, node.nodeExprRef, nodeExprView.typeRef());

        if (!range.nodeExprUpRef.isValid() && indexedType.isAnyPointer())
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

        auto* slicePayload          = sema.compiler().allocate<SliceIndexSemaPayload>();
        slicePayload->lowerBoundRef = range.nodeExprDownRef;
        slicePayload->upperBoundRef = range.nodeExprUpRef;
        slicePayload->inclusive     = range.hasFlag(AstRangeExprFlagsE::Inclusive);
        sema.setSemaPayload(sema.curNodeRef(), slicePayload);

        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsValue(sema.node(sema.curNodeRef()));
        SWC_RESULT(completeIndexedValueRuntimeStorage(sema, node.nodeExprRef, nodeExprView));
        SWC_RESULT(completeSliceRuntimeStorage(sema, sliceRuntimeStorageTypeRef(sema, resultTypeRef, ConstantRef::invalid())));
        return Result::Continue;
    }

    Result indexRuntimeStorageTypeRef(TypeRef& outRuntimeStorageTypeRef, Sema& sema, const SemaNodeView& indexedView, AstNodeRef indexedRef)
    {
        outRuntimeStorageTypeRef = TypeRef::invalid();
        if (!indexedView.type())
            return Result::Continue;

        const TypeRef   indexedTypeRef = resolveIndexedExprTypeRef(sema, indexedView);
        const TypeInfo& indexedType    = sema.typeMgr().get(indexedTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&indexedType, indexedRef));
        if (!indexedType.isArray())
            return Result::Continue;
        if (indexedView.hasConstant())
            return Result::Continue;

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
            return Result::Continue;

        const uint64_t valueSize = indexedType.sizeOf(sema.ctx());
        if (valueSize != 1 && valueSize != 2 && valueSize != 4 && valueSize != 8)
            return Result::Continue;

        SmallVector<uint64_t> dims;
        dims.push_back(8);
        outRuntimeStorageTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), sema.typeMgr().typeU8()));
        return Result::Continue;
    }
}

Result AstIndexExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView   = sema.viewTypeConstant(nodeExprRef);
    const SemaNodeView nodeArgView    = sema.viewTypeConstant(nodeArgRef);
    const TypeRef      indexedTypeRef = resolveIndexedExprTypeRef(sema, nodeExprView);
    const TypeInfo&    indexedType    = sema.typeMgr().get(indexedTypeRef);

    if (sema.node(nodeArgRef).is(AstNodeId::RangeExpr))
    {
        bool handled = false;
        SWC_RESULT(SemaSpecOp::tryResolveSlice(sema, *this, nodeExprView, handled));
        if (handled)
            return Result::Continue;
        return semaSliceIndex(sema, *this, nodeExprView);
    }

    bool handled = false;
    SWC_RESULT(SemaSpecOp::tryResolveIndex(sema, *this, nodeExprView, handled));
    if (handled)
        return Result::Continue;

    int64_t constIndex    = 0;
    bool    hasConstIndex = false;
    SWC_RESULT(checkIndex(sema, nodeArgRef, nodeArgView, constIndex, hasConstIndex));

    if (indexedType.isAggregateArray())
    {
        if (!hasConstIndex)
            return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef());

        const auto& elemTypes = indexedType.payloadAggregate().types;
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

    if (indexedType.isArray())
    {
        const auto&    arrayDims   = indexedType.payloadArrayDims();
        const uint64_t numExpected = arrayDims.size();
        if (numExpected > 1)
        {
            SmallVector4<uint64_t> dims;
            for (size_t i = 1; i < numExpected; i++)
                dims.push_back(arrayDims[i]);
            const auto typeArray = TypeInfo::makeArray(dims, indexedType.payloadArrayElemTypeRef(), indexedType.flags());
            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(typeArray));
        }
        else
        {
            sema.setType(sema.curNodeRef(), indexedType.payloadArrayElemTypeRef());
        }
    }
    else if (indexedType.isBlockPointer())
    {
        SWC_RESULT(checkVoidPointerIndex(sema, sema.curNodeRef(), nodeExprRef, nodeExprView, indexedType));
        sema.setType(sema.curNodeRef(), indexedType.payloadTypeRef());
    }
    else if (indexedType.isSlice())
    {
        sema.setType(sema.curNodeRef(), indexedType.payloadTypeRef());
    }
    else if (indexedType.isVariadic())
    {
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeAny());
    }
    else if (indexedType.isTypedVariadic())
    {
        sema.setType(sema.curNodeRef(), indexedType.payloadTypeRef());
    }
    else if (indexedType.isString() || indexedType.isCString())
    {
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeU8());
    }
    else if (indexedType.isValuePointer())
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

    SWC_RESULT(setupIndexBoundCheck(sema, sema.curNodeRef(), indexedType, codeRef()));

    TypeRef runtimeStorageTypeRef = TypeRef::invalid();
    SWC_RESULT(indexRuntimeStorageTypeRef(runtimeStorageTypeRef, sema, nodeExprView, nodeExprRef));
    if (runtimeStorageTypeRef.isValid() && sema.isCurrentFunction())
        SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, *this, runtimeStorageTypeRef, "__index_runtime_storage"));

    return Result::Continue;
}

Result AstIndexListExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewTypeConstant(nodeExprRef);

    bool handled = false;
    SWC_RESULT(SemaSpecOp::tryResolveIndex(sema, *this, nodeExprView, handled));
    if (handled)
        return Result::Continue;

    const TypeRef   indexedTypeRef = resolveIndexedExprTypeRef(sema, nodeExprView);
    const TypeInfo& indexedType    = sema.typeMgr().get(indexedTypeRef);

    SmallVector<AstNodeRef> children;
    sema.ast().appendNodes(children, spanChildrenRef);

    if (indexedType.isArray() || indexedType.isSlice() || indexedType.isAnyVariadic())
    {
        const uint32_t maxIndexCount = resolveMaxSequentialIndexCount(sema, indexedTypeRef);
        if (children.size() > maxIndexCount)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_num_dims, children[maxIndexCount]);
            diag.addArgument(Diagnostic::ARG_COUNT, maxIndexCount);
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(children.size()));
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    if (indexedType.isArray() || indexedType.isAggregateArray() || indexedType.isSlice() || indexedType.isAnyVariadic() || indexedType.isCString() || indexedType.isString() || indexedType.isBlockPointer() || indexedType.isTypedVariadic())
    {
        TypeRef     currentTypeRef  = indexedTypeRef;
        ConstantRef currentCstRef   = nodeExprView.cstRef();
        bool        currentIsLValue = sema.isLValue(nodeExprRef);

        for (const AstNodeRef nodeRef : children)
        {
            const SemaNodeView nodeArgView = sema.viewTypeConstant(nodeRef);

            int64_t constIndex    = 0;
            bool    hasConstIndex = false;
            SWC_RESULT(checkIndex(sema, nodeRef, nodeArgView, constIndex, hasConstIndex));

            const TypeInfo& currentType = sema.typeMgr().get(currentTypeRef);
            if (currentType.isAggregateArray())
            {
                if (!hasConstIndex)
                    return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef());

                const auto& elemTypes = currentType.payloadAggregate().types;
                if (std::cmp_greater_equal(constIndex, elemTypes.size()))
                    return SemaError::raiseIndexOutOfRange(sema, nodeRef, constIndex, elemTypes.size());

                if (currentCstRef.isValid())
                {
                    ConstantRef nextCstRef = ConstantRef::invalid();
                    SWC_RESULT(ConstantExtract::atIndexRef(sema, sema.cstMgr().get(currentCstRef), constIndex, nodeRef, nextCstRef));
                    currentCstRef = nextCstRef;
                }

                currentTypeRef  = elemTypes[constIndex];
                currentIsLValue = false;
                continue;
            }

            if (currentType.isArray())
            {
                if (currentCstRef.isValid() && hasConstIndex)
                {
                    ConstantRef nextCstRef = ConstantRef::invalid();
                    SWC_RESULT(ConstantExtract::atIndexRef(sema, sema.cstMgr().get(currentCstRef), constIndex, nodeRef, nextCstRef));
                    currentCstRef = nextCstRef;
                }
                else
                {
                    currentCstRef = ConstantRef::invalid();
                }

                const auto& arrayDims = currentType.payloadArrayDims();
                if (arrayDims.size() > 1)
                {
                    SmallVector4<uint64_t> dims;
                    for (size_t i = 1; i < arrayDims.size(); i++)
                        dims.push_back(arrayDims[i]);
                    const auto typeArray = TypeInfo::makeArray(dims, currentType.payloadArrayElemTypeRef(), currentType.flags());
                    currentTypeRef       = sema.typeMgr().addType(typeArray);
                }
                else
                {
                    currentTypeRef = currentType.payloadArrayElemTypeRef();
                }

                if (currentCstRef.isValid())
                    currentIsLValue = false;
                continue;
            }

            if (currentType.isBlockPointer())
            {
                SWC_RESULT(checkVoidPointerIndex(sema, sema.curNodeRef(), nodeExprRef, nodeExprView, currentType));
                currentTypeRef  = currentType.payloadTypeRef();
                currentCstRef   = ConstantRef::invalid();
                currentIsLValue = true;
                continue;
            }

            if (currentType.isSlice())
            {
                currentTypeRef = currentType.payloadTypeRef();
                currentCstRef  = ConstantRef::invalid();
                continue;
            }

            if (currentType.isVariadic())
            {
                currentTypeRef = sema.typeMgr().typeAny();
                currentCstRef  = ConstantRef::invalid();
                continue;
            }

            if (currentType.isTypedVariadic())
            {
                currentTypeRef = currentType.payloadTypeRef();
                currentCstRef  = ConstantRef::invalid();
                continue;
            }

            if (currentType.isString() || currentType.isCString())
            {
                currentTypeRef = sema.typeMgr().typeU8();
                currentCstRef  = ConstantRef::invalid();
                continue;
            }

            return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef());
        }

        sema.setType(sema.curNodeRef(), currentTypeRef);
        sema.setIsValue(*this);
        if (currentCstRef.isValid())
            sema.setConstant(sema.curNodeRef(), currentCstRef);
        else if (currentIsLValue)
            sema.setIsLValue(*this);
    }
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef());
    }
    SWC_RESULT(setupIndexBoundCheck(sema, sema.curNodeRef(), indexedType, codeRef()));

    TypeRef runtimeStorageTypeRef = TypeRef::invalid();
    SWC_RESULT(indexRuntimeStorageTypeRef(runtimeStorageTypeRef, sema, nodeExprView, nodeExprRef));
    if (runtimeStorageTypeRef.isValid() && sema.isCurrentFunction())
        SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, *this, runtimeStorageTypeRef, "__index_runtime_storage"));

    return Result::Continue;
}

SWC_END_NAMESPACE();
