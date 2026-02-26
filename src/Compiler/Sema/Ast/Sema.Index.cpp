#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Index.Payload.h"
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

        if (SymbolFunction* currentFunc = sema.frame().currentFunction())
        {
            const TypeInfo& symType = sema.typeMgr().get(typeRef);
            SWC_RESULT_VERIFY(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            currentFunc->addLocalVariable(sema.ctx(), &symVar);
        }

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SymbolVariable& registerUniqueIndexRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        TaskContext&        ctx         = sema.ctx();
        const Utf8          privateName = Utf8("__index_runtime_storage");
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

        return *SWC_NOT_NULL(sym);
    }
}

Result AstIndexExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewTypeConstant(nodeExprRef);
    const SemaNodeView nodeArgView  = sema.viewTypeConstant(nodeArgRef);

    int64_t constIndex    = 0;
    bool    hasConstIndex = false;
    SWC_RESULT_VERIFY(checkIndex(sema, nodeArgRef, nodeArgView, constIndex, hasConstIndex));

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
        SWC_RESULT_VERIFY(ConstantExtract::atIndex(sema, *nodeExprView.cst(), constIndex, nodeArgRef));
    }
    else
    {
        sema.setIsLValue(*this);
    }

    const TypeRef runtimeStorageTypeRef = indexRuntimeStorageTypeRef(sema, nodeExprView, nodeExprRef);
    if (runtimeStorageTypeRef.isValid() && sema.frame().currentFunction() != nullptr)
    {
        auto& storageSym = registerUniqueIndexRuntimeStorageSymbol(sema, *this);
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT_VERIFY(Match::ghosting(sema, storageSym));
        SWC_RESULT_VERIFY(completeIndexRuntimeStorageSymbol(sema, storageSym, runtimeStorageTypeRef));

        auto* payload = sema.codeGenPayload<IndexExprCodeGenPayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<IndexExprCodeGenPayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeStorageSym = &storageSym;
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
            SWC_RESULT_VERIFY(checkIndex(sema, nodeRef, nodeArgView, constIndex, hasConstIndex));

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
            SWC_RESULT_VERIFY(checkIndex(sema, children[0], nodeArgView, constIndex, hasConstIndex));
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
