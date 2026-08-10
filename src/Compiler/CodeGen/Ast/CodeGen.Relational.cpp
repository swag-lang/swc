#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Sema attaches the comparison helper only where the operands really carry content: an
    // operand compared against 'null' is a null test and must stay a plain register compare.
    bool hasPreparedRuntimeContentCompare(const CodeGen& codeGen)
    {
        const auto* payload = codeGen.loweringPayload(codeGen.curNodeRef());
        return payload && payload->runtimeFunctionSymbol != nullptr;
    }

    SymbolFunction* preparedRuntimeCompareFunction(CodeGen& codeGen, IdentifierManager::PredefinedName fallbackName)
    {
        const auto* payload = codeGen.loweringPayload(codeGen.curNodeRef());
        if (payload && payload->runtimeFunctionSymbol != nullptr)
            return payload->runtimeFunctionSymbol;

        const IdentifierRef idRef = codeGen.idMgr().predefined(fallbackName);
        return idRef.isValid() ? codeGen.compiler().runtimeFunctionSymbol(idRef) : nullptr;
    }

    bool shouldReadScalarReference(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeRef normalizedTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), typeRef);
        if (!normalizedTypeRef.isValid())
            return false;

        const TypeInfo& normalizedType = codeGen.typeMgr().get(normalizedTypeRef);
        if (!normalizedType.isReference())
            return false;

        return codeGen.typeMgr().get(normalizedType.payloadTypeRef()).isScalarNumeric();
    }

    void normalizeScalarReferenceOperand(CodeGen& codeGen, CodeGenNodePayload& ioPayload, TypeRef& ioTypeRef)
    {
        const TypeRef normalizedTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), ioTypeRef);
        if (!normalizedTypeRef.isValid())
            return;

        const TypeInfo& normalizedType = codeGen.typeMgr().get(normalizedTypeRef);
        if (!normalizedType.isReference())
        {
            ioTypeRef = normalizedTypeRef;
            return;
        }

        const TypeRef payloadTypeRef = normalizedType.payloadTypeRef();
        if (!codeGen.typeMgr().get(payloadTypeRef).isScalarNumeric())
            return;

        ioTypeRef         = payloadTypeRef;
        ioPayload.typeRef = payloadTypeRef;
        if (ioPayload.isValue())
        {
            ioPayload.setIsAddress();
            return;
        }

        const MicroReg referenceSlotReg = ioPayload.reg;
        ioPayload.reg                   = codeGen.nextVirtualIntRegister();
        MicroBuilder&           builder = codeGen.builder();
        const ScopedDebugSource debugSource(builder, ioPayload.sourceCodeRef);
        builder.emitLoadRegMem(ioPayload.reg, referenceSlotReg, 0, MicroOpBits::B64);
        ioPayload.setIsAddress();
    }

    TypeRef resolveRelationalOperandTypeRef(CodeGen& codeGen, AstNodeRef operandRef, const SemaNodeView& operandView, const CodeGenNodePayload& operandPayload)
    {
        if (operandPayload.typeRef.isValid())
            return operandPayload.typeRef;

        const TypeRef storedTypeRef = codeGen.sema().viewStored(operandRef, SemaNodeViewPartE::Type).typeRef();
        if (storedTypeRef.isValid())
            return storedTypeRef;

        const AstNodeRef resolvedOperandRef = codeGen.resolvedNodeRef(operandRef);
        if (resolvedOperandRef != operandRef && resolvedOperandRef.isValid())
        {
            const TypeRef storedResolvedTypeRef = codeGen.sema().viewStored(resolvedOperandRef, SemaNodeViewPartE::Type).typeRef();
            if (storedResolvedTypeRef.isValid())
                return storedResolvedTypeRef;
        }

        return operandView.typeRef();
    }

    TypeRef resolveCompareTypeRef(CodeGen& codeGen, TypeRef leftTypeRef, TypeRef rightTypeRef)
    {
        if (shouldReadScalarReference(codeGen, leftTypeRef))
            leftTypeRef = codeGen.typeMgr().get(codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), leftTypeRef)).payloadTypeRef();
        else
            leftTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), leftTypeRef);

        if (shouldReadScalarReference(codeGen, rightTypeRef))
            rightTypeRef = codeGen.typeMgr().get(codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), rightTypeRef)).payloadTypeRef();
        else
            rightTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), rightTypeRef);

        const TypeInfo& leftType  = codeGen.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType = codeGen.typeMgr().get(rightTypeRef);
        if (leftType.isScalarNumeric() && rightType.isScalarNumeric())
        {
            const TypeRef promotedTypeRef = codeGen.typeMgr().promote(leftTypeRef, rightTypeRef, false);
            if (!promotedTypeRef.isValid())
                return promotedTypeRef;

            const TypeInfo& promotedType = codeGen.typeMgr().get(promotedTypeRef);
            // Integer compares run at their natural promoted width. An N-bit
            // comparison reads only the low N bits, so it is correct regardless of
            // the register's upper bits and needs no widening sign/zero-extend
            // (which the previous 32 -> 64 widening emitted on every compare).
            // Floats still widen f32 -> f64 for the backend's comparison form.
            if (promotedType.isFloat() && promotedType.payloadFloatBitsOr(64) == 32)
                return codeGen.typeMgr().typeFloat(64);

            return promotedTypeRef;
        }

        return leftTypeRef;
    }

    void loadCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        outReg                                 = codeGen.nextVirtualRegisterForType(operandTypeRef);
        const TypeInfo&   operandType          = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits opBits               = CodeGenTypeHelpers::compareBits(operandType, codeGen.ctx());
        const bool        isAddressBackedValue = operandType.sizeOf(codeGen.ctx()) > sizeof(uint64_t);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress() || (operandPayload.isValue() && isAddressBackedValue))
        {
            const ScopedDebugSource debugSource(builder, operandPayload.sourceCodeRef);
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        }
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    void convertCompareOperand(MicroReg& outReg, CodeGen& codeGen, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef == dstTypeRef)
            return;

        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstTypeRef);
        const MicroOpBits srcBits = CodeGenTypeHelpers::compareBits(srcType, codeGen.ctx());
        const MicroOpBits dstBits = CodeGenTypeHelpers::compareBits(dstType, codeGen.ctx());

        MicroBuilder& builder = codeGen.builder();

        if (srcType.isIntLike() && dstType.isIntLike())
        {
            const MicroReg dstReg = codeGen.nextVirtualIntRegister();
            if (srcBits == dstBits)
            {
                builder.emitLoadRegReg(dstReg, outReg, dstBits);
                outReg = dstReg;
                return;
            }

            if (getNumBits(srcBits) > getNumBits(dstBits))
            {
                builder.emitLoadRegReg(dstReg, outReg, dstBits);
                outReg = dstReg;
                return;
            }

            if (srcType.isIntSigned())
                builder.emitLoadSignedExtendRegReg(dstReg, outReg, dstBits, srcBits);
            else
                builder.emitLoadZeroExtendRegReg(dstReg, outReg, dstBits, srcBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isIntLike() && dstType.isFloat())
        {
            MicroReg srcReg = outReg;
            if (getNumBits(srcBits) < 32 || (dstBits == MicroOpBits::B64 && getNumBits(srcBits) == 32))
            {
                srcReg                        = codeGen.nextVirtualIntRegister();
                const MicroOpBits widenedBits = dstBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                if (srcType.isIntSigned())
                    builder.emitLoadSignedExtendRegReg(srcReg, outReg, widenedBits, srcBits);
                else
                    builder.emitLoadZeroExtendRegReg(srcReg, outReg, widenedBits, srcBits);
            }

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertIntToFloat, dstBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            if (srcBits == dstBits)
                return;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, outReg, MicroOp::ConvertFloatToFloat, srcBits);
            outReg = dstReg;
        }
    }

    void materializeCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef compareTypeRef)
    {
        loadCompareOperand(outReg, codeGen, operandPayload, operandTypeRef);
        convertCompareOperand(outReg, codeGen, operandTypeRef, compareTypeRef);
    }

    void loadTypeInfoComparePtr(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef operandTypeRef, TypeRef compareTypeRef)
    {
        const TypeRef   resolvedTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), operandTypeRef);
        const TypeInfo& operandType     = codeGen.typeMgr().get(resolvedTypeRef);
        if (operandType.isAny())
        {
            outReg                          = codeGen.nextVirtualIntRegister();
            MicroBuilder&           builder = codeGen.builder();
            const ScopedDebugSource debugSource(builder, payload.sourceCodeRef);
            builder.emitLoadRegMem(outReg, payload.reg, offsetof(Runtime::Any, type), MicroOpBits::B64);
            return;
        }

        materializeCompareOperand(outReg, codeGen, payload, operandTypeRef, compareTypeRef);
    }

    // Turns the 'true when equal' answer of a comparison helper into the boolean the operator
    // yields, so '!=' costs the same as '=='.
    void emitContentCompareResult(CodeGen& codeGen, TokenId tokId, const CodeGenNodePayload& resultPayload)
    {
        MicroBuilder&   builder = codeGen.builder();
        const MicroCond cond    = tokId == TokenId::SymEqualEqual ? MicroCond::NotEqual : MicroCond::Equal;
        builder.emitCmpRegImm(resultPayload.reg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitSetCondReg(resultPayload.reg, cond);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
    }

    // Two slices compare over their elements, like the array they view. The scalar path below
    // would only look at the data pointer, so two slices holding the same bytes over different
    // storage would answer 'false', and two slices of different lengths over the same storage
    // would answer 'true'.
    Result emitSliceCompareBool(CodeGen& codeGen, TokenId tokId, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, TypeRef sliceTypeRef)
    {
        SymbolFunction* sliceCmpSymbol = preparedRuntimeCompareFunction(codeGen, IdentifierManager::PredefinedName::RuntimeSliceCmp);
        SWC_ASSERT(sliceCmpSymbol != nullptr);
        if (!sliceCmpSymbol)
            return Result::Error;

        const TypeInfo& sliceType   = codeGen.typeMgr().get(codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), sliceTypeRef));
        const uint64_t  elementSize = codeGen.typeMgr().get(sliceType.payloadTypeRef()).sizeOf(codeGen.ctx());

        MicroBuilder&  builder       = codeGen.builder();
        const MicroReg leftDataReg   = codeGen.nextVirtualIntRegister();
        const MicroReg rightDataReg  = codeGen.nextVirtualIntRegister();
        const MicroReg leftCountReg  = codeGen.nextVirtualIntRegister();
        const MicroReg rightCountReg = codeGen.nextVirtualIntRegister();
        const MicroReg sizeReg       = codeGen.nextVirtualIntRegister();

        constexpr uint32_t dataOffset  = offsetof(Runtime::Slice<std::byte>, ptr);
        constexpr uint32_t countOffset = offsetof(Runtime::Slice<std::byte>, count);
        builder.emitLoadRegMem(leftDataReg, leftPayload.reg, dataOffset, MicroOpBits::B64);
        builder.emitLoadRegMem(leftCountReg, leftPayload.reg, countOffset, MicroOpBits::B64);
        builder.emitLoadRegMem(rightDataReg, rightPayload.reg, dataOffset, MicroOpBits::B64);
        builder.emitLoadRegMem(rightCountReg, rightPayload.reg, countOffset, MicroOpBits::B64);
        builder.emitLoadRegImm(sizeReg, ApInt(elementSize, 64), MicroOpBits::B64);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        const MicroReg            argRegs[]     = {leftDataReg, rightDataReg, leftCountReg, rightCountReg, sizeReg};
        SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, *sliceCmpSymbol, argRegs, resultPayload.reg));

        emitContentCompareResult(codeGen, tokId, resultPayload);
        return Result::Continue;
    }

    Result emitStringCompareBool(CodeGen& codeGen, TokenId tokId, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload)
    {
        SymbolFunction* stringCmpSymbol = preparedRuntimeCompareFunction(codeGen, IdentifierManager::PredefinedName::RuntimeStringCmp);
        SWC_ASSERT(stringCmpSymbol != nullptr);
        if (!stringCmpSymbol)
            return Result::Error;

        auto&                             stringCmpFunction = *stringCmpSymbol;
        const CallConvKind                callConvKind      = stringCmpFunction.callConvKind();
        const CallConv&                   callConv          = CallConv::get(callConvKind);
        const auto&                       params            = stringCmpFunction.parameters();
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);

        SWC_ASSERT(params.size() >= 2);
        SWC_ASSERT(params[0] != nullptr);
        SWC_ASSERT(params[1] != nullptr);
        CodeGenCallHelpers::appendPreparedStringCompareArg(preparedArgs, codeGen, callConv, leftPayload, params[0]->typeRef());
        CodeGenCallHelpers::appendPreparedStringCompareArg(preparedArgs, codeGen, callConv, rightPayload, params[1]->typeRef());

        CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);

        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (stringCmpFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &stringCmpFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &stringCmpFunction, preparedCall);

        const CodeGenNodePayload&              resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, stringCmpFunction.returnTypeRef(), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid);
        SWC_ASSERT(!normalizedRet.isIndirect);
        SWC_ASSERT(normalizedRet.numBits == 8);
        ABICall::materializeReturnToReg(builder, resultPayload.reg, callConvKind, normalizedRet);

        emitContentCompareResult(codeGen, tokId, resultPayload);
        return Result::Continue;
    }

    Result emitTypeInfoCompareBool(CodeGen& codeGen, TokenId tokId, const CodeGenNodePayload& leftPayload, TypeRef leftOperandTypeRef, const CodeGenNodePayload& rightPayload, TypeRef rightOperandTypeRef, TypeRef compareTypeRef)
    {
        MicroReg leftPtrReg, rightPtrReg;
        loadTypeInfoComparePtr(leftPtrReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        loadTypeInfoComparePtr(rightPtrReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();

        const MicroLabelRef sameTypeLabel  = builder.createLabel();
        const MicroLabelRef otherTypeLabel = builder.createLabel();
        const MicroLabelRef doneLabel      = builder.createLabel();
        CodeGenCompareHelpers::emitTypeInfoEqualJump(codeGen, leftPtrReg, rightPtrReg, sameTypeLabel, otherTypeLabel);

        const bool wantEqual = tokId == TokenId::SymEqualEqual;

        builder.placeLabel(sameTypeLabel);
        builder.emitLoadRegImm(resultPayload.reg, ApInt(wantEqual ? 1 : 0, 32), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        builder.placeLabel(otherTypeLabel);
        builder.emitLoadRegImm(resultPayload.reg, ApInt(wantEqual ? 0 : 1, 32), MicroOpBits::B32);

        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    // Integer compares run at their natural width (see resolveCompareTypeRef);
    // only floats are widened to the backend's f64 comparison form.
    void widenCompareRegsIfNeeded(MicroReg& leftReg, MicroReg& rightReg, CodeGen& codeGen, const TypeInfo& compareType, MicroOpBits& ioOpBits)
    {
        if (ioOpBits != MicroOpBits::B32)
            return;

        MicroBuilder& builder = codeGen.builder();
        if (compareType.isFloat())
        {
            constexpr auto widenedBits  = MicroOpBits::B64;
            const MicroReg widenedLeft  = codeGen.nextVirtualFloatRegister();
            const MicroReg widenedRight = codeGen.nextVirtualFloatRegister();
            builder.emitClearReg(widenedLeft, widenedBits);
            builder.emitOpBinaryRegReg(widenedLeft, leftReg, MicroOp::ConvertFloatToFloat, ioOpBits);
            builder.emitClearReg(widenedRight, widenedBits);
            builder.emitOpBinaryRegReg(widenedRight, rightReg, MicroOp::ConvertFloatToFloat, ioOpBits);
            leftReg  = widenedLeft;
            rightReg = widenedRight;
            ioOpBits = widenedBits;
        }
    }

    CodeGenCompareHelpers::CompareCondition buildCompareCondition(TokenId tokId, const TypeInfo& compareType)
    {
        using FloatUnorderedMode          = CodeGenCompareHelpers::FloatUnorderedMode;
        const bool unsignedOrFloatCompare = compareType.usesUnsignedConditions();
        switch (tokId)
        {
            case TokenId::SymLess:
                return {.primaryCond        = CodeGenCompareHelpers::lessCond(unsignedOrFloatCompare),
                        .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::RequireOrdered : FloatUnorderedMode::ExcludedByPrimary};
            case TokenId::SymLessEqual:
                return {.primaryCond        = CodeGenCompareHelpers::lessEqualCond(unsignedOrFloatCompare),
                        .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::RequireOrdered : FloatUnorderedMode::ExcludedByPrimary};
            case TokenId::SymGreater:
                return {.primaryCond = CodeGenCompareHelpers::greaterCond(unsignedOrFloatCompare)};
            case TokenId::SymGreaterEqual:
                return {.primaryCond = CodeGenCompareHelpers::greaterEqualCond(unsignedOrFloatCompare)};
            case TokenId::SymEqualEqual:
                return {.primaryCond        = MicroCond::Equal,
                        .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::RequireOrdered : FloatUnorderedMode::ExcludedByPrimary};
            case TokenId::SymBangEqual:
                return {.primaryCond        = MicroCond::NotEqual,
                        .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::AcceptUnordered : FloatUnorderedMode::ExcludedByPrimary};

            default:
                SWC_UNREACHABLE();
        }
    }

    Result emitSpecialCallResult(CodeGen& codeGen, const RelationalSpecOpPayload& relationalPayload)
    {
        const AstNodeRef callRef     = codeGen.curNodeRef();
        AstNodeRef       resolvedRef = codeGen.resolvedNodeRef(callRef);
        if ((resolvedRef.isInvalid() || resolvedRef == callRef) && relationalPayload.inlineSubstituteRef.isValid())
            resolvedRef = relationalPayload.inlineSubstituteRef;
        if (resolvedRef.isValid() && resolvedRef != callRef)
        {
            SWC_RESULT(codeGen.emitNodeNow(resolvedRef));
            codeGen.inheritPayload(callRef, resolvedRef);
            return Result::Continue;
        }

        return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
    }

    CodeGenNodePayload& materializeSpecialResultPayload(CodeGen& codeGen, TypeRef resultTypeRef, MicroOpBits opBits)
    {
        const CodeGenNodePayload callPayload   = codeGen.payload(codeGen.curNodeRef());
        CodeGenNodePayload&      resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        if (callPayload.isAddress())
            CodeGenMemoryHelpers::loadOperandToRegister(resultPayload.reg, codeGen, callPayload, callPayload.typeRef, opBits);
        else
            codeGen.builder().emitLoadRegReg(resultPayload.reg, callPayload.reg, opBits);
        return resultPayload;
    }

    Result emitSpecialEqualsNotEqual(CodeGen& codeGen, TypeRef resultTypeRef, const RelationalSpecOpPayload& relationalPayload)
    {
        SWC_RESULT(emitSpecialCallResult(codeGen, relationalPayload));

        const CodeGenNodePayload& resultPayload = materializeSpecialResultPayload(codeGen, resultTypeRef, MicroOpBits::B8);
        MicroBuilder&             builder       = codeGen.builder();
        builder.emitCmpRegImm(resultPayload.reg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitSetCondReg(resultPayload.reg, MicroCond::Equal);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
        return Result::Continue;
    }

    Result emitSpecialEqualsEqual(CodeGen& codeGen, TypeRef resultTypeRef, const RelationalSpecOpPayload& relationalPayload)
    {
        SWC_RESULT(emitSpecialCallResult(codeGen, relationalPayload));

        const CodeGenNodePayload& resultPayload = materializeSpecialResultPayload(codeGen, resultTypeRef, MicroOpBits::B8);
        MicroBuilder&             builder       = codeGen.builder();
        builder.emitCmpRegImm(resultPayload.reg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitSetCondReg(resultPayload.reg, MicroCond::NotEqual);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
        return Result::Continue;
    }

    Result emitSpecialCmpBool(CodeGen& codeGen, TokenId tokId, TypeRef resultTypeRef, const RelationalSpecOpPayload& relationalPayload)
    {
        SWC_RESULT(emitSpecialCallResult(codeGen, relationalPayload));

        auto cond = MicroCond::Equal;
        switch (tokId)
        {
            case TokenId::SymLess:
                cond = MicroCond::Less;
                break;
            case TokenId::SymLessEqual:
                cond = MicroCond::LessOrEqual;
                break;
            case TokenId::SymGreater:
                cond = MicroCond::Greater;
                break;
            case TokenId::SymGreaterEqual:
                cond = MicroCond::GreaterOrEqual;
                break;
            default:
                SWC_UNREACHABLE();
        }

        const CodeGenNodePayload& resultPayload = materializeSpecialResultPayload(codeGen, resultTypeRef, MicroOpBits::B32);
        MicroBuilder&             builder       = codeGen.builder();
        builder.emitCmpRegImm(resultPayload.reg, ApInt(0, 64), MicroOpBits::B32);
        builder.emitSetCondReg(resultPayload.reg, cond);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
        return Result::Continue;
    }

    Result emitSpecialCmpValue(CodeGen& codeGen, TypeRef resultTypeRef, const RelationalSpecOpPayload& relationalPayload)
    {
        SWC_RESULT(emitSpecialCallResult(codeGen, relationalPayload));
        materializeSpecialResultPayload(codeGen, resultTypeRef, MicroOpBits::B32);
        return Result::Continue;
    }

    Result emitSpecialRelational(CodeGen& codeGen, TokenId tokId, const SymbolFunction& calledFn, TypeRef resultTypeRef, const RelationalSpecOpPayload& relationalPayload)
    {
        switch (calledFn.specOpKind())
        {
            case SpecOpKind::OpEquals:
                if (tokId == TokenId::SymEqualEqual)
                    return emitSpecialEqualsEqual(codeGen, resultTypeRef, relationalPayload);
                if (tokId == TokenId::SymBangEqual)
                    return emitSpecialEqualsNotEqual(codeGen, resultTypeRef, relationalPayload);
                break;

            case SpecOpKind::OpCompare:
                if (tokId == TokenId::SymLessEqualGreater)
                    return emitSpecialCmpValue(codeGen, resultTypeRef, relationalPayload);
                if (tokId == TokenId::SymLess || tokId == TokenId::SymLessEqual || tokId == TokenId::SymGreater || tokId == TokenId::SymGreaterEqual)
                    return emitSpecialCmpBool(codeGen, tokId, resultTypeRef, relationalPayload);
                break;

            default:
                break;
        }

        SWC_UNREACHABLE();
    }

    // Compare two address-backed aggregate operands (structs/arrays) for equality by
    // comparing their full byte content, chunk by chunk. The scalar compare path only
    // looks at a single register-sized load, which silently ignores every field past
    // the first machine word for aggregates larger than a register.
    Result emitAggregateEqualsBool(CodeGen& codeGen, TokenId tokId, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, uint64_t sizeBytes)
    {
        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();

        const bool          isEqual       = tokId == TokenId::SymEqualEqual;
        const MicroLabelRef notEqualLabel = builder.createLabel();
        const MicroLabelRef doneLabel     = builder.createLabel();

        uint64_t offset = 0;
        while (offset < sizeBytes)
        {
            const uint64_t remain = sizeBytes - offset;

            MicroOpBits chunkBits;
            uint64_t    chunkSize;
            if (remain >= 8)
            {
                chunkBits = MicroOpBits::B64;
                chunkSize = 8;
            }
            else if (remain >= 4)
            {
                chunkBits = MicroOpBits::B32;
                chunkSize = 4;
            }
            else if (remain >= 2)
            {
                chunkBits = MicroOpBits::B16;
                chunkSize = 2;
            }
            else
            {
                chunkBits = MicroOpBits::B8;
                chunkSize = 1;
            }

            const MicroReg leftChunk  = codeGen.nextVirtualIntRegister();
            const MicroReg rightChunk = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(leftChunk, leftPayload.reg, static_cast<uint32_t>(offset), chunkBits);
            builder.emitLoadRegMem(rightChunk, rightPayload.reg, static_cast<uint32_t>(offset), chunkBits);
            builder.emitCmpRegReg(leftChunk, rightChunk, chunkBits);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, notEqualLabel);

            offset += chunkSize;
        }

        builder.emitLoadRegImm(resultPayload.reg, ApInt(isEqual ? 1 : 0, 32), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        builder.placeLabel(notEqualLabel);
        builder.emitLoadRegImm(resultPayload.reg, ApInt(isEqual ? 0 : 1, 32), MicroOpBits::B32);

        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result emitRelationalBool(CodeGen& codeGen, const AstRelationalExpr& node, TokenId tokId)
    {
        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);

        const CodeGenNodePayload& leftPayload         = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = codeGen.payload(node.nodeRightRef);
        TypeRef                   leftOperandTypeRef  = resolveRelationalOperandTypeRef(codeGen, node.nodeLeftRef, leftView, leftPayload);
        TypeRef                   rightOperandTypeRef = resolveRelationalOperandTypeRef(codeGen, node.nodeRightRef, rightView, rightPayload);
        SWC_ASSERT(leftOperandTypeRef.isValid());
        SWC_ASSERT(rightOperandTypeRef.isValid());
        CodeGenNodePayload leftOperandPayload  = leftPayload;
        CodeGenNodePayload rightOperandPayload = rightPayload;
        normalizeScalarReferenceOperand(codeGen, leftOperandPayload, leftOperandTypeRef);
        normalizeScalarReferenceOperand(codeGen, rightOperandPayload, rightOperandTypeRef);

        const TypeRef   compareTypeRef       = resolveCompareTypeRef(codeGen, leftOperandTypeRef, rightOperandTypeRef);
        const TypeRef   resolvedLeftTypeRef  = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), leftOperandTypeRef);
        const TypeRef   resolvedRightTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), rightOperandTypeRef);
        const TypeInfo& resolvedLeftType     = codeGen.typeMgr().get(resolvedLeftTypeRef);
        const TypeInfo& resolvedRightType    = codeGen.typeMgr().get(resolvedRightTypeRef);
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            ((resolvedLeftType.isAny() && resolvedRightType.isAnyTypeInfo(codeGen.ctx())) ||
             (resolvedLeftType.isAnyTypeInfo(codeGen.ctx()) && resolvedRightType.isAny())))
            return emitTypeInfoCompareBool(codeGen, tokId, leftPayload, leftOperandTypeRef, rightPayload, rightOperandTypeRef, codeGen.typeMgr().typeTypeInfo());

        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            CodeGenTypeHelpers::isStringCompareType(codeGen.ctx(), compareTypeRef) &&
            hasPreparedRuntimeContentCompare(codeGen))
            return emitStringCompareBool(codeGen, tokId, leftPayload, rightPayload);

        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            CodeGenTypeHelpers::isSliceCompareType(codeGen.ctx(), compareTypeRef) &&
            hasPreparedRuntimeContentCompare(codeGen))
            return emitSliceCompareBool(codeGen, tokId, leftOperandPayload, rightOperandPayload, compareTypeRef);

        const TypeInfo& compareType                   = codeGen.typeMgr().get(compareTypeRef);
        const bool      leftIsRuntimeTypeInfoPointer  = codeGen.typeMgr().isRuntimeTypeInfoPointer(codeGen.ctx(), leftOperandTypeRef);
        const bool      rightIsRuntimeTypeInfoPointer = codeGen.typeMgr().isRuntimeTypeInfoPointer(codeGen.ctx(), rightOperandTypeRef);
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) && compareType.isAnyTypeInfo(codeGen.ctx()))
            return emitTypeInfoCompareBool(codeGen, tokId, leftPayload, leftOperandTypeRef, rightPayload, rightOperandTypeRef, compareTypeRef);
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) && leftIsRuntimeTypeInfoPointer && rightIsRuntimeTypeInfoPointer)
            return emitTypeInfoCompareBool(codeGen, tokId, leftPayload, leftOperandTypeRef, rightPayload, rightOperandTypeRef, codeGen.typeMgr().typeTypeInfo());

        // Aggregates (structs/arrays) wider than a machine register must be compared over
        // their full content. The scalar path below only compares a single register-sized
        // load, which would ignore every field beyond the first machine word.
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            (compareType.isStruct() || compareType.isArray() || compareType.isAggregate()) &&
            compareType.sizeOf(codeGen.ctx()) > sizeof(uint64_t))
            return emitAggregateEqualsBool(codeGen, tokId, leftOperandPayload, rightOperandPayload, compareType.sizeOf(codeGen.ctx()));

        MicroOpBits opBits = CodeGenTypeHelpers::compareBits(compareType, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeCompareOperand(leftReg, codeGen, leftOperandPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightOperandPayload, rightOperandTypeRef, compareTypeRef);
        widenCompareRegsIfNeeded(leftReg, rightReg, codeGen, compareType, opBits);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        MicroBuilder& builder             = codeGen.builder();
        builder.emitCmpRegReg(leftReg, rightReg, opBits);

        const CodeGenCompareHelpers::CompareCondition condition = buildCompareCondition(tokId, compareType);
        CodeGenCompareHelpers::emitConditionBool(codeGen, resultPayload.reg, compareType, condition);
        return Result::Continue;
    }

    Result emitThreeWayCompare(CodeGen& codeGen, const AstRelationalExpr& node)
    {
        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);

        const CodeGenNodePayload& leftPayload         = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = codeGen.payload(node.nodeRightRef);
        TypeRef                   leftOperandTypeRef  = resolveRelationalOperandTypeRef(codeGen, node.nodeLeftRef, leftView, leftPayload);
        TypeRef                   rightOperandTypeRef = resolveRelationalOperandTypeRef(codeGen, node.nodeRightRef, rightView, rightPayload);
        SWC_ASSERT(leftOperandTypeRef.isValid());
        SWC_ASSERT(rightOperandTypeRef.isValid());
        CodeGenNodePayload leftOperandPayload  = leftPayload;
        CodeGenNodePayload rightOperandPayload = rightPayload;
        normalizeScalarReferenceOperand(codeGen, leftOperandPayload, leftOperandTypeRef);
        normalizeScalarReferenceOperand(codeGen, rightOperandPayload, rightOperandTypeRef);

        const TypeRef   compareTypeRef = resolveCompareTypeRef(codeGen, leftOperandTypeRef, rightOperandTypeRef);
        const TypeInfo& compareType    = codeGen.typeMgr().get(compareTypeRef);
        MicroOpBits     opBits         = CodeGenTypeHelpers::compareBits(compareType, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeCompareOperand(leftReg, codeGen, leftOperandPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightOperandPayload, rightOperandTypeRef, compareTypeRef);
        widenCompareRegsIfNeeded(leftReg, rightReg, codeGen, compareType, opBits);

        MicroBuilder& builder = codeGen.builder();

        const CodeGenCompareHelpers::CompareCondition lessCond  = buildCompareCondition(TokenId::SymLess, compareType);
        const CodeGenCompareHelpers::CompareCondition greatCond = buildCompareCondition(TokenId::SymGreater, compareType);

        const MicroReg lessReg  = codeGen.nextVirtualIntRegister();
        const MicroReg greatReg = codeGen.nextVirtualIntRegister();
        builder.emitCmpRegReg(leftReg, rightReg, opBits);
        builder.emitSetCondReg(lessReg, lessCond.primaryCond);
        builder.emitLoadZeroExtendRegReg(lessReg, lessReg, MicroOpBits::B32, MicroOpBits::B8);
        builder.emitSetCondReg(greatReg, greatCond.primaryCond);
        builder.emitLoadZeroExtendRegReg(greatReg, greatReg, MicroOpBits::B32, MicroOpBits::B8);

        if (CodeGenCompareHelpers::needsFloatUnorderedHandling(compareType, lessCond))
        {
            const MicroReg orderedReg = codeGen.nextVirtualIntRegister();
            builder.emitSetCondReg(orderedReg, MicroCond::NotParity);
            builder.emitLoadZeroExtendRegReg(orderedReg, orderedReg, MicroOpBits::B32, MicroOpBits::B8);
            builder.emitOpBinaryRegReg(lessReg, orderedReg, MicroOp::And, MicroOpBits::B32);
        }

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        // `<=>` is reconstructed from two predicates: `left > right` minus `left < right` yields
        // {+1, 0, -1} without needing a dedicated three-way compare opcode.
        builder.emitLoadRegReg(resultPayload.reg, greatReg, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(resultPayload.reg, lessReg, MicroOp::Subtract, MicroOpBits::B32);
        return Result::Continue;
    }
}

Result AstRelationalExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok               = codeGen.token(codeRef());
    const auto*  relationalPayload = codeGen.sema().semaPayload<RelationalSpecOpPayload>(codeGen.curNodeRef());
    if (relationalPayload && relationalPayload->calledFn != nullptr)
    {
        const TypeRef resultTypeRef = codeGen.viewType(codeGen.curNodeRef()).typeRef();
        SWC_ASSERT(resultTypeRef.isValid());
        codeGen.sema().setSymbol(codeGen.curNodeRef(), relationalPayload->calledFn);
        const auto& calledFn = *relationalPayload->calledFn;
        if (calledFn.specOpKind() == SpecOpKind::OpEquals || calledFn.specOpKind() == SpecOpKind::OpCompare)
            return emitSpecialRelational(codeGen, tok.id, calledFn, resultTypeRef, *relationalPayload);
    }

    if (tok.id == TokenId::SymLessEqualGreater)
        return emitThreeWayCompare(codeGen, *this);

    SWC_INTERNAL_CHECK(Token::isOpRelational(tok.id));
    return emitRelationalBool(codeGen, *this, tok.id);
}

SWC_END_NAMESPACE();
