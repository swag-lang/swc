#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool hasRuntimeSafety(const CodeGen& codeGen, const Runtime::SafetyWhat what)
    {
        const auto* nodePayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        return nodePayload && nodePayload->hasRuntimeSafety(what);
    }

    CodeGenNodePayload makeAddressPayloadFromConstant(CodeGen& codeGen, ConstantRef cstRef)
    {
        const ConstantValue& cst = codeGen.cstMgr().get(cstRef);
        SWC_ASSERT(cst.isStruct() || cst.isArray());

        const ByteSpan bytes = cst.isStruct() ? cst.getStruct() : cst.getArray();
        const uint64_t addr  = reinterpret_cast<uint64_t>(bytes.data());

        CodeGenNodePayload payload;
        payload.typeRef = cst.typeRef();
        payload.reg     = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(payload.reg, addr, cstRef);
        payload.setIsAddress();
        return payload;
    }

    SymbolFunction* runtimeSafetyPanicFunction(CodeGen& codeGen, const CodeGenNodePayload* nodePayload = nullptr)
    {
        if (nodePayload && nodePayload->runtimeFunctionSymbol != nullptr)
            return nodePayload->runtimeFunctionSymbol;

        if (const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
            payload && payload->runtimeFunctionSymbol != nullptr)
        {
            return payload->runtimeFunctionSymbol;
        }

        const IdentifierRef idRef = codeGen.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SafetyPanic);
        if (idRef.isInvalid())
            return nullptr;

        return codeGen.compiler().runtimeFunctionSymbol(idRef);
    }

    Result emitRuntimePanicCall(CodeGen& codeGen, SymbolFunction& runtimeFunction, const AstNode& node, std::string_view message)
    {
        codeGen.function().addCallDependency(&runtimeFunction);
        SWC_ASSERT(runtimeFunction.parameters().size() == 2);

        const CallConvKind                callConvKind = runtimeFunction.callConvKind();
        const CallConv&                   callConv     = CallConv::get(callConvKind);
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);

        const ConstantRef messageCstRef = CodeGenConstantHelpers::materializeRuntimeStringConstant(codeGen, codeGen.typeMgr().typeString(), message);
        SWC_ASSERT(messageCstRef.isValid());
        const auto messageArg = makeAddressPayloadFromConstant(codeGen, messageCstRef);
        CodeGenCallHelpers::appendDirectPreparedArg(preparedArgs, codeGen, callConv, runtimeFunction.parameters()[0]->typeRef(), messageArg.reg);

        ConstantRef sourceLocCstRef = ConstantRef::invalid();
        SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), sourceLocCstRef, node));
        SWC_ASSERT(sourceLocCstRef.isValid());
        const auto sourceLocArg = makeAddressPayloadFromConstant(codeGen, sourceLocCstRef);
        CodeGenCallHelpers::appendDirectPreparedArg(preparedArgs, codeGen, callConv, runtimeFunction.parameters()[1]->typeRef(), sourceLocArg.reg);

        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (runtimeFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &runtimeFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &runtimeFunction, preparedCall);

        return Result::Continue;
    }

    Result emitRuntimeDiagnosticCall(CodeGen& codeGen, SymbolFunction& runtimeFunction, const AstNode& node, const DiagnosticId diagId)
    {
        SWC_ASSERT(diagId != DiagnosticId::None);
        return emitRuntimePanicCall(codeGen, runtimeFunction, node, Diagnostic::diagIdMessage(diagId));
    }

    MicroReg materializeIndexBoundReg(CodeGen& codeGen, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload)
    {
        MicroBuilder&  builder  = codeGen.builder();
        const MicroReg countReg = codeGen.nextVirtualIntRegister();

        if (indexedType.isArray())
        {
            const uint64_t count = indexedType.payloadArrayDims().empty() ? 0 : indexedType.payloadArrayDims()[0];
            builder.emitLoadRegImm(countReg, ApInt(count, 64), MicroOpBits::B64);
            return countReg;
        }

        if (indexedType.isString())
        {
            builder.emitLoadRegMem(countReg, indexedPayload.reg, offsetof(Runtime::String, length), MicroOpBits::B64);
            return countReg;
        }

        if (indexedType.isSlice() || indexedType.isAnyVariadic())
        {
            builder.emitLoadRegMem(countReg, indexedPayload.reg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
            return countReg;
        }

        SWC_UNREACHABLE();
    }

    MicroReg emitFloatImmediateReg(CodeGen& codeGen, const MicroOpBits opBits, const uint64_t bits)
    {
        const MicroReg reg = codeGen.nextVirtualFloatRegister();
        codeGen.builder().emitLoadRegImm(reg, ApInt(bits, 64), opBits);
        return reg;
    }

    MicroReg widenIntRegTo64(CodeGen& codeGen, const MicroReg srcReg, const TypeInfo& srcType, const MicroOpBits srcBits)
    {
        if (srcBits == MicroOpBits::B64)
            return srcReg;

        MicroBuilder&  builder = codeGen.builder();
        const MicroReg dstReg  = codeGen.nextVirtualIntRegister();
        if (srcType.isIntLikeUnsigned())
            builder.emitLoadZeroExtendRegReg(dstReg, srcReg, MicroOpBits::B64, srcBits);
        else
            builder.emitLoadSignedExtendRegReg(dstReg, srcReg, MicroOpBits::B64, srcBits);
        return dstReg;
    }

    ApInt minSignedImmediate(const MicroOpBits opBits)
    {
        const uint32_t bits = getNumBits(opBits);
        SWC_ASSERT(bits > 0 && bits <= 64);
        const uint64_t value = bits == 64 ? (1ull << 63) : (1ull << (bits - 1));
        return ApInt(value, 64);
    }

    uint64_t maxUnsignedValue(const uint32_t bits)
    {
        if (bits >= 64)
            return std::numeric_limits<uint64_t>::max();
        return (1ull << bits) - 1;
    }

    uint64_t maxSignedValue(const uint32_t bits)
    {
        SWC_ASSERT(bits > 0 && bits <= 64);
        if (bits == 64)
            return std::numeric_limits<int64_t>::max();
        return (1ull << (bits - 1)) - 1;
    }

    uint64_t minSignedValue(const uint32_t bits)
    {
        SWC_ASSERT(bits > 0 && bits <= 64);
        if (bits == 64)
            return 1ull << 63;
        const int64_t value = -(static_cast<int64_t>(1ull << (bits - 1)));
        return static_cast<uint64_t>(value);
    }

    uint64_t floatPow2Bits(const bool negative, const uint32_t exponent, const MicroOpBits floatBits)
    {
        if (floatBits == MicroOpBits::B32)
        {
            constexpr uint32_t bias = 127;
            const uint32_t     sign = negative ? (1u << 31) : 0u;
            return sign | (exponent + bias) << 23;
        }

        SWC_ASSERT(floatBits == MicroOpBits::B64);
        constexpr uint64_t bias = 1023;
        const uint64_t     sign = negative ? (1ull << 63) : 0ull;
        return sign | ((exponent + bias) << 52);
    }
}

