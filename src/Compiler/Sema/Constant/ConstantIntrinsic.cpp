#include "pch.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void setDataOfPointerConstant(Sema& sema, TypeRef resultTypeRef, uint64_t ptrValue)
    {
        TaskContext&    ctx        = sema.ctx();
        const TypeInfo& resultType = sema.typeMgr().get(resultTypeRef);

        ConstantValue resultCst;
        if (resultType.isValuePointer())
        {
            resultCst = ConstantValue::makeValuePointer(ctx, resultType.payloadTypeRef(), ptrValue, resultType.flags());
        }
        else
        {
            SWC_ASSERT(resultType.isBlockPointer());
            resultCst = ConstantValue::makeBlockPointer(ctx, resultType.payloadTypeRef(), ptrValue, resultType.flags());
        }

        resultCst.setTypeRef(resultTypeRef);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, resultCst));
    }

    uint64_t materializeConstantAndGetAddress(Sema& sema, const SemaNodeView& view)
    {
        SWC_ASSERT(view.type());
        const uint64_t sizeOf = view.type()->sizeOf(sema.ctx());
        if (!sizeOf)
            return 0;

        SmallVector<std::byte> storage(sizeOf);
        const ByteSpanRW       storageSpan{storage.data(), storage.size()};
        std::memset(storageSpan.data(), 0, storageSpan.size());
        SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, storageSpan, view.cstRef(), view.typeRef()) == Result::Continue);

        const std::string_view persistentStorage = sema.cstMgr().addPayloadBuffer(asStringView(asByteSpan(storageSpan)));
        return reinterpret_cast<uint64_t>(persistentStorage.data());
    }

    bool getFloatArgAsDouble(Sema& sema, AstNodeRef argRef, double& out)
    {
        const SemaNodeView argView(sema, argRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        if (!argView.cstRef().isValid())
            return false;
        if (!argView.type() || !argView.type()->isFloat())
            return false;
        out = sema.cstMgr().get(argView.cstRef()).getFloat().asDouble();
        return true;
    }

    Result makeFloatResult(Sema& sema, AstNodeRef callRef, double value)
    {
        if (!std::isfinite(value))
            return Result::Continue;

        const TypeRef  resultTypeRef = sema.viewType(callRef).typeRef();
        const TypeInfo resultTy      = sema.typeMgr().get(resultTypeRef);
        if (!resultTy.isFloat())
            return Result::Continue;

        const ApFloat af(value);
        ConstantValue cv;
        if (resultTy.isFloatUnsized())
            cv = ConstantValue::makeFloatUnsized(sema.ctx(), af);
        else
            cv = ConstantValue::makeFloat(sema.ctx(), af, resultTy.payloadFloatBits());
        cv.setTypeRef(resultTypeRef);
        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), cv);
        sema.setConstant(callRef, cstRef);
        return Result::Continue;
    }

    Result raiseIntrinsicFoldError(Sema& sema, const SymbolFunction& fn, AstNodeRef argRef, Math::FoldStatus status)
    {
        const DiagnosticId diagId = Math::foldStatusDiagnosticId(status);
        SWC_ASSERT(diagId != DiagnosticId::None);
        const auto diag = SemaError::report(sema, diagId, argRef);
        diag.last().addArgument(Diagnostic::ARG_SYM, fn.name(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    bool mapTokenToUnaryIntrinsicFoldOp(Math::FoldIntrinsicUnaryFloatOp& outOp, TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::IntrinsicSqrt:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Sqrt;
                return true;
            case TokenId::IntrinsicSin:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Sin;
                return true;
            case TokenId::IntrinsicCos:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Cos;
                return true;
            case TokenId::IntrinsicTan:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Tan;
                return true;
            case TokenId::IntrinsicSinh:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Sinh;
                return true;
            case TokenId::IntrinsicCosh:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Cosh;
                return true;
            case TokenId::IntrinsicTanh:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Tanh;
                return true;
            case TokenId::IntrinsicASin:
                outOp = Math::FoldIntrinsicUnaryFloatOp::ASin;
                return true;
            case TokenId::IntrinsicACos:
                outOp = Math::FoldIntrinsicUnaryFloatOp::ACos;
                return true;
            case TokenId::IntrinsicATan:
                outOp = Math::FoldIntrinsicUnaryFloatOp::ATan;
                return true;
            case TokenId::IntrinsicLog:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Log;
                return true;
            case TokenId::IntrinsicLog2:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Log2;
                return true;
            case TokenId::IntrinsicLog10:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Log10;
                return true;
            case TokenId::IntrinsicFloor:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Floor;
                return true;
            case TokenId::IntrinsicCeil:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Ceil;
                return true;
            case TokenId::IntrinsicTrunc:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Trunc;
                return true;
            case TokenId::IntrinsicRound:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Round;
                return true;
            case TokenId::IntrinsicAbs:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Abs;
                return true;
            case TokenId::IntrinsicExp:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Exp;
                return true;
            case TokenId::IntrinsicExp2:
                outOp = Math::FoldIntrinsicUnaryFloatOp::Exp2;
                return true;
            default:
                return false;
        }
    }
}

void ConstantIntrinsic::tryConstantFoldDataOf(Sema& sema, TypeRef resultTypeRef, const SemaNodeView& view)
{
    if (!view.cstRef().isValid())
        return;

    const ConstantValue& cst  = sema.cstMgr().get(view.cstRef());
    const TypeInfo*      type = view.type();
    SWC_ASSERT(type);

    uint64_t ptrValue = 0;

    if (cst.isNull())
    {
        ptrValue = 0;
    }
    else if (type->isString())
    {
        if (!cst.isString())
            return;

        ptrValue = reinterpret_cast<uint64_t>(cst.getString().data());
    }
    else if (type->isSlice())
    {
        if (cst.isSlice())
            ptrValue = reinterpret_cast<uint64_t>(cst.getSlice().data());
        else if (cst.isString())
            ptrValue = reinterpret_cast<uint64_t>(cst.getString().data());
        else
            return;
    }
    else if (type->isArray())
    {
        if (cst.isArray())
            ptrValue = reinterpret_cast<uint64_t>(cst.getArray().data());
        else if (cst.isAggregateArray())
            ptrValue = materializeConstantAndGetAddress(sema, view);
        else
            return;
    }
    else if (type->isAnyPointer() || type->isCString())
    {
        if (cst.isString())
            ptrValue = reinterpret_cast<uint64_t>(cst.getString().data());
        else if (cst.isValuePointer())
            ptrValue = cst.getValuePointer();
        else if (cst.isBlockPointer())
            ptrValue = cst.getBlockPointer();
        else
            return;
    }
    else
    {
        return;
    }

    setDataOfPointerConstant(sema, resultTypeRef, ptrValue);
}

Result ConstantIntrinsic::tryConstantFoldCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args)
{
    const Token& tok = sema.token(selectedFn.codeRef());

    switch (tok.id)
    {
        case TokenId::IntrinsicMin:
        case TokenId::IntrinsicMax:
        {
            SWC_ASSERT(args.size() == 2);

            const SemaNodeView aView(sema, args[0], SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            const SemaNodeView bView(sema, args[1], SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            if (!aView.cstRef().isValid() || !bView.cstRef().isValid())
                return Result::Continue;

            auto aCstRef = aView.cstRef();
            auto bCstRef = bView.cstRef();
            SWC_RESULT(Cast::promoteConstants(sema, aView, bView, aCstRef, bCstRef));

            const ConstantValue& aCst  = sema.cstMgr().get(aCstRef);
            const ConstantValue& bCst  = sema.cstMgr().get(bCstRef);
            const bool           takeA = tok.id == TokenId::IntrinsicMin ? aCst.le(bCst) : aCst.ge(bCst);
            sema.setConstant(sema.curNodeRef(), takeA ? aCstRef : bCstRef);
            return Result::Continue;
        }

        case TokenId::IntrinsicSqrt:
        {
            SWC_ASSERT(args.size() == 1);

            double x;
            if (!getFloatArgAsDouble(sema, args[0], x))
                return Result::Continue;

            double                 foldedValue = 0.0;
            const Math::FoldStatus foldStatus  = Math::foldIntrinsicUnaryFloat(foldedValue, x, Math::FoldIntrinsicUnaryFloatOp::Sqrt);
            if (foldStatus != Math::FoldStatus::Ok)
                return raiseIntrinsicFoldError(sema, selectedFn, args[0], foldStatus);

            return makeFloatResult(sema, sema.curNodeRef(), foldedValue);
        }

        case TokenId::IntrinsicSin:
        case TokenId::IntrinsicCos:
        case TokenId::IntrinsicTan:
        case TokenId::IntrinsicSinh:
        case TokenId::IntrinsicCosh:
        case TokenId::IntrinsicTanh:
        case TokenId::IntrinsicASin:
        case TokenId::IntrinsicACos:
        case TokenId::IntrinsicATan:
        case TokenId::IntrinsicLog:
        case TokenId::IntrinsicLog2:
        case TokenId::IntrinsicLog10:
        case TokenId::IntrinsicFloor:
        case TokenId::IntrinsicCeil:
        case TokenId::IntrinsicTrunc:
        case TokenId::IntrinsicRound:
        case TokenId::IntrinsicAbs:
        case TokenId::IntrinsicExp:
        case TokenId::IntrinsicExp2:
        {
            SWC_ASSERT(args.size() == 1);

            double x;
            if (!getFloatArgAsDouble(sema, args[0], x))
                return Result::Continue;

            Math::FoldIntrinsicUnaryFloatOp foldOp;
            const bool                      mapped = mapTokenToUnaryIntrinsicFoldOp(foldOp, tok.id);
            SWC_ASSERT(mapped);

            double                 foldedValue = 0.0;
            const Math::FoldStatus foldStatus  = Math::foldIntrinsicUnaryFloat(foldedValue, x, foldOp);
            if (foldStatus != Math::FoldStatus::Ok)
                return raiseIntrinsicFoldError(sema, selectedFn, args[0], foldStatus);

            return makeFloatResult(sema, sema.curNodeRef(), foldedValue);
        }

        case TokenId::IntrinsicATan2:
        {
            SWC_ASSERT(args.size() == 2);

            double x, y;
            if (!getFloatArgAsDouble(sema, args[0], y) || !getFloatArgAsDouble(sema, args[1], x))
                return Result::Continue;

            double                 foldedValue = 0.0;
            const Math::FoldStatus foldStatus  = Math::foldIntrinsicBinaryFloat(foldedValue, y, x, Math::FoldIntrinsicBinaryFloatOp::ATan2);
            if (foldStatus != Math::FoldStatus::Ok)
                return raiseIntrinsicFoldError(sema, selectedFn, args[0], foldStatus);

            return makeFloatResult(sema, sema.curNodeRef(), foldedValue);
        }

        case TokenId::IntrinsicPow:
        {
            SWC_ASSERT(args.size() == 2);

            double a, b;
            if (!getFloatArgAsDouble(sema, args[0], a) || !getFloatArgAsDouble(sema, args[1], b))
                return Result::Continue;

            double                 foldedValue = 0.0;
            const Math::FoldStatus foldStatus  = Math::foldIntrinsicBinaryFloat(foldedValue, a, b, Math::FoldIntrinsicBinaryFloatOp::Pow);
            if (foldStatus != Math::FoldStatus::Ok)
                return raiseIntrinsicFoldError(sema, selectedFn, args[0], foldStatus);

            return makeFloatResult(sema, sema.curNodeRef(), foldedValue);
        }

        case TokenId::IntrinsicMulAdd:
        {
            SWC_ASSERT(args.size() == 3);
            double a, b, c;
            if (!getFloatArgAsDouble(sema, args[0], a) || !getFloatArgAsDouble(sema, args[1], b) || !getFloatArgAsDouble(sema, args[2], c))
                return Result::Continue;

            double                 foldedValue = 0.0;
            const Math::FoldStatus foldStatus  = Math::foldIntrinsicTernaryFloat(foldedValue, a, b, c, Math::FoldIntrinsicTernaryFloatOp::MulAdd);
            if (foldStatus != Math::FoldStatus::Ok)
                return raiseIntrinsicFoldError(sema, selectedFn, args[0], foldStatus);

            return makeFloatResult(sema, sema.curNodeRef(), foldedValue);
        }

        default:
            break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
