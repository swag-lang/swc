#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/Ast/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Match/MatchContext.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result checkIndex(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeArgView, int64_t& constIndex, bool& hasConstIndex)
    {
        if (!nodeArgView.type->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeArgRef);
            diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (nodeArgView.cst)
        {
            const auto& idxInt = nodeArgView.cst->getInt();
            if (!idxInt.fits64())
            {
                return SemaError::raise(sema, DiagnosticId::sema_err_index_too_large, nodeArgRef);
            }

            hasConstIndex = true;
            constIndex    = idxInt.asI64();
        }

        return Result::Continue;
    }

    Result checkIndexValue(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeExprView, int64_t constIndex, bool hasConstIndex)
    {
        if (!hasConstIndex)
            return Result::Continue;

        if (constIndex < 0)
        {
            if (nodeExprView.type->isArray() || nodeExprView.type->isSlice() || nodeExprView.type->isAnyString())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_negative, nodeArgRef);
                diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        return Result::Continue;
    }

    Result constantFold(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeExprView, int64_t constIndex, bool hasConstIndex)
    {
        if (!hasConstIndex || !nodeExprView.cst)
            return Result::Continue;

        if (nodeExprView.cst->isAggregateArray())
        {
            const auto& values = nodeExprView.cst->getAggregateArray();
            if (std::cmp_greater_equal(constIndex, values.size()))
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_out_of_range, nodeArgRef);
                diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
                diag.addArgument(Diagnostic::ARG_COUNT, values.size());
                diag.report(sema.ctx());
                return Result::Error;
            }
            sema.setConstant(sema.curNodeRef(), values[constIndex]);
        }
        else if (nodeExprView.cst->isString() || nodeExprView.cst->isSlice())
        {
            // If it's a slice, it's only constant foldable if it's actually a string
            if (nodeExprView.cst->isSlice() && !nodeExprView.type->isAnyString())
                return Result::Continue;

            const std::string_view s = nodeExprView.cst->getString();
            if (std::cmp_greater_equal(constIndex, s.size()))
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_out_of_range, nodeArgRef);
                diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
                diag.addArgument(Diagnostic::ARG_COUNT, s.size());
                diag.report(sema.ctx());
                return Result::Error;
            }

            const uint8_t       ch  = static_cast<uint8_t>(s[constIndex]);
            const ApsInt        v(static_cast<uint64_t>(ch), 8);
            const ConstantValue cst = ConstantValue::makeInt(sema.ctx(), v, 8, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), cst));
        }

        return Result::Continue;
    }
}

Result AstIndexExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView(sema, nodeExprRef);
    const SemaNodeView nodeArgView(sema, nodeArgRef);

    int64_t constIndex    = 0;
    bool    hasConstIndex = false;
    RESULT_VERIFY(checkIndex(sema, nodeArgRef, nodeArgView, constIndex, hasConstIndex));
    RESULT_VERIFY(checkIndexValue(sema, nodeArgRef, nodeExprView, constIndex, hasConstIndex));

    if (nodeExprView.type->isArray())
    {
        const auto& arrayDims   = nodeExprView.type->payloadArrayDims();
        const auto  numExpected = arrayDims.size();
        if (numExpected > 1)
        {
            std::vector<int64_t> dims;
            for (size_t i = 1; i < numExpected; i++)
                dims.push_back(arrayDims[i]);
            const auto typeArray = TypeInfo::makeArray(dims, nodeExprView.type->payloadArrayElemTypeRef(), nodeExprView.type->flags());
            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(typeArray));
        }
        else
        {
            sema.setType(sema.curNodeRef(), nodeExprView.type->payloadArrayElemTypeRef());
        }

        if (SemaInfo::isLValue(sema.node(nodeExprView.nodeRef)))
            SemaInfo::setIsLValue(*this);
    }
    else if (nodeExprView.type->isBlockPointer())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type->payloadTypeRef());
        SemaInfo::setIsLValue(*this);
    }
    else if (nodeExprView.type->isSlice())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type->payloadTypeRef());
        SemaInfo::setIsLValue(*this);
    }
    else if (nodeExprView.type->isString() || nodeExprView.type->isCString())
    {
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeU8());
        SemaInfo::setIsLValue(*this);
    }
    else if (nodeExprView.type->isValuePointer())
    {
        return SemaError::raisePointerArithmeticValuePointer(sema, sema.node(nodeExprRef), nodeExprRef, nodeExprView.typeRef);
    }
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef);
    }

    RESULT_VERIFY(constantFold(sema, nodeArgRef, nodeExprView, constIndex, hasConstIndex));

    SemaInfo::setIsValue(*this);
    return Result::Continue;
}

Result AstIndexListExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    SmallVector<AstNodeRef> children;
    sema.ast().nodes(children, spanChildrenRef);

    // Array
    if (nodeExprView.type->isArray())
    {
        const auto&    arrayDims   = nodeExprView.type->payloadArrayDims();
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

        bool                             allConstant = nodeExprView.cst != nullptr;
        std::vector<int64_t>             constIndexes;
        const std::vector<ConstantRef>* curValues = allConstant ? &nodeExprView.cst->getAggregateArray() : nullptr;

        for (size_t i = 0; i < numGot; i++)
        {
            const auto         nodeRef = children[i];
            const SemaNodeView nodeArgView(sema, nodeRef);

            int64_t constIndex    = 0;
            bool    hasConstIndex = false;
            RESULT_VERIFY(checkIndex(sema, nodeRef, nodeArgView, constIndex, hasConstIndex));
            RESULT_VERIFY(checkIndexValue(sema, nodeRef, nodeExprView, constIndex, hasConstIndex));

            if (hasConstIndex)
            {
                constIndexes.push_back(constIndex);
                if (allConstant)
                {
                    if (std::cmp_greater_equal(constIndex, curValues->size()))
                    {
                        auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_out_of_range, nodeRef);
                        diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
                        diag.addArgument(Diagnostic::ARG_COUNT, curValues->size());
                        diag.report(sema.ctx());
                        return Result::Error;
                    }

                    const auto& nextCst = sema.cstMgr().get((*curValues)[constIndex]);
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
            std::vector<int64_t> dims;
            for (size_t i = numGot; i < numExpected; i++)
                dims.push_back(arrayDims[i]);
            const auto typeArray = TypeInfo::makeArray(dims, nodeExprView.type->payloadArrayElemTypeRef(), nodeExprView.type->flags());
            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(typeArray));
        }
        else
        {
            sema.setType(sema.curNodeRef(), nodeExprView.type->payloadArrayElemTypeRef());
        }

        if (SemaInfo::isLValue(sema.node(nodeExprRef)))
            SemaInfo::setIsLValue(*this);
    }

    // Slice
    else if (nodeExprView.type->isSlice())
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
            const SemaNodeView nodeArgView(sema, children[0]);
            int64_t            constIndex    = 0;
            bool               hasConstIndex = false;
            RESULT_VERIFY(checkIndex(sema, children[0], nodeArgView, constIndex, hasConstIndex));
            RESULT_VERIFY(checkIndexValue(sema, children[0], nodeExprView, constIndex, hasConstIndex));
        }

        sema.setType(sema.curNodeRef(), nodeExprView.type->payloadArrayElemTypeRef());
        if (SemaInfo::isLValue(sema.node(nodeExprRef)))
            SemaInfo::setIsLValue(*this);
    }
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef);
    }

    SemaInfo::setIsValue(*this);
    return Result::Continue;
}

SWC_END_NAMESPACE();
