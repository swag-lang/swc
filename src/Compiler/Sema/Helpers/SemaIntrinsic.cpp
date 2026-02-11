#include "pch.h"
#include "Compiler/Sema/Helpers/SemaIntrinsic.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool getFloatArgAsDouble(Sema& sema, AstNodeRef argRef, double& out)
    {
        argRef = sema.getSubstituteRef(argRef);
        const SemaNodeView argView(sema, argRef);
        if (!argView.cstRef.isValid())
            return false;
        if (!argView.type || !argView.type->isFloat())
            return false;
        out = sema.cstMgr().get(argView.cstRef).getFloat().asDouble();
        return true;
    }

    Result makeFloatResult(Sema& sema, AstNodeRef callRef, double value)
    {
        if (!std::isfinite(value))
            return Result::Continue;

        const TypeRef  resultTypeRef = sema.typeRefOf(callRef);
        const TypeInfo resultTy      = sema.typeMgr().get(resultTypeRef);
        if (!resultTy.isFloat())
            return Result::Continue;

        ApFloat       af(value);
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

    Result raiseInvalidIntrinsicArg(Sema& sema, const SymbolFunction& fn, AstNodeRef argRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_intrinsic_invalid_argument, argRef);
        diag.last().addArgument(Diagnostic::ARG_SYM, fn.name(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }
}

Result SemaIntrinsic::tryConstantFoldCall(Sema& sema, const AstCallExpr& call, const SymbolFunction& selectedFn, std::span<AstNodeRef> args)
{
    const Token& tok = sema.token(selectedFn.codeRef());

    switch (tok.id)
    {
        case TokenId::IntrinsicMin:
        case TokenId::IntrinsicMax:
        {
            SWC_ASSERT(args.size() == 2);

            const AstNodeRef   aRef = sema.getSubstituteRef(args[0]);
            const AstNodeRef   bRef = sema.getSubstituteRef(args[1]);
            const SemaNodeView aView(sema, aRef);
            const SemaNodeView bView(sema, bRef);
            if (!aView.cstRef.isValid() || !bView.cstRef.isValid())
                return Result::Continue;

            auto aCstRef = aView.cstRef;
            auto bCstRef = bView.cstRef;
            RESULT_VERIFY(Cast::promoteConstants(sema, aView, bView, aCstRef, bCstRef));

            const auto& aCst  = sema.cstMgr().get(aCstRef);
            const auto& bCst  = sema.cstMgr().get(bCstRef);
            const bool  takeA = tok.id == TokenId::IntrinsicMin ? aCst.le(bCst) : aCst.ge(bCst);
            sema.setConstant(sema.curNodeRef(), takeA ? aCstRef : bCstRef);
            return Result::Continue;
        }

        case TokenId::IntrinsicSqrt:
        {
            SWC_ASSERT(args.size() == 1);

            double x;
            if (!getFloatArgAsDouble(sema, args[0], x))
                return Result::Continue;
            if (x < 0.0)
                return raiseInvalidIntrinsicArg(sema, selectedFn, args[0]);

            return makeFloatResult(sema, sema.curNodeRef(), std::sqrt(x));
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

            // Domain checks for known restricted functions (only when constant folding).
            if ((tok.id == TokenId::IntrinsicLog || tok.id == TokenId::IntrinsicLog2 || tok.id == TokenId::IntrinsicLog10) && x <= 0.0)
                return raiseInvalidIntrinsicArg(sema, selectedFn, args[0]);
            if ((tok.id == TokenId::IntrinsicASin || tok.id == TokenId::IntrinsicACos) && (x < -1.0 || x > 1.0))
                return raiseInvalidIntrinsicArg(sema, selectedFn, args[0]);

            double r = 0.0;
            switch (tok.id)
            {
                case TokenId::IntrinsicSin: r = std::sin(x); break;
                case TokenId::IntrinsicCos: r = std::cos(x); break;
                case TokenId::IntrinsicTan: r = std::tan(x); break;
                case TokenId::IntrinsicSinh: r = std::sinh(x); break;
                case TokenId::IntrinsicCosh: r = std::cosh(x); break;
                case TokenId::IntrinsicTanh: r = std::tanh(x); break;
                case TokenId::IntrinsicASin: r = std::asin(x); break;
                case TokenId::IntrinsicACos: r = std::acos(x); break;
                case TokenId::IntrinsicATan: r = std::atan(x); break;
                case TokenId::IntrinsicLog: r = std::log(x); break;
                case TokenId::IntrinsicLog2: r = std::log2(x); break;
                case TokenId::IntrinsicLog10: r = std::log10(x); break;
                case TokenId::IntrinsicFloor: r = std::floor(x); break;
                case TokenId::IntrinsicCeil: r = std::ceil(x); break;
                case TokenId::IntrinsicTrunc: r = std::trunc(x); break;
                case TokenId::IntrinsicRound: r = std::round(x); break;
                case TokenId::IntrinsicAbs: r = std::fabs(x); break;
                case TokenId::IntrinsicExp: r = std::exp(x); break;
                case TokenId::IntrinsicExp2: r = std::exp2(x); break;
                default: SWC_INTERNAL_ERROR(sema.ctx());
            }

            if (std::isnan(r))
                return raiseInvalidIntrinsicArg(sema, selectedFn, args[0]);

            return makeFloatResult(sema, sema.curNodeRef(), r);
        }

        case TokenId::IntrinsicATan2:
        {
            SWC_ASSERT(args.size() == 2);

            double y;
            double x;
            if (!getFloatArgAsDouble(sema, args[0], y) || !getFloatArgAsDouble(sema, args[1], x))
                return Result::Continue;

            return makeFloatResult(sema, sema.curNodeRef(), std::atan2(y, x));
        }

        case TokenId::IntrinsicPow:
        {
            SWC_ASSERT(args.size() == 2);

            double a;
            double b;
            if (!getFloatArgAsDouble(sema, args[0], a) || !getFloatArgAsDouble(sema, args[1], b))
                return Result::Continue;

            const double r = std::pow(a, b);
            if (std::isnan(r))
                return raiseInvalidIntrinsicArg(sema, selectedFn, args[0]);
            return makeFloatResult(sema, sema.curNodeRef(), r);
        }

        case TokenId::IntrinsicMulAdd:
        {
            SWC_ASSERT(args.size() == 3);
            double a;
            double b;
            double c;
            if (!getFloatArgAsDouble(sema, args[0], a) || !getFloatArgAsDouble(sema, args[1], b) || !getFloatArgAsDouble(sema, args[2], c))
                return Result::Continue;

            return makeFloatResult(sema, sema.curNodeRef(), std::fma(a, b, c));
        }

        default:
            break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
