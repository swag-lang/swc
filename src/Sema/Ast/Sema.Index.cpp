#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/Ast/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Match/MatchContext.h"
#include "Sema/Symbol/Symbol.Enum.h"
#include "Sema/Type/TypeManager.h"
#include "Runtime/Runtime.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result checkIndex(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeArgView, int64_t& constIndex, bool& hasConstIndex)
    {
        if (!nodeArgView.type->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_not_int, nodeArgRef);
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

            if (nodeArgView.type->isIntSigned() && idxInt.isNegative())
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

    Result constantFold(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeExprView, int64_t constIndex, bool hasConstIndex)
    {
        if (!hasConstIndex || !nodeExprView.cst)
            return Result::Continue;

        ////////////////////////////////////////////////////////
        if (nodeExprView.cst->isAggregateArray())
        {
            if (nodeExprView.type->payloadArrayDims().size() > 1)
                return Result::Continue;
            const auto& values = nodeExprView.cst->getAggregateArray();
            if (std::cmp_greater_equal(constIndex, values.size()))
                return SemaError::raiseIndexOutOfRange(sema, constIndex, values.size(), nodeArgRef);
            sema.setConstant(sema.curNodeRef(), values[constIndex]);
            return Result::Continue;
        }

        ////////////////////////////////////////////////////////
        if (nodeExprView.cst->isString())
        {
            const std::string_view s = nodeExprView.cst->getString();
            if (std::cmp_greater_equal(constIndex, s.size()))
                return SemaError::raiseIndexOutOfRange(sema, constIndex, s.size(), nodeArgRef);
            const ConstantValue cst = ConstantValue::makeIntSized(sema.ctx(), static_cast<uint8_t>(s[constIndex]));
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), cst));
            return Result::Continue;
        }

        ////////////////////////////////////////////////////////
        if (nodeExprView.cst->isSlice())
        {
            auto&          ctx        = sema.ctx();
            const TypeRef  elemTypeRef = nodeExprView.type->payloadTypeRef();
            const TypeInfo elemType    = sema.typeMgr().get(elemTypeRef);

            const uint64_t elemSize = elemType.sizeOf(ctx);
            if (!elemSize)
                return Result::Continue;

            const ByteSpan bytes      = nodeExprView.cst->getSlice();
            const uint64_t numEntries = bytes.size() / elemSize;
            if (std::cmp_greater_equal(constIndex, numEntries))
                return SemaError::raiseIndexOutOfRange(sema, constIndex, numEntries, nodeArgRef);

            const auto elemBytes = ByteSpan{bytes.data() + (constIndex * elemSize), elemSize};

            const TypeInfo* typeField = &elemType;
            if (typeField->isEnum())
                typeField = &sema.typeMgr().get(typeField->payloadSymEnum().underlyingTypeRef());

            ConstantValue cv;
            if (typeField->isStruct())
            {
                cv = ConstantValue::makeStruct(ctx, typeField->payloadTypeRef(), elemBytes);
            }
            else if (typeField->isBool())
            {
                cv = ConstantValue::makeBool(ctx, *reinterpret_cast<const bool*>(elemBytes.data()));
            }
            else if (typeField->isIntLike())
            {
                const ApsInt apsInt(reinterpret_cast<const char*>(elemBytes.data()), typeField->payloadIntLikeBits(), typeField->isIntUnsigned());
                cv = ConstantValue::makeFromIntLike(ctx, apsInt, *typeField);
            }
            else if (typeField->isFloat())
            {
                const ApFloat apFloat(reinterpret_cast<const char*>(elemBytes.data()), typeField->payloadFloatBits());
                cv = ConstantValue::makeFloat(ctx, apFloat, typeField->payloadFloatBits());
            }
            else if (typeField->isString())
            {
                const auto str = reinterpret_cast<const Runtime::String*>(elemBytes.data());
                cv             = ConstantValue::makeString(ctx, std::string_view(str->ptr, str->length));
            }
            else if (typeField->isValuePointer())
            {
                const auto val = *reinterpret_cast<const uint64_t*>(elemBytes.data());
                cv             = ConstantValue::makeValuePointer(ctx, typeField->payloadTypeRef(), val);
            }
            else
            {
                return Result::Continue;
            }

            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, cv));
            return Result::Continue;
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

    ////////////////////////////////////////////////////////
    if (nodeExprView.type->isArray())
    {
        const auto&    arrayDims   = nodeExprView.type->payloadArrayDims();
        const uint64_t numExpected = arrayDims.size();
        if (numExpected > 1)
        {
            std::vector<uint64_t> dims;
            for (size_t i = 1; i < numExpected; i++)
                dims.push_back(arrayDims[i]);
            const auto typeArray = TypeInfo::makeArray(dims, nodeExprView.type->payloadArrayElemTypeRef(), nodeExprView.type->flags());
            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(typeArray));
        }
        else
        {
            sema.setType(sema.curNodeRef(), nodeExprView.type->payloadArrayElemTypeRef());
        }
    }

    ////////////////////////////////////////////////////////
    else if (nodeExprView.type->isBlockPointer())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type->payloadTypeRef());
    }

    ////////////////////////////////////////////////////////
    else if (nodeExprView.type->isSlice())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type->payloadTypeRef());
    }

    ////////////////////////////////////////////////////////
    else if (nodeExprView.type->isString() || nodeExprView.type->isCString())
    {
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeU8());
    }

    ////////////////////////////////////////////////////////
    else if (nodeExprView.type->isValuePointer())
    {
        return SemaError::raisePointerArithmeticValuePointer(sema, sema.node(nodeExprRef), nodeExprRef, nodeExprView.typeRef);
    }

    ////////////////////////////////////////////////////////
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef);
    }

    RESULT_VERIFY(constantFold(sema, nodeArgRef, nodeExprView, constIndex, hasConstIndex));

    SemaInfo::setIsLValue(*this);
    SemaInfo::setIsValue(*this);

    return Result::Continue;
}

Result AstIndexListExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    SmallVector<AstNodeRef> children;
    sema.ast().nodes(children, spanChildrenRef);

    ////////////////////////////////////////////////////////
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

        bool                            allConstant = nodeExprView.cst != nullptr;
        std::vector<int64_t>            constIndexes;
        const std::vector<ConstantRef>* curValues = allConstant ? &nodeExprView.cst->getAggregateArray() : nullptr;

        for (size_t i = 0; i < numGot; i++)
        {
            const auto         nodeRef = children[i];
            const SemaNodeView nodeArgView(sema, nodeRef);

            int64_t constIndex    = 0;
            bool    hasConstIndex = false;
            RESULT_VERIFY(checkIndex(sema, nodeRef, nodeArgView, constIndex, hasConstIndex));

            if (hasConstIndex)
            {
                constIndexes.push_back(constIndex);
                if (allConstant)
                {
                    if (std::cmp_greater_equal(constIndex, curValues->size()))
                        return SemaError::raiseIndexOutOfRange(sema, constIndex, curValues->size(), nodeRef);

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
            std::vector<uint64_t> dims;
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

    ////////////////////////////////////////////////////////
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
        }

        sema.setType(sema.curNodeRef(), nodeExprView.type->payloadArrayElemTypeRef());
        if (SemaInfo::isLValue(sema.node(nodeExprRef)))
            SemaInfo::setIsLValue(*this);
    }

    ////////////////////////////////////////////////////////
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef);
    }

    SemaInfo::setIsValue(*this);
    return Result::Continue;
}

SWC_END_NAMESPACE();