bool CodeGenSafety::hasMathRuntimeSafety(const CodeGen& codeGen)
{
    return hasRuntimeSafety(codeGen, Runtime::SafetyWhat::Math);
}

bool CodeGenSafety::hasOverflowRuntimeSafety(const CodeGen& codeGen)
{
    return hasRuntimeSafety(codeGen, Runtime::SafetyWhat::Overflow);
}

Result CodeGenSafety::emitBoundCheck(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, MicroReg indexReg)
{
    if (!indexedType.isIndexable())
        return Result::Continue;

    const auto* nodePayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
    if (!nodePayload || !nodePayload->hasRuntimeSafety(Runtime::SafetyWhat::BoundCheck))
        return Result::Continue;

    SymbolFunction* panicFunction = runtimeSafetyPanicFunction(codeGen);
    SWC_ASSERT(panicFunction != nullptr);

    MicroBuilder&       builder     = codeGen.builder();
    const MicroReg      countReg    = materializeIndexBoundReg(codeGen, indexedType, indexedPayload);
    const MicroLabelRef inBoundsRef = builder.createLabel();
    builder.emitCmpRegReg(indexReg, countReg, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, inBoundsRef);
    SWC_RESULT(emitRuntimeDiagnosticCall(codeGen, *panicFunction, codeGen.node(indexRef), DiagnosticId::safety_err_bound_check));
    builder.placeLabel(inBoundsRef);
    return Result::Continue;
}

