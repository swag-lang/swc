#include "pch.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef constantFoldStorageTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (!typeInfo.isAlias() && !typeInfo.isEnum())
            return typeRef;

        const TypeRef storageTypeRef = typeInfo.unwrapAliasEnum(sema.ctx(), typeRef);
        return storageTypeRef.isValid() ? storageTypeRef : typeRef;
    }

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

    bool getFloatArgAsDouble(Sema& sema, AstNodeRef argRef, double& out)
    {
        const SemaNodeView argView(sema, argRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        if (!argView.cstRef().isValid())
            return false;
        if (!argView.type())
            return false;

        const TypeRef   storageTypeRef = constantFoldStorageTypeRef(sema, argView.typeRef());
        const TypeInfo& storageType    = sema.typeMgr().get(storageTypeRef);
        if (!storageType.isFloat())
            return false;
        out = sema.cstMgr().get(argView.cstRef()).getFloat().asDouble();
        return true;
    }

    Result makeFloatResult(Sema& sema, AstNodeRef callRef, double value)
    {
        if (!std::isfinite(value))
            return Result::Continue;

        const TypeRef  resultTypeRef  = sema.viewType(callRef).typeRef();
        const TypeInfo resultTy       = sema.typeMgr().get(resultTypeRef);
        const TypeRef  storageTypeRef = constantFoldStorageTypeRef(sema, resultTypeRef);
        const TypeInfo storageTy      = sema.typeMgr().get(storageTypeRef);
        if (!storageTy.isFloat())
            return Result::Continue;

        const ApFloat af(value);
        ConstantValue cv;
        if (storageTy.isFloatUnsized())
        {
            cv = ConstantValue::makeFloatUnsized(sema.ctx(), af);
        }
        else
        {
            const uint32_t bitWidth = storageTy.payloadFloatBits();
            bool           exact    = false;
            bool           overflow = false;
            const ApFloat  typedAf  = af.toFloat(bitWidth, exact, overflow);
            if (overflow)
                return Result::Continue;
            cv = ConstantValue::makeFloat(sema.ctx(), typedAf, bitWidth);
        }
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

    bool getIntLikeArg(Sema& sema, AstNodeRef argRef, uint64_t& outValue, uint32_t& outBitWidth, bool& outUnsigned)
    {
        const SemaNodeView argView(sema, argRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        if (!argView.cstRef().isValid())
            return false;
        if (!argView.type())
            return false;

        const TypeRef   storageTypeRef = constantFoldStorageTypeRef(sema, argView.typeRef());
        const TypeInfo& storageType    = sema.typeMgr().get(storageTypeRef);
        if (!storageType.isIntLike())
            return false;
        const uint32_t bits = storageType.payloadIntLikeBits();
        if (bits == 0)
            return false;
        const ConstantValue& cst = sema.cstMgr().get(argView.cstRef());
        const ApsInt         v   = cst.getIntLike();
        outValue                 = v.as64();
        outBitWidth              = bits;
        outUnsigned              = storageType.isIntLikeUnsigned();
        return true;
    }

    Result makeIntResult(Sema& sema, AstNodeRef callRef, uint64_t value, uint32_t bitWidth, bool isUnsigned)
    {
        const TypeRef   resultTypeRef  = sema.viewType(callRef).typeRef();
        const TypeRef   storageTypeRef = constantFoldStorageTypeRef(sema, resultTypeRef);
        const TypeInfo& storageTy      = sema.typeMgr().get(storageTypeRef);
        if (!storageTy.isIntLike())
            return Result::Continue;

        const ApsInt  apsResult(std::bit_cast<int64_t>(value), bitWidth, isUnsigned);
        ConstantValue cv = ConstantValue::makeFromIntLike(sema.ctx(), apsResult, storageTy);
        cv.setTypeRef(resultTypeRef);
        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), cv);
        sema.setConstant(callRef, cstRef);
        return Result::Continue;
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

    enum class ReflectionLifecycleOp : uint8_t
    {
        None,
        HasDrop,
        HasPostMove,
        HasPostCopy,
        CanCopy,
        IsPod,
    };

    bool fullScopedNameMatchesSuffix(const SymbolFunction& selectedFn, TaskContext& ctx, const std::string_view suffix)
    {
        const Utf8             fullNameStorage = selectedFn.getFullScopedName(ctx);
        const std::string_view fullName        = fullNameStorage.view();
        if (fullName == suffix)
            return true;
        if (fullName.size() <= suffix.size())
            return false;
        return fullName.ends_with(suffix) && fullName[fullName.size() - suffix.size() - 1] == '.';
    }

    ReflectionLifecycleOp reflectionLifecycleOp(Sema& sema, const SymbolFunction& selectedFn)
    {
        if (selectedFn.returnTypeRef().isValid() && !sema.typeMgr().get(selectedFn.returnTypeRef()).isBool())
            return ReflectionLifecycleOp::None;

        const std::string_view name = selectedFn.name(sema.ctx());
        if (name != "hasDrop" &&
            name != "hasPostMove" &&
            name != "hasPostCopy" &&
            name != "canCopy" &&
            name != "isPod")
            return ReflectionLifecycleOp::None;

        Utf8 expected = "Reflection.";
        expected += name;
        if (!fullScopedNameMatchesSuffix(selectedFn, sema.ctx(), expected.view()))
            return ReflectionLifecycleOp::None;

        if (name == "hasDrop")
            return ReflectionLifecycleOp::HasDrop;
        if (name == "hasPostMove")
            return ReflectionLifecycleOp::HasPostMove;
        if (name == "hasPostCopy")
            return ReflectionLifecycleOp::HasPostCopy;
        if (name == "canCopy")
            return ReflectionLifecycleOp::CanCopy;
        return ReflectionLifecycleOp::IsPod;
    }

    bool lifecycleFoldResult(const TypeGen::LifecycleFlags& flags, const ReflectionLifecycleOp op)
    {
        switch (op)
        {
            case ReflectionLifecycleOp::HasDrop:
                return flags.hasDrop;
            case ReflectionLifecycleOp::HasPostMove:
                return flags.hasPostMove;
            case ReflectionLifecycleOp::HasPostCopy:
                return flags.hasPostCopy;
            case ReflectionLifecycleOp::CanCopy:
                return flags.canCopy;
            case ReflectionLifecycleOp::IsPod:
                return !flags.hasDrop && !flags.hasPostMove && !flags.hasPostCopy;
            default:
                SWC_UNREACHABLE();
        }
    }

    TypeRef reflectedLifecycleTypeArg(Sema& sema, const AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return TypeRef::invalid();

        const SemaNodeView argView(sema, argRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        if (!SemaHelpers::isTypeLikeTypeRef(sema.ctx(), argView.typeRef()))
            return TypeRef::invalid();

        return SemaHelpers::resolveRepresentedTypeRef(sema, argView);
    }

    void setBoolCallConstant(Sema& sema, const bool value)
    {
        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeBool(sema.ctx(), value));
        sema.setConstant(sema.curNodeRef(), cstRef);
        sema.setFoldedTypedConst(sema.curNodeRef());
    }
}

void ConstantIntrinsic::tryConstantFoldDataOf(Sema& sema, TypeRef resultTypeRef, const SemaNodeView& view)
{
    if (!view.cstRef().isValid())
        return;

    const ConstantValue& cst         = sema.cstMgr().get(view.cstRef());
    TypeRef              dataTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), view.typeRef());
    if (view.cstRef().isValid())
        dataTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(sema, dataTypeRef, view.cstRef());
    const TypeInfo* type = &sema.typeMgr().get(dataTypeRef);

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
            ptrValue = ConstantHelpers::materializeConstantStorageAndGetAddress(sema, view);
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
    else if (type->isInterface())
    {
        if (cst.isStruct())
        {
            const auto* runtimeInterface = cst.getStruct<Runtime::Interface>(view.typeRef());
            ptrValue                     = reinterpret_cast<uint64_t>(runtimeInterface->obj);
        }
        else
        {
            const auto* runtimeInterface = reinterpret_cast<const Runtime::Interface*>(ConstantHelpers::materializeConstantStorageAndGetAddress(sema, view));
            ptrValue                     = runtimeInterface ? reinterpret_cast<uint64_t>(runtimeInterface->obj) : 0;
        }
    }
    else
    {
        return;
    }

    setDataOfPointerConstant(sema, resultTypeRef, ptrValue);
}

