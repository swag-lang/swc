#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
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

    void appendDirectPreparedArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, TypeRef argTypeRef, MicroReg srcReg)
    {
        const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, argTypeRef, ABITypeNormalize::Usage::Argument);

        ABICall::PreparedArg arg;
        arg.srcReg      = srcReg;
        arg.kind        = ABICall::PreparedArgKind::Direct;
        arg.isFloat     = normalizedArg.isFloat;
        arg.isAddressed = false;
        arg.numBits     = normalizedArg.numBits;
        outArgs.push_back(arg);
    }

    SymbolFunction* runtimeSafetyPanicFunction(CodeGen& codeGen)
    {
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

        const ConstantValue  messageTextValue = ConstantValue::makeString(codeGen.ctx(), message);
        const ConstantRef    messageTextRef   = codeGen.cstMgr().addConstant(codeGen.ctx(), messageTextValue);
        const ConstantValue& messageTextCst   = codeGen.cstMgr().get(messageTextRef);
        const ConstantRef    messageCstRef    = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, codeGen.typeMgr().typeString(), messageTextCst.getString().data(), messageTextCst.getString().size());
        SWC_ASSERT(messageCstRef.isValid());
        const auto messageArg = makeAddressPayloadFromConstant(codeGen, messageCstRef);
        appendDirectPreparedArg(preparedArgs, codeGen, callConv, runtimeFunction.parameters()[0]->typeRef(), messageArg.reg);

        ConstantRef sourceLocCstRef = ConstantRef::invalid();
        SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), sourceLocCstRef, node));
        SWC_ASSERT(sourceLocCstRef.isValid());
        const auto sourceLocArg = makeAddressPayloadFromConstant(codeGen, sourceLocCstRef);
        appendDirectPreparedArg(preparedArgs, codeGen, callConv, runtimeFunction.parameters()[1]->typeRef(), sourceLocArg.reg);

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
