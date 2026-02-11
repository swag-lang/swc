#include "pch.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isPureIntrinsicToken(TokenId id)
    {
        switch (id)
        {
            case TokenId::IntrinsicMin:
            case TokenId::IntrinsicMax:
            case TokenId::IntrinsicSqrt:
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
            case TokenId::IntrinsicATan2:
            case TokenId::IntrinsicPow:
            case TokenId::IntrinsicMulAdd:
                return true;
            default:
                return false;
        }
    }

    bool getFloatArgAsDouble(Sema& sema, AstNodeRef argRef, ConstantRef argCst, double& out)
    {
        argRef = sema.getSubstituteRef(argRef);
        SemaNodeView argView(sema, argRef);
        if (argCst.isValid())
            argView.setCstRef(sema, argCst);
        if (!argView.cstRef.isValid())
            return false;
        if (!argView.type || !argView.type->isFloat())
            return false;
        out = sema.cstMgr().get(argView.cstRef).getFloat().asDouble();
        return true;
    }

    Result makeFloatResult(Sema& sema, AstNodeRef callRef, double value, ConstantRef& outResult)
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
        outResult = sema.cstMgr().addConstant(sema.ctx(), cv);
        return Result::Continue;
    }

    Result raiseInvalidIntrinsicArg(Sema& sema, const SymbolFunction& fn, AstNodeRef argRef)
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_intrinsic_invalid_argument, argRef);
        diag.last().addArgument(Diagnostic::ARG_SYM, fn.name(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result tryConstantFoldCallImpl(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, std::span<const ConstantRef> argCsts, AstNodeRef callRef, ConstantRef& outResult)
    {
        outResult         = ConstantRef::invalid();
        const Token& tok  = sema.token(selectedFn.codeRef());
        const bool  useCst = argCsts.size() == args.size();

        switch (tok.id)
        {
            case TokenId::IntrinsicMin:
            case TokenId::IntrinsicMax:
            {
                SWC_ASSERT(args.size() == 2);

                const AstNodeRef   aRef = sema.getSubstituteRef(args[0]);
                const AstNodeRef   bRef = sema.getSubstituteRef(args[1]);
                SemaNodeView       aView(sema, aRef);
                SemaNodeView       bView(sema, bRef);
                const ConstantRef  aCstArg = useCst ? argCsts[0] : ConstantRef::invalid();
                const ConstantRef  bCstArg = useCst ? argCsts[1] : ConstantRef::invalid();
                if (aCstArg.isValid())
                    aView.setCstRef(sema, aCstArg);
                if (bCstArg.isValid())
                    bView.setCstRef(sema, bCstArg);
                if (!aView.cstRef.isValid() || !bView.cstRef.isValid())
                    return Result::Continue;

                auto aCstRef = aView.cstRef;
                auto bCstRef = bView.cstRef;
                RESULT_VERIFY(Cast::promoteConstants(sema, aView, bView, aCstRef, bCstRef));

                const auto& aCst  = sema.cstMgr().get(aCstRef);
                const auto& bCst  = sema.cstMgr().get(bCstRef);
                const bool  takeA = tok.id == TokenId::IntrinsicMin ? aCst.le(bCst) : aCst.ge(bCst);
                outResult         = takeA ? aCstRef : bCstRef;
                return Result::Continue;
            }

            case TokenId::IntrinsicSqrt:
            {
                SWC_ASSERT(args.size() == 1);

                double x;
                const ConstantRef argCst = useCst ? argCsts[0] : ConstantRef::invalid();
                if (!getFloatArgAsDouble(sema, args[0], argCst, x))
                    return Result::Continue;
                if (x < 0.0)
                    return raiseInvalidIntrinsicArg(sema, selectedFn, args[0]);

                return makeFloatResult(sema, callRef, std::sqrt(x), outResult);
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
                const ConstantRef argCst = useCst ? argCsts[0] : ConstantRef::invalid();
                if (!getFloatArgAsDouble(sema, args[0], argCst, x))
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

                return makeFloatResult(sema, callRef, r, outResult);
            }

            case TokenId::IntrinsicATan2:
            {
                SWC_ASSERT(args.size() == 2);

                double x, y;
                const ConstantRef yCst = useCst ? argCsts[0] : ConstantRef::invalid();
                const ConstantRef xCst = useCst ? argCsts[1] : ConstantRef::invalid();
                if (!getFloatArgAsDouble(sema, args[0], yCst, y) || !getFloatArgAsDouble(sema, args[1], xCst, x))
                    return Result::Continue;

                return makeFloatResult(sema, callRef, std::atan2(y, x), outResult);
            }

            case TokenId::IntrinsicPow:
            {
                SWC_ASSERT(args.size() == 2);

                double a, b;
                const ConstantRef aCst = useCst ? argCsts[0] : ConstantRef::invalid();
                const ConstantRef bCst = useCst ? argCsts[1] : ConstantRef::invalid();
                if (!getFloatArgAsDouble(sema, args[0], aCst, a) || !getFloatArgAsDouble(sema, args[1], bCst, b))
                    return Result::Continue;

                const double r = std::pow(a, b);
                if (std::isnan(r))
                    return raiseInvalidIntrinsicArg(sema, selectedFn, args[0]);
                return makeFloatResult(sema, callRef, r, outResult);
            }

            case TokenId::IntrinsicMulAdd:
            {
                SWC_ASSERT(args.size() == 3);
                double a, b, c;
                const ConstantRef aCst = useCst ? argCsts[0] : ConstantRef::invalid();
                const ConstantRef bCst = useCst ? argCsts[1] : ConstantRef::invalid();
                const ConstantRef cCst = useCst ? argCsts[2] : ConstantRef::invalid();
                if (!getFloatArgAsDouble(sema, args[0], aCst, a) || !getFloatArgAsDouble(sema, args[1], bCst, b) || !getFloatArgAsDouble(sema, args[2], cCst, c))
                    return Result::Continue;

                return makeFloatResult(sema, callRef, std::fma(a, b, c), outResult);
            }

            default:
                break;
        }

        return Result::Continue;
    }
}

bool ConstantIntrinsic::isPureIntrinsic(Sema& sema, const SymbolFunction& selectedFn)
{
    const Token& tok = sema.token(selectedFn.codeRef());
    return isPureIntrinsicToken(tok.id);
}

Result ConstantIntrinsic::tryConstantFoldCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args)
{
    ConstantRef result = ConstantRef::invalid();
    RESULT_VERIFY(tryConstantFoldCallImpl(sema, selectedFn, args, {}, sema.curNodeRef(), result));
    if (result.isValid())
        sema.setConstant(sema.curNodeRef(), result);
    return Result::Continue;
}

Result ConstantIntrinsic::tryConstantFoldCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, std::span<const ConstantRef> argCsts, AstNodeRef callRef, ConstantRef& outResult)
{
    return tryConstantFoldCallImpl(sema, selectedFn, args, argCsts, callRef, outResult);
}

SWC_END_NAMESPACE();