Result CodeGenSafety::emitLoopBoundCheck(CodeGen& codeGen, AstNodeRef nodeRef, MicroReg lowerReg, MicroReg upperReg, const TypeInfo& indexType, bool inclusive)
{
    if (!indexType.isInt())
        return Result::Continue;

    nodeRef = codeGen.resolvedNodeRef(nodeRef);
    if (nodeRef.isInvalid())
        return Result::Continue;

    const auto* nodePayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(nodeRef);
    if (!nodePayload || !nodePayload->hasRuntimeSafety(Runtime::SafetyWhat::BoundCheck))
        return Result::Continue;

    SymbolFunction* panicFunction = runtimeSafetyPanicFunction(codeGen, nodePayload);
    SWC_ASSERT(panicFunction != nullptr);

    const MicroOpBits opBits = CodeGenTypeHelpers::conditionBits(indexType, codeGen.ctx());
    SWC_ASSERT(opBits != MicroOpBits::Zero);

    MicroBuilder&       builder     = codeGen.builder();
    const MicroLabelRef inBoundsRef = builder.createLabel();
    builder.emitCmpRegReg(lowerReg, upperReg, opBits);
    const auto cpuCond = inclusive ? CodeGenCompareHelpers::lessEqualCond(indexType.isIntUnsigned()) : CodeGenCompareHelpers::lessCond(indexType.isIntUnsigned());
    builder.emitJumpToLabel(cpuCond, MicroOpBits::B32, inBoundsRef);
    SWC_RESULT(emitRuntimeDiagnosticCall(codeGen, *panicFunction, codeGen.node(nodeRef), DiagnosticId::safety_err_bound_check));
    builder.placeLabel(inBoundsRef);
    return Result::Continue;
}

Result CodeGenSafety::emitSwitchCheck(CodeGen& codeGen, const AstNode& node, SymbolFunction* panicFunction)
{
    SymbolFunction* resolvedPanicFunction = panicFunction ? panicFunction : runtimeSafetyPanicFunction(codeGen);
    SWC_ASSERT(resolvedPanicFunction != nullptr);
    return emitRuntimePanicCall(codeGen, *resolvedPanicFunction, node, "unexpected case value in complete switch");
}

Result CodeGenSafety::emitMathCheck(CodeGen& codeGen, const AstNode& node)
{
    const auto* nodePayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
    if (!nodePayload || !nodePayload->hasRuntimeSafety(Runtime::SafetyWhat::Math))
        return Result::Continue;

    SymbolFunction* panicFunction = runtimeSafetyPanicFunction(codeGen);
    SWC_ASSERT(panicFunction != nullptr);
    return emitRuntimeDiagnosticCall(codeGen, *panicFunction, node, DiagnosticId::safety_err_invalid_argument);
}

Result CodeGenSafety::emitOverflowCheck(CodeGen& codeGen, const AstNode& node)
{
    if (!hasOverflowRuntimeSafety(codeGen))
        return Result::Continue;

    SymbolFunction* panicFunction = runtimeSafetyPanicFunction(codeGen);
    SWC_ASSERT(panicFunction != nullptr);
    return emitRuntimeDiagnosticCall(codeGen, *panicFunction, node, DiagnosticId::safety_err_integer_overflow);
}

Result CodeGenSafety::emitOverflowTrapOnFailure(CodeGen& codeGen, const AstNode& node, const MicroCond successCond)
{
    if (!hasOverflowRuntimeSafety(codeGen))
        return Result::Continue;

    MicroBuilder&       builder      = codeGen.builder();
    const MicroLabelRef successLabel = builder.createLabel();
    builder.emitJumpToLabel(successCond, MicroOpBits::B32, successLabel);
    SWC_RESULT(emitOverflowCheck(codeGen, node));
    builder.placeLabel(successLabel);
    return Result::Continue;
}

Result CodeGenSafety::emitIntArithmeticOverflowCheck(CodeGen& codeGen, const AstNode& node, const TokenId binaryTokId, const bool isSigned)
{
    switch (binaryTokId)
    {
        case TokenId::SymPlus:
        case TokenId::SymMinus:
            return emitOverflowTrapOnFailure(codeGen, node, isSigned ? MicroCond::NotOverflow : MicroCond::AboveOrEqual);

        case TokenId::SymAsterisk:
            return emitOverflowTrapOnFailure(codeGen, node, MicroCond::NotOverflow);

        default:
            return Result::Continue;
    }
}

