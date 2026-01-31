#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/Ast/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Match/MatchContext.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

Result AstIndexExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView(sema, nodeExprRef);
    const SemaNodeView nodeArgView(sema, nodeArgRef);

    if (!nodeArgView.type->isInt())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeArgRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    // Validate constant index
    bool    hasConstIndex = false;
    int64_t constIndex    = 0;
    if (nodeArgView.cst)
    {
        const auto& idxInt = nodeArgView.cst->getInt();
        if (!idxInt.fits64())
        {
            return SemaError::raise(sema, DiagnosticId::sema_err_index_too_large, nodeArgRef);
        }

        hasConstIndex = true;
        constIndex    = idxInt.asI64();

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
    }

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

    // Constant folding
    if (nodeExprView.cst && hasConstIndex)
    {
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
        else if (nodeExprView.cst->isString())
        {
            const std::string_view s = nodeExprView.cst->getString();
            if (std::cmp_greater_equal(constIndex, s.size()))
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_out_of_range, nodeArgRef);
                diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
                diag.addArgument(Diagnostic::ARG_COUNT, s.size());
                diag.report(sema.ctx());
                return Result::Error;
            }

            const uint8_t       ch = static_cast<uint8_t>(s[constIndex]);
            const ApsInt        v(static_cast<uint64_t>(ch), 8);
            const ConstantValue cst = ConstantValue::makeInt(sema.ctx(), v, 8, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), cst));
        }
    }

    SemaInfo::setIsValue(*this);
    return Result::Continue;
}

Result AstIndexListExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    // Array
    if (nodeExprView.type->isArray())
    {
        SmallVector<AstNodeRef> children;
        sema.ast().nodes(children, spanChildrenRef);

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

        for (const AstNodeRef nodeRef : children)
        {
            const SemaNodeView nodeArgView(sema, nodeRef);
            if (!nodeArgView.type->isInt())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
                diag.report(sema.ctx());
                return Result::Error;
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
        SmallVector<AstNodeRef> children;
        sema.ast().nodes(children, spanChildrenRef);

        const size_t numGot = children.size();
        if (numGot > 1)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_num_dims, children[1]);
            diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(1));
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(numGot));
            diag.report(sema.ctx());
            return Result::Error;
        }

        for (const AstNodeRef nodeRef : children)
        {
            const SemaNodeView nodeArgView(sema, nodeRef);
            if (!nodeArgView.type->isInt())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
                diag.report(sema.ctx());
                return Result::Error;
            }
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