Result ConstantIntrinsic::tryConstantFoldCallBeforeParameterCasts(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args)
{
    const ReflectionLifecycleOp op = reflectionLifecycleOp(sema, selectedFn);
    if (op == ReflectionLifecycleOp::None || args.size() != 1)
        return Result::Continue;

    const TypeRef typeRef = reflectedLifecycleTypeArg(sema, args[0]);
    if (!typeRef.isValid())
        return Result::Continue;

    const TypeInfo& type = sema.typeMgr().get(typeRef);
    const Symbol*   sym  = type.getSymbol();
    if (sym && !sym->isTyped())
        return Result::Continue;

    const TypeGen::LifecycleFlags flags = TypeGen::lifecycleFlagsOfTypeRef(sema.ctx(), typeRef);
    setBoolCallConstant(sema, lifecycleFoldResult(flags, op));
    return Result::Continue;
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
            if (!aView.type()->isAlias() && !bView.type()->isAlias())
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

        case TokenId::IntrinsicAbs:
        {
            SWC_ASSERT(args.size() == 1);

            // Integer abs
            {
                const SemaNodeView argView(sema, args[0], SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
                if (argView.cstRef().isValid() && argView.type())
                {
                    const TypeRef   storageTypeRef = constantFoldStorageTypeRef(sema, argView.typeRef());
                    const TypeInfo& storageType    = sema.typeMgr().get(storageTypeRef);
                    const uint32_t  bits           = storageType.isIntLike() ? storageType.payloadIntLikeBits() : 0;
                    if (bits > 0)
                    {
                        const ConstantValue& cst      = sema.cstMgr().get(argView.cstRef());
                        ApsInt               v        = cst.getIntLike();
                        bool                 overflow = false;
                        v.abs(overflow);
                        return makeIntResult(sema, sema.curNodeRef(), v.as64(), bits, storageType.isIntLikeUnsigned());
                    }
                }
            }

            // Float abs
            double x;
            if (!getFloatArgAsDouble(sema, args[0], x))
                return Result::Continue;

            double                 foldedValue = 0.0;
            const Math::FoldStatus foldStatus  = Math::foldIntrinsicUnaryFloat(foldedValue, x, Math::FoldIntrinsicUnaryFloatOp::Abs);
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

        case TokenId::IntrinsicBitCountNz:
        case TokenId::IntrinsicBitCountTz:
        case TokenId::IntrinsicBitCountLz:
        {
            SWC_ASSERT(args.size() == 1);

            uint64_t val;
            uint32_t bits;
            bool     uns;
            if (!getIntLikeArg(sema, args[0], val, bits, uns))
                return Result::Continue;

            // Mask to the actual bit width
            if (bits < 64)
                val &= (1ULL << bits) - 1;

            uint64_t result = 0;
            if (tok.id == TokenId::IntrinsicBitCountNz)
            {
                result = static_cast<uint64_t>(std::popcount(val));
            }
            else if (tok.id == TokenId::IntrinsicBitCountTz)
            {
                if (val == 0)
                    result = bits;
                else
                    result = static_cast<uint64_t>(std::countr_zero(val));
            }
            else
            {
                if (val == 0)
                    result = bits;
                else
                    result = static_cast<uint64_t>(std::countl_zero(val)) - (64 - bits);
            }

            return makeIntResult(sema, sema.curNodeRef(), result, bits, true);
        }

        case TokenId::IntrinsicByteSwap:
        {
            SWC_ASSERT(args.size() == 1);

            uint64_t val;
            uint32_t bits;
            bool     uns;
            if (!getIntLikeArg(sema, args[0], val, bits, uns))
                return Result::Continue;

            uint64_t result = 0;
            switch (bits)
            {
                case 16:
                {
                    const auto v = static_cast<uint16_t>(val);
                    result       = static_cast<uint64_t>((v >> 8) | (v << 8));
                    break;
                }
                case 32:
                {
                    const auto v = static_cast<uint32_t>(val);
                    result       = static_cast<uint64_t>(((v >> 24) & 0x000000FF) | ((v >> 8) & 0x0000FF00) | ((v << 8) & 0x00FF0000) | ((v << 24) & 0xFF000000));
                    break;
                }
                case 64:
                {
                    result =
                        ((val >> 56) & 0x00000000000000FFULL) |
                        ((val >> 40) & 0x000000000000FF00ULL) |
                        ((val >> 24) & 0x0000000000FF0000ULL) |
                        ((val >> 8) & 0x00000000FF000000ULL) |
                        ((val << 8) & 0x000000FF00000000ULL) |
                        ((val << 24) & 0x0000FF0000000000ULL) |
                        ((val << 40) & 0x00FF000000000000ULL) |
                        ((val << 56) & 0xFF00000000000000ULL);
                    break;
                }
                default:
                    return Result::Continue;
            }

            return makeIntResult(sema, sema.curNodeRef(), result, bits, true);
        }

        case TokenId::IntrinsicRol:
        case TokenId::IntrinsicRor:
        {
            SWC_ASSERT(args.size() == 2);

            uint64_t val;
            uint32_t valBits;
            bool     valUns;
            if (!getIntLikeArg(sema, args[0], val, valBits, valUns))
                return Result::Continue;

            uint64_t count;
            uint32_t countBits;
            bool     countUns;
            if (!getIntLikeArg(sema, args[1], count, countBits, countUns))
                return Result::Continue;

            // Mask value and count
            if (valBits < 64)
                val &= (1ULL << valBits) - 1;
            count %= valBits;

            uint64_t result;
            if (count == 0)
            {
                result = val;
            }
            else if (tok.id == TokenId::IntrinsicRol)
            {
                result = (val << count) | (val >> (valBits - count));
            }
            else
            {
                result = (val >> count) | (val << (valBits - count));
            }

            if (valBits < 64)
                result &= (1ULL << valBits) - 1;

            return makeIntResult(sema, sema.curNodeRef(), result, valBits, true);
        }

        default:
            break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