Result CodeGenSafety::emitShiftIntLike(CodeGen&          codeGen,
                                       const AstNode&    node,
                                       const MicroReg    valueReg,
                                       const MicroReg    rightReg,
                                       const TypeInfo&   operationType,
                                       const MicroOpBits opBits,
                                       const TokenId     shiftTokId,
                                       const bool        allowWrap)
{
    SWC_ASSERT(shiftTokId == TokenId::SymLowerLower || shiftTokId == TokenId::SymGreaterGreater);

    const bool          isLeftShift   = shiftTokId == TokenId::SymLowerLower;
    const bool          isSigned      = operationType.isIntLike() && !operationType.isIntLikeUnsigned();
    const bool          hasSafety     = hasOverflowRuntimeSafety(codeGen);
    const bool          checkOverflow = isLeftShift && hasSafety && !allowWrap;
    MicroBuilder&       builder       = codeGen.builder();
    const MicroOp       shiftOp       = isLeftShift ? MicroOp::ShiftLeft : (isSigned ? MicroOp::ShiftArithmeticRight : MicroOp::ShiftRight);
    const uint64_t      bitWidth      = getNumBits(opBits);
    const MicroReg      originalReg   = codeGen.nextVirtualIntRegister();
    const MicroReg      countReg64    = widenIntRegTo64(codeGen, rightReg, operationType, opBits);
    const MicroLabelRef nonNegative   = builder.createLabel();
    const MicroLabelRef normalLabel   = builder.createLabel();
    const MicroLabelRef largeLabel    = builder.createLabel();
    const MicroLabelRef doneLabel     = builder.createLabel();

    builder.emitLoadRegReg(originalReg, valueReg, opBits);

    if (isSigned)
    {
        builder.emitCmpRegImm(rightReg, ApInt(0, 64), opBits);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B32, nonNegative);
        if (hasSafety)
            SWC_RESULT(emitNegativeShiftCheck(codeGen, node));
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, normalLabel);
        builder.placeLabel(nonNegative);
    }

    builder.emitCmpRegImm(countReg64, ApInt(bitWidth, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, largeLabel);

    builder.placeLabel(normalLabel);
    builder.emitOpBinaryRegReg(valueReg, rightReg, shiftOp, opBits);
    if (checkOverflow)
    {
        const MicroReg reverseReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(reverseReg, valueReg, opBits);
        builder.emitOpBinaryRegReg(reverseReg, rightReg, isSigned ? MicroOp::ShiftArithmeticRight : MicroOp::ShiftRight, opBits);
        builder.emitCmpRegReg(reverseReg, originalReg, opBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
        SWC_RESULT(emitOverflowCheck(codeGen, node));
    }

    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(largeLabel);

    if (isLeftShift)
    {
        if (checkOverflow)
        {
            const MicroLabelRef zeroLabel = builder.createLabel();
            builder.emitCmpRegImm(originalReg, ApInt(0, 64), opBits);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, zeroLabel);
            SWC_RESULT(emitOverflowCheck(codeGen, node));
            builder.placeLabel(zeroLabel);
        }

        builder.emitClearReg(valueReg, opBits);
    }
    else if (isSigned)
    {
        const MicroLabelRef negativeLabel = builder.createLabel();
        builder.emitCmpRegImm(originalReg, ApInt(0, 64), opBits);
        builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, negativeLabel);
        builder.emitClearReg(valueReg, opBits);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
        builder.placeLabel(negativeLabel);
        builder.emitLoadRegImm(valueReg, ApInt(std::numeric_limits<uint64_t>::max(), 64), opBits);
    }
    else
    {
        builder.emitClearReg(valueReg, opBits);
    }

    builder.placeLabel(doneLabel);
    return Result::Continue;
}

Result CodeGenSafety::emitSignedDivOrModIntLike(CodeGen&          codeGen,
                                                const AstNode&    node,
                                                const MicroReg    leftReg,
                                                const MicroReg    rightReg,
                                                const MicroOp     op,
                                                const MicroOpBits opBits,
                                                const bool        zeroOnOverflow)
{
    MicroBuilder&       builder   = codeGen.builder();
    const MicroLabelRef doOpLabel = builder.createLabel();
    const MicroLabelRef doneLabel = builder.createLabel();
    builder.emitCmpRegImm(rightReg, ApInt(std::numeric_limits<uint64_t>::max(), 64), opBits);
    builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, doOpLabel);
    builder.emitCmpRegImm(leftReg, minSignedImmediate(opBits), opBits);
    builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, doOpLabel);
    if (hasOverflowRuntimeSafety(codeGen))
        SWC_RESULT(emitOverflowCheck(codeGen, node));
    if (zeroOnOverflow)
        builder.emitClearReg(leftReg, opBits);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(doOpLabel);
    builder.emitOpBinaryRegReg(leftReg, rightReg, op, opBits);
    builder.placeLabel(doneLabel);
    return Result::Continue;
}

Result CodeGenSafety::emitNegativeShiftCheck(CodeGen& codeGen, const AstNode& node)
{
    if (!hasOverflowRuntimeSafety(codeGen))
        return Result::Continue;

    SymbolFunction* panicFunction = runtimeSafetyPanicFunction(codeGen);
    SWC_ASSERT(panicFunction != nullptr);
    return emitRuntimeDiagnosticCall(codeGen, *panicFunction, node, DiagnosticId::safety_err_negative_shift);
}

Result CodeGenSafety::emitUnaryMathDomainCheck(CodeGen& codeGen, const MicroReg valueReg, const TypeInfo& floatType, Math::FoldIntrinsicUnaryFloatOp op, const MicroLabelRef failLabel)
{
    if (!hasMathRuntimeSafety(codeGen))
        return Result::Continue;

    const auto opBits = CodeGenTypeHelpers::numericBits(floatType);
    SWC_ASSERT(floatType.isFloat());
    SWC_ASSERT(opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);

    MicroBuilder&  builder = codeGen.builder();
    const MicroReg zeroReg = emitFloatImmediateReg(codeGen, opBits, 0);
    if (op == Math::FoldIntrinsicUnaryFloatOp::Sqrt)
    {
        builder.emitCmpRegReg(valueReg, zeroReg, opBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 floatType,
                                                 {
                                                     .primaryCond        = MicroCond::Below,
                                                     .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered,
                                                 },
                                                 failLabel);
    }
    else if (op == Math::FoldIntrinsicUnaryFloatOp::Log || op == Math::FoldIntrinsicUnaryFloatOp::Log2 || op == Math::FoldIntrinsicUnaryFloatOp::Log10)
    {
        builder.emitCmpRegReg(valueReg, zeroReg, opBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 floatType,
                                                 {
                                                     .primaryCond        = MicroCond::Below,
                                                     .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered,
                                                 },
                                                 failLabel);
    }
    else
    {
        SWC_ASSERT(op == Math::FoldIntrinsicUnaryFloatOp::ASin || op == Math::FoldIntrinsicUnaryFloatOp::ACos);

        const uint64_t minusOneBits = opBits == MicroOpBits::B32 ? 0xBF800000ull : 0xBFF0000000000000ull;
        const uint64_t oneBits      = opBits == MicroOpBits::B32 ? 0x3F800000ull : 0x3FF0000000000000ull;
        const MicroReg minusOneReg  = emitFloatImmediateReg(codeGen, opBits, minusOneBits);
        const MicroReg oneReg       = emitFloatImmediateReg(codeGen, opBits, oneBits);

        builder.emitCmpRegReg(valueReg, minusOneReg, opBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 floatType,
                                                 {
                                                     .primaryCond        = MicroCond::Below,
                                                     .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered,
                                                 },
                                                 failLabel);

        builder.emitCmpRegReg(valueReg, oneReg, opBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 floatType,
                                                 {
                                                     .primaryCond        = MicroCond::Above,
                                                     .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered,
                                                 },
                                                 failLabel);
    }

    return Result::Continue;
}

Result CodeGenSafety::emitFloatNanCheck(CodeGen& codeGen, const AstNode& node, const MicroReg valueReg, const TypeInfo& floatType)
{
    if (!hasMathRuntimeSafety(codeGen))
        return Result::Continue;

    const auto opBits = CodeGenTypeHelpers::numericBits(floatType);
    SWC_ASSERT(floatType.isFloat());
    SWC_ASSERT(opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);

    MicroBuilder&       builder   = codeGen.builder();
    const MicroLabelRef failLabel = builder.createLabel();
    const MicroLabelRef doneLabel = builder.createLabel();
    builder.emitCmpRegReg(valueReg, valueReg, opBits);
    builder.emitJumpToLabel(MicroCond::Parity, MicroOpBits::B32, failLabel);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(failLabel);
    SWC_RESULT(emitMathCheck(codeGen, node));
    builder.placeLabel(doneLabel);
    return Result::Continue;
}

Result CodeGenSafety::emitIntLikeCastOverflowCheck(CodeGen& codeGen, const AstNode& node, const MicroReg srcReg, const TypeInfo& srcType, const TypeInfo& dstType)
{
    if (!hasOverflowRuntimeSafety(codeGen))
        return Result::Continue;
    if (srcType.isBool() || dstType.isBool())
        return Result::Continue;

    const MicroOpBits srcBits     = CodeGenTypeHelpers::numericOrBoolBits(srcType);
    const MicroReg    srcReg64    = widenIntRegTo64(codeGen, srcReg, srcType, srcBits);
    const bool        srcUnsigned = srcType.isIntLikeUnsigned();
    const bool        dstUnsigned = dstType.isIntLikeUnsigned();
    const uint32_t    dstBits     = dstType.payloadIntLikeBits();
    if (!dstBits)
        return Result::Continue;
    MicroBuilder&       builder   = codeGen.builder();
    const MicroLabelRef failLabel = builder.createLabel();
    const MicroLabelRef doneLabel = builder.createLabel();

    if (dstUnsigned)
    {
        if (!srcUnsigned)
        {
            builder.emitCmpRegImm(srcReg64, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, failLabel);
        }

        if (dstBits < 64)
        {
            builder.emitCmpRegImm(srcReg64, ApInt(maxUnsignedValue(dstBits), 64), MicroOpBits::B64);
            builder.emitJumpToLabel(srcUnsigned ? MicroCond::Above : MicroCond::Greater, MicroOpBits::B32, failLabel);
        }
    }
    else if (srcUnsigned)
    {
        builder.emitCmpRegImm(srcReg64, ApInt(maxSignedValue(dstBits), 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Above, MicroOpBits::B32, failLabel);
    }
    else if (dstBits < 64)
    {
        builder.emitCmpRegImm(srcReg64, ApInt(minSignedValue(dstBits), 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, failLabel);
        builder.emitCmpRegImm(srcReg64, ApInt(maxSignedValue(dstBits), 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Greater, MicroOpBits::B32, failLabel);
    }

    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(failLabel);
    SWC_RESULT(emitOverflowCheck(codeGen, node));
    builder.placeLabel(doneLabel);
    return Result::Continue;
}

Result CodeGenSafety::emitFloatToIntCastOverflowCheck(CodeGen& codeGen, const AstNode& node, const MicroReg srcReg, const TypeInfo& srcType, const TypeInfo& dstType)
{
    if (!hasOverflowRuntimeSafety(codeGen))
        return Result::Continue;
    if (dstType.isBool())
        return Result::Continue;

    const MicroOpBits srcBits = CodeGenTypeHelpers::numericOrBoolBits(srcType);
    const uint32_t    dstBits = dstType.payloadIntLikeBits();
    if (!dstBits)
        return Result::Continue;
    const bool          dstUnsigned = dstType.isIntLikeUnsigned();
    MicroBuilder&       builder     = codeGen.builder();
    const MicroLabelRef failLabel   = builder.createLabel();
    const MicroLabelRef doneLabel   = builder.createLabel();

    if (dstUnsigned)
    {
        const MicroReg zeroReg = codeGen.nextVirtualFloatRegister();
        builder.emitClearReg(zeroReg, srcBits);
        builder.emitCmpRegReg(srcReg, zeroReg, srcBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 srcType,
                                                 {
                                                     .primaryCond        = MicroCond::Below,
                                                     .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered,
                                                 },
                                                 failLabel);

        const MicroReg maxReg = codeGen.nextVirtualFloatRegister();
        builder.emitLoadRegImm(maxReg, ApInt(floatPow2Bits(false, dstBits, srcBits), 64), srcBits);
        builder.emitCmpRegReg(srcReg, maxReg, srcBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 srcType,
                                                 {
                                                     .primaryCond        = MicroCond::AboveOrEqual,
                                                     .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered,
                                                 },
                                                 failLabel);
    }
    else
    {
        const MicroReg minReg = codeGen.nextVirtualFloatRegister();
        builder.emitLoadRegImm(minReg, ApInt(floatPow2Bits(true, dstBits - 1, srcBits), 64), srcBits);
        builder.emitCmpRegReg(srcReg, minReg, srcBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 srcType,
                                                 {
                                                     .primaryCond        = MicroCond::Below,
                                                     .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered,
                                                 },
                                                 failLabel);

        const MicroReg maxReg = codeGen.nextVirtualFloatRegister();
        builder.emitLoadRegImm(maxReg, ApInt(floatPow2Bits(false, dstBits - 1, srcBits), 64), srcBits);
        builder.emitCmpRegReg(srcReg, maxReg, srcBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 srcType,
                                                 {
                                                     .primaryCond        = MicroCond::AboveOrEqual,
                                                     .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered,
                                                 },
                                                 failLabel);
    }

    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(failLabel);
    SWC_RESULT(emitOverflowCheck(codeGen, node));
    builder.placeLabel(doneLabel);
    return Result::Continue;
}

Result CodeGenSafety::emitUnaryMathIntrinsicCall(CodeGen& codeGen, const AstIntrinsicCallExpr& node, Math::FoldIntrinsicUnaryFloatOp op, MaterializeNumericOperandFn materializeOperandFn)
{
    SWC_ASSERT(materializeOperandFn != nullptr);
    if (!hasMathRuntimeSafety(codeGen))
        return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

    SmallVector<AstNodeRef> children;
    codeGen.ast().appendNodes(children, node.spanChildrenRef);
    SWC_ASSERT(children.size() == 1);

    const AstNodeRef          valueRef      = children[0];
    const CodeGenNodePayload& valuePayload  = codeGen.payload(valueRef);
    const SemaNodeView        valueView     = codeGen.viewType(valueRef);
    const TypeRef             valueTypeRef  = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
    const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
    MicroReg                  valueReg      = MicroReg::invalid();
    MicroBuilder&             builder       = codeGen.builder();
    const MicroLabelRef       failLabel     = builder.createLabel();
    const MicroLabelRef       doneLabel     = builder.createLabel();

    materializeOperandFn(valueReg, codeGen, valuePayload, valueTypeRef, resultTypeRef);
    SWC_RESULT(emitUnaryMathDomainCheck(codeGen, valueReg, codeGen.typeMgr().get(resultTypeRef), op, failLabel));
    SWC_RESULT(CodeGenCallHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef));
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(failLabel);
    SWC_RESULT(emitMathCheck(codeGen, node));
    builder.placeLabel(doneLabel);
    return Result::Continue;
}

Result CodeGenSafety::emitPowIntrinsicCall(CodeGen& codeGen, const AstIntrinsicCallExpr& node, LoadNumericOperandFn loadOperandFn)
{
    SWC_ASSERT(loadOperandFn != nullptr);
    SWC_RESULT(CodeGenCallHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef));
    if (!hasMathRuntimeSafety(codeGen))
        return Result::Continue;

    const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
    const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
    const CodeGenNodePayload& resultPayload = codeGen.payload(codeGen.curNodeRef());
    MicroReg                  resultReg     = MicroReg::invalid();
    loadOperandFn(resultReg, codeGen, resultPayload, resultTypeRef);
    return emitFloatNanCheck(codeGen, node, resultReg, resultType);
}

Result CodeGenSafety::emitDynCastCheck(CodeGen& codeGen, SymbolFunction& panicFunction, const AstNode& node)
{
    return emitRuntimeDiagnosticCall(codeGen, panicFunction, node, DiagnosticId::safety_err_dyn_cast);
}

Result CodeGenSafety::emitUnreachableCheck(CodeGen& codeGen, const AstNode& node)
{
    const auto* nodePayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
    if (!nodePayload || !nodePayload->hasRuntimeSafety(Runtime::SafetyWhat::Unreachable))
        return Result::Continue;

    SymbolFunction* panicFunction = runtimeSafetyPanicFunction(codeGen);
    SWC_ASSERT(panicFunction != nullptr);
    return emitRuntimePanicCall(codeGen, *panicFunction, node, "reached unreachable statement");
}

SWC_END_NAMESPACE();
