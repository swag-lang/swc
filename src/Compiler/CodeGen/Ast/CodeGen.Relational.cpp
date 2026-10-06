#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenBinaryValueCall.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenIntegerConversion.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenVectorHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
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

    TypeRef normalizeScalarReferenceOperand(CodeGen& codeGen, CodeGenNodePayload& ioPayload, TypeRef& ioTypeRef)
    {
        if (!ioTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& declaredType      = codeGen.typeMgr().get(ioTypeRef);
        const TypeInfo* unwrappedType     = declaredType.unwrapAliasEnumType(codeGen.ctx());
        const TypeInfo& normalizedType    = unwrappedType ? *unwrappedType : declaredType;
        const TypeRef   normalizedTypeRef = normalizedType.typeRef();
        if (!normalizedType.isReference())
        {
            ioTypeRef = normalizedTypeRef;
            return normalizedTypeRef;
        }

        const TypeRef payloadTypeRef = normalizedType.payloadTypeRef();
        if (!codeGen.typeMgr().get(payloadTypeRef).isScalarNumeric())
            return normalizedTypeRef;

        ioTypeRef         = payloadTypeRef;
        ioPayload.typeRef = payloadTypeRef;
        if (ioPayload.isValue())
        {
            ioPayload.setIsAddress();
            return payloadTypeRef;
        }

        const MicroReg referenceSlotReg = ioPayload.reg;
        ioPayload.reg                   = codeGen.nextVirtualIntRegister();
        MicroBuilder&           builder = codeGen.builder();
        const ScopedDebugSource debugSource(builder, ioPayload.sourceCodeRef);
        builder.emitLoadRegMem(ioPayload.reg, referenceSlotReg, 0, MicroOpBits::B64);
        ioPayload.setIsAddress();
        return payloadTypeRef;
    }

    TypeRef resolveRelationalOperandTypeRef(CodeGen& codeGen, AstNodeRef operandRef, const CodeGenNodePayload& operandPayload)
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

        return codeGen.viewType(operandRef).typeRef();
    }

    TypeRef resolveCompareTypeRef(CodeGen& codeGen, TypeRef leftTypeRef, TypeRef rightTypeRef)
    {
        const TypeInfo& leftType  = codeGen.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType = codeGen.typeMgr().get(rightTypeRef);
        if (leftType.isScalarNumeric() && rightType.isScalarNumeric())
        {
            const TypeRef promotedTypeRef = codeGen.typeMgr().promote(leftTypeRef, rightTypeRef, false);
            if (!promotedTypeRef.isValid())
                return promotedTypeRef;

            // Compares run at their natural promoted width. An N-bit integer
            // comparison reads only the low N bits, so it is correct regardless of
            // the register's upper bits and needs no widening sign/zero-extend
            // (which the previous 32 -> 64 widening emitted on every compare).
            // Two f32 values compare with comiss: widening both to f64 first
            // is exact and changes no answer, NaN included, so it only cost two
            // clears and two conversions per comparison. An integer compared
            // with an f32 still meets it at f64, where every int32 and uint32
            // converts exactly.
            const TypeInfo& promotedType = codeGen.typeMgr().get(promotedTypeRef);
            if (promotedType.isFloat() && promotedType.payloadFloatBitsOr(64) == 32 && (!leftType.isFloat() || !rightType.isFloat()))
                return codeGen.typeMgr().typeF64();

            return promotedTypeRef;
        }

        return leftTypeRef;
    }

    void loadCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        const TypeInfo& operandType            = codeGen.typeMgr().get(operandTypeRef);
        outReg                                 = codeGen.nextVirtualRegisterForType(operandTypeRef, operandType);
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
            CodeGenIntegerConversion::convertOperand(codeGen, outReg, srcType, srcBits, dstBits);
            return;
        }

        if (srcType.isIntLike() && dstType.isFloat())
        {
            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef, dstType);
            CodeGenMemoryHelpers::emitConvertIntToFloat(codeGen, dstReg, outReg, srcBits, dstBits, !srcType.isIntSigned());
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            if (srcBits == dstBits)
                return;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef, dstType);
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
        const TypeInfo& declaredType  = codeGen.typeMgr().get(operandTypeRef);
        const TypeInfo* unwrappedType = declaredType.unwrapAliasEnumType(codeGen.ctx());
        const TypeInfo& operandType   = unwrappedType ? *unwrappedType : declaredType;
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
    Result emitSliceCompareBool(CodeGen& codeGen, TypeRef resultTypeRef, TokenId tokId, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, const TypeInfo& sliceType)
    {
        const SymbolFunction* sliceCmpSymbol = preparedRuntimeCompareFunction(codeGen, IdentifierManager::PredefinedName::RuntimeSliceCmp);
        SWC_ASSERT(sliceCmpSymbol != nullptr);
        if (!sliceCmpSymbol)
            return Result::Error;

        const uint64_t elementSize = codeGen.typeMgr().get(sliceType.payloadTypeRef()).sizeOf(codeGen.ctx());

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

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        const MicroReg            argRegs[]     = {leftDataReg, rightDataReg, leftCountReg, rightCountReg, sizeReg};
        SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, *sliceCmpSymbol, argRegs, resultPayload.reg));

        emitContentCompareResult(codeGen, tokId, resultPayload);
        return Result::Continue;
    }

    Result emitStringCompareBool(CodeGen& codeGen, TypeRef resultTypeRef, TokenId tokId, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload)
    {
        SymbolFunction* stringCmpSymbol = preparedRuntimeCompareFunction(codeGen, IdentifierManager::PredefinedName::RuntimeStringCmp);
        SWC_ASSERT(stringCmpSymbol != nullptr);
        if (!stringCmpSymbol)
            return Result::Error;

        auto&         stringCmpFunction = *stringCmpSymbol;
        const auto    callInfo          = CodeGenBinaryValueCall::emit(codeGen, stringCmpFunction, leftPayload, rightPayload);
        MicroBuilder& builder           = codeGen.builder();

        const CodeGenNodePayload&              resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), *callInfo.callConv, codeGen.typeMgr().get(stringCmpFunction.returnTypeRef()), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid);
        SWC_ASSERT(!normalizedRet.isIndirect);
        SWC_ASSERT(normalizedRet.numBits == 8);
        ABICall::materializeReturnToReg(builder, resultPayload.reg, callInfo.callConvKind, normalizedRet);

        emitContentCompareResult(codeGen, tokId, resultPayload);
        return Result::Continue;
    }

    Result emitTypeInfoCompareBool(CodeGen& codeGen, TypeRef resultTypeRef, TokenId tokId, const CodeGenNodePayload& leftPayload, TypeRef leftOperandTypeRef, const CodeGenNodePayload& rightPayload, TypeRef rightOperandTypeRef, TypeRef compareTypeRef)
    {
        MicroReg leftPtrReg, rightPtrReg;
        loadTypeInfoComparePtr(leftPtrReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        loadTypeInfoComparePtr(rightPtrReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
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

        return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid(), relationalPayload.calledFn);
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

    // One step of an aggregate comparison, at an offset from the start of the value. Most of a
    // value is bytes both operands must hold identically, but a member whose type answers '=='
    // its own way — a 'string', a slice, or a struct owning an 'opEquals' — is asked that
    // question instead, so an array gives the same answer its elements give.
    struct ComparePart
    {
        enum class Kind : uint8_t
        {
            Bytes,   // 'size' bytes that must be identical
            Content, // a view of 'size'-wide elements, compared through '__sliceCmp'
            SpecOp,  // a struct, compared through the 'opEquals' it owns
            Array,   // 'count' elements 'size' bytes apart, each compared through 'elemParts'
        };

        Kind                     kind     = Kind::Bytes;
        uint64_t                 offset   = 0;
        uint64_t                 size     = 0;
        uint64_t                 count    = 0;
        SymbolFunction*          equalsFn = nullptr;
        std::vector<ComparePart> elemParts;
    };

    // Past this many elements, an array whose elements are not plain bytes is compared in a loop.
    // Unrolled, every element repeats its helper calls and string compares, and a runtime struct
    // holding a few such arrays grew an equality operator of thousands of instructions.
    constexpr uint64_t K_COMPARE_UNROLLED_ELEMENTS = 4;

    // Past this many sixteen-byte chunks, a byte run is compared in a loop.
    constexpr uint64_t K_COMPARE_UNROLLED_CHUNKS = 8;

    void appendCompareBytes(SmallVector<ComparePart>& out, uint64_t offset, uint64_t size)
    {
        if (!size)
            return;

        // Members follow each other in offset order, so a run that starts where the previous one
        // ended extends it instead of adding a second compare for the same contiguous bytes.
        if (!out.empty() && out.back().kind == ComparePart::Kind::Bytes && out.back().offset + out.back().size == offset)
        {
            out.back().size += size;
            return;
        }

        out.push_back({.kind = ComparePart::Kind::Bytes, .offset = offset, .size = size});
    }

    // Fill 'out' with the steps comparing a value of this type. The padding a layout inserts
    // between and after members is not one of them: two values whose every member is equal must
    // compare equal, and the bytes between the members are not members. A union is the exception
    // — its members share one storage, so all of it is compared.
    void appendCompareParts(CodeGen& codeGen, SmallVector<ComparePart>& out, const TypeInfo& declaredType, uint64_t base)
    {
        TaskContext&    ctx           = codeGen.ctx();
        const TypeInfo* unwrappedType = declaredType.unwrapAliasEnumType(ctx);
        const TypeInfo& type          = unwrappedType ? *unwrappedType : declaredType;
        const uint64_t  size          = type.sizeOf(ctx);

        if (type.isString())
        {
            out.push_back({.kind = ComparePart::Kind::Content, .offset = base, .size = 1});
            return;
        }

        if (type.isSlice())
        {
            out.push_back({.kind = ComparePart::Kind::Content, .offset = base, .size = ctx.typeMgr().get(type.payloadTypeRef()).sizeOf(ctx)});
            return;
        }

        if (type.isStruct())
        {
            const SymbolStruct& ownerStruct = type.payloadSymStruct();
            if (SymbolFunction* equalsFn = ownerStruct.selfEqualsFunction(ctx))
            {
                out.push_back({.kind = ComparePart::Kind::SpecOp, .offset = base, .size = size, .equalsFn = equalsFn});
                return;
            }

            if (ownerStruct.isUnion() || ownerStruct.fields().empty())
            {
                appendCompareBytes(out, base, size);
                return;
            }

            for (const SymbolVariable* field : ownerStruct.fields())
            {
                if (field)
                    appendCompareParts(codeGen, out, ctx.typeMgr().get(field->typeRef()), base + field->offset());
            }

            return;
        }

        if (type.isArray())
        {
            const TypeInfo& elemType = ctx.typeMgr().get(type.payloadArrayElemTypeRef());
            const uint64_t  elemSize = elemType.sizeOf(ctx);
            if (!elemSize)
                return;

            SmallVector<ComparePart> elemParts;
            appendCompareParts(codeGen, elemParts, elemType, 0);

            // An element that occupies all of its own storage leaves the whole array contiguous,
            // which is one compare instead of one per element.
            if (elemParts.size() == 1 && elemParts[0].kind == ComparePart::Kind::Bytes && elemParts[0].offset == 0 && elemParts[0].size == elemSize)
            {
                appendCompareBytes(out, base, size);
                return;
            }

            const uint64_t count = size / elemSize;
            if (count > K_COMPARE_UNROLLED_ELEMENTS)
            {
                ComparePart& arrayPart = out.emplace_back();
                arrayPart.kind         = ComparePart::Kind::Array;
                arrayPart.offset       = base;
                arrayPart.size         = elemSize;
                arrayPart.count        = count;
                arrayPart.elemParts.assign(std::make_move_iterator(elemParts.begin()), std::make_move_iterator(elemParts.end()));
                return;
            }

            for (uint64_t elem = 0; elem < count; ++elem)
            {
                for (const ComparePart& part : elemParts)
                {
                    const uint64_t offset = base + elem * elemSize + part.offset;
                    if (part.kind == ComparePart::Kind::Bytes)
                        appendCompareBytes(out, offset, part.size);
                    else
                        out.emplace_back(part).offset = offset;
                }
            }

            return;
        }

        appendCompareBytes(out, base, size);
    }

    // Sixteen bytes at a time: the packed compare answers every byte at once and the move-mask
    // turns the sixteen lane results into one integer, so a run costs one branch per sixteen
    // bytes instead of one per eight.
    void emitCompareBytesVectorChunk(CodeGen& codeGen, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, uint64_t offset, MicroLabelRef notEqualLabel)
    {
        MicroBuilder&  builder     = codeGen.builder();
        const MicroReg leftVecReg  = codeGen.nextVirtualFloatRegister();
        const MicroReg rightVecReg = codeGen.nextVirtualFloatRegister();
        const MicroReg equalVecReg = codeGen.nextVirtualFloatRegister();
        const MicroReg maskReg     = codeGen.nextVirtualIntRegister();

        builder.emitLoadRegMem(leftVecReg, leftPayload.reg, offset, MicroOpBits::B128);
        builder.emitLoadRegMem(rightVecReg, rightPayload.reg, offset, MicroOpBits::B128);
        builder.emitOpBinaryRegRegReg(equalVecReg, leftVecReg, rightVecReg, MicroOp::VecCmpEq8, MicroOpBits::B128);
        builder.emitVecUnaryRegReg(maskReg, equalVecReg, MicroOp::VecMoveMaskB, MicroOpBits::B128);
        builder.emitCmpRegImm(maskReg, ApInt(0xFFFF, 32), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, notEqualLabel);
    }

    void emitCompareBytesPart(CodeGen& codeGen, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, const ComparePart& part, MicroLabelRef notEqualLabel)
    {
        MicroBuilder& builder = codeGen.builder();

        uint64_t offset = part.offset;
        if (codeGen.buildCfgBackend().optimizes())
        {
            // A long run is walked by a loop over its sixteen-byte chunks: unrolled, a struct of a
            // few kilobytes compiled hundreds of compare blocks for an operator nobody may call.
            const uint64_t chunkCount = part.size / 16;
            if (chunkCount > K_COMPARE_UNROLLED_CHUNKS)
            {
                CodeGenNodePayload leftCursor  = leftPayload;
                CodeGenNodePayload rightCursor = rightPayload;
                leftCursor.reg                 = codeGen.nextVirtualIntRegister();
                rightCursor.reg                = codeGen.nextVirtualIntRegister();
                const MicroReg counterReg      = codeGen.nextVirtualIntRegister();
                builder.emitLoadAddressRegMem(leftCursor.reg, leftPayload.reg, offset, MicroOpBits::B64);
                builder.emitLoadAddressRegMem(rightCursor.reg, rightPayload.reg, offset, MicroOpBits::B64);
                builder.emitLoadRegImm(counterReg, ApInt(chunkCount, 64), MicroOpBits::B64);

                const MicroLabelRef loopLabel = builder.createLabel();
                builder.placeLabel(loopLabel);
                emitCompareBytesVectorChunk(codeGen, leftCursor, rightCursor, 0, notEqualLabel);
                builder.emitOpBinaryRegImm(leftCursor.reg, ApInt(16, 64), MicroOp::Add, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(rightCursor.reg, ApInt(16, 64), MicroOp::Add, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(counterReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
                builder.emitCmpRegImm(counterReg, ApInt(0, 64), MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, loopLabel);
                offset += chunkCount * 16;
            }

            while (part.offset + part.size - offset >= 16)
            {
                emitCompareBytesVectorChunk(codeGen, leftPayload, rightPayload, offset, notEqualLabel);
                offset += 16;
            }
        }

        while (offset < part.offset + part.size)
        {
            const uint64_t remain = part.offset + part.size - offset;

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
    }

    // A helper answering 'true when equal' leaves the aggregate on its equal path.
    void emitJumpWhenPartAnsweredNotEqual(CodeGen& codeGen, MicroReg resultReg, MicroLabelRef notEqualLabel)
    {
        MicroBuilder& builder = codeGen.builder();
        builder.emitCmpRegImm(resultReg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, notEqualLabel);
    }

    // A 'string' and a slice share one layout, so both ask '__sliceCmp' the same question; a
    // string is a view of single bytes.
    Result emitCompareContentPart(CodeGen& codeGen, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, const ComparePart& part, MicroLabelRef notEqualLabel)
    {
        const SymbolFunction* sliceCmpSymbol = preparedRuntimeCompareFunction(codeGen, IdentifierManager::PredefinedName::RuntimeSliceCmp);
        SWC_ASSERT(sliceCmpSymbol != nullptr);
        if (!sliceCmpSymbol)
            return Result::Error;

        MicroBuilder&  builder       = codeGen.builder();
        const MicroReg leftDataReg   = codeGen.nextVirtualIntRegister();
        const MicroReg rightDataReg  = codeGen.nextVirtualIntRegister();
        const MicroReg leftCountReg  = codeGen.nextVirtualIntRegister();
        const MicroReg rightCountReg = codeGen.nextVirtualIntRegister();
        const MicroReg sizeReg       = codeGen.nextVirtualIntRegister();
        const MicroReg resultReg     = codeGen.nextVirtualIntRegister();

        const auto dataOffset  = static_cast<uint32_t>(part.offset + offsetof(Runtime::Slice<std::byte>, ptr));
        const auto countOffset = static_cast<uint32_t>(part.offset + offsetof(Runtime::Slice<std::byte>, count));
        builder.emitLoadRegMem(leftDataReg, leftPayload.reg, dataOffset, MicroOpBits::B64);
        builder.emitLoadRegMem(leftCountReg, leftPayload.reg, countOffset, MicroOpBits::B64);
        builder.emitLoadRegMem(rightDataReg, rightPayload.reg, dataOffset, MicroOpBits::B64);
        builder.emitLoadRegMem(rightCountReg, rightPayload.reg, countOffset, MicroOpBits::B64);
        builder.emitLoadRegImm(sizeReg, ApInt(part.size, 64), MicroOpBits::B64);

        const MicroReg argRegs[] = {leftDataReg, rightDataReg, leftCountReg, rightCountReg, sizeReg};
        SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, *sliceCmpSymbol, argRegs, resultReg));

        emitJumpWhenPartAnsweredNotEqual(codeGen, resultReg, notEqualLabel);
        return Result::Continue;
    }

    Result emitCompareSpecOpPart(CodeGen& codeGen, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, const ComparePart& part, MicroLabelRef notEqualLabel)
    {
        SymbolFunction&    equalsFn     = *part.equalsFn;
        const CallConvKind callConvKind = equalsFn.callConvKind();
        const CallConv&    callConv     = CallConv::get(callConvKind);
        const auto&        params       = equalsFn.parameters();
        SWC_ASSERT(params.size() >= 2);

        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg leftAddrReg  = codeGen.nextVirtualIntRegister();
        const MicroReg rightAddrReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadAddressRegMem(leftAddrReg, leftPayload.reg, part.offset, MicroOpBits::B64);
        builder.emitLoadAddressRegMem(rightAddrReg, rightPayload.reg, part.offset, MicroOpBits::B64);

        CodeGenNodePayload otherPayload;
        otherPayload.reg = rightAddrReg;
        otherPayload.setIsAddress();

        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);
        CodeGenCallHelpers::appendDirectPreparedArg(preparedArgs, codeGen, callConv, params[0]->typeRef(), leftAddrReg);
        CodeGenCallHelpers::appendPreparedValueArg(preparedArgs, codeGen, callConv, otherPayload, params[1]->typeRef());
        CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);

        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (equalsFn.isForeign())
            ABICall::callExtern(builder, callConvKind, &equalsFn, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &equalsFn, preparedCall);
        codeGen.function().addCallDependency(&equalsFn);

        const MicroReg                         resultReg     = codeGen.nextVirtualIntRegister();
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().get(equalsFn.returnTypeRef()), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid && !normalizedRet.isIndirect);
        ABICall::materializeReturnToReg(builder, resultReg, callConvKind, normalizedRet);

        emitJumpWhenPartAnsweredNotEqual(codeGen, resultReg, notEqualLabel);
        return Result::Continue;
    }

    Result emitComparePart(CodeGen& codeGen, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, const ComparePart& part, MicroLabelRef notEqualLabel);

    // One element per iteration: both cursors walk the arrays together and every element part
    // is asked at its offset from the cursor, so the code size no longer grows with the count.
    Result emitCompareArrayPart(CodeGen& codeGen, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, const ComparePart& part, MicroLabelRef notEqualLabel)
    {
        MicroBuilder&      builder     = codeGen.builder();
        CodeGenNodePayload leftCursor  = leftPayload;
        CodeGenNodePayload rightCursor = rightPayload;
        leftCursor.reg                 = codeGen.nextVirtualIntRegister();
        rightCursor.reg                = codeGen.nextVirtualIntRegister();
        const MicroReg counterReg      = codeGen.nextVirtualIntRegister();

        builder.emitLoadAddressRegMem(leftCursor.reg, leftPayload.reg, part.offset, MicroOpBits::B64);
        builder.emitLoadAddressRegMem(rightCursor.reg, rightPayload.reg, part.offset, MicroOpBits::B64);
        builder.emitLoadRegImm(counterReg, ApInt(part.count, 64), MicroOpBits::B64);

        const MicroLabelRef loopLabel = builder.createLabel();
        builder.placeLabel(loopLabel);
        for (const ComparePart& elemPart : part.elemParts)
            SWC_RESULT(emitComparePart(codeGen, leftCursor, rightCursor, elemPart, notEqualLabel));

        builder.emitOpBinaryRegImm(leftCursor.reg, ApInt(part.size, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(rightCursor.reg, ApInt(part.size, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(counterReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(counterReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, loopLabel);
        return Result::Continue;
    }

    Result emitComparePart(CodeGen& codeGen, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, const ComparePart& part, MicroLabelRef notEqualLabel)
    {
        switch (part.kind)
        {
            case ComparePart::Kind::Content:
                return emitCompareContentPart(codeGen, leftPayload, rightPayload, part, notEqualLabel);
            case ComparePart::Kind::SpecOp:
                return emitCompareSpecOpPart(codeGen, leftPayload, rightPayload, part, notEqualLabel);
            case ComparePart::Kind::Array:
                return emitCompareArrayPart(codeGen, leftPayload, rightPayload, part, notEqualLabel);
            default:
                emitCompareBytesPart(codeGen, leftPayload, rightPayload, part, notEqualLabel);
                return Result::Continue;
        }
    }

    // A part that is not a plain byte run needs the aggregate path whatever the value's size,
    // because the scalar compare below can only answer with the storage.
    bool hasOwnAnswerPart(std::span<const ComparePart> parts)
    {
        return std::ranges::any_of(parts, [](const ComparePart& part) { return part.kind != ComparePart::Kind::Bytes; });
    }

    // Compare two address-backed aggregate operands (structs/arrays) for equality, step by step.
    // The scalar compare path only looks at a single register-sized load, which silently ignores
    // every field past the first machine word for aggregates larger than a register.
    Result emitAggregateEqualsBool(CodeGen& codeGen, TypeRef resultTypeRef, TokenId tokId, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload, std::span<const ComparePart> parts)
    {
        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();

        const bool          isEqual       = tokId == TokenId::SymEqualEqual;
        const MicroLabelRef notEqualLabel = builder.createLabel();
        const MicroLabelRef doneLabel     = builder.createLabel();

        for (const ComparePart& part : parts)
            SWC_RESULT(emitComparePart(codeGen, leftPayload, rightPayload, part, notEqualLabel));

        builder.emitLoadRegImm(resultPayload.reg, ApInt(isEqual ? 1 : 0, 32), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        builder.placeLabel(notEqualLabel);
        builder.emitLoadRegImm(resultPayload.reg, ApInt(isEqual ? 0 : 1, 32), MicroOpBits::B32);

        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result emitRelationalBool(CodeGen& codeGen, TypeRef resultTypeRef, const AstRelationalExpr& node, TokenId tokId)
    {
        const CodeGenNodePayload& leftPayload         = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = codeGen.payload(node.nodeRightRef);
        TypeRef                   leftOperandTypeRef  = resolveRelationalOperandTypeRef(codeGen, node.nodeLeftRef, leftPayload);
        TypeRef                   rightOperandTypeRef = resolveRelationalOperandTypeRef(codeGen, node.nodeRightRef, rightPayload);
        SWC_ASSERT(leftOperandTypeRef.isValid());
        SWC_ASSERT(rightOperandTypeRef.isValid());
        CodeGenNodePayload leftOperandPayload  = leftPayload;
        CodeGenNodePayload rightOperandPayload = rightPayload;
        const TypeRef      leftCompareTypeRef  = normalizeScalarReferenceOperand(codeGen, leftOperandPayload, leftOperandTypeRef);
        const TypeRef      rightCompareTypeRef = normalizeScalarReferenceOperand(codeGen, rightOperandPayload, rightOperandTypeRef);

        const TypeRef   compareTypeRef = resolveCompareTypeRef(codeGen, leftCompareTypeRef, rightCompareTypeRef);
        const TypeInfo& compareType    = codeGen.typeMgr().get(compareTypeRef);
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            compareType.isString() &&
            hasPreparedRuntimeContentCompare(codeGen))
            return emitStringCompareBool(codeGen, resultTypeRef, tokId, leftPayload, rightPayload);

        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            compareType.isSlice() &&
            hasPreparedRuntimeContentCompare(codeGen))
            return emitSliceCompareBool(codeGen, resultTypeRef, tokId, leftOperandPayload, rightOperandPayload, compareType);

        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) && compareType.isAnyTypeInfo(codeGen.ctx()))
            return emitTypeInfoCompareBool(codeGen, resultTypeRef, tokId, leftPayload, leftOperandTypeRef, rightPayload, rightOperandTypeRef, compareTypeRef);
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            codeGen.typeMgr().isRuntimeTypeInfoPointer(codeGen.ctx(), leftOperandTypeRef) &&
            codeGen.typeMgr().isRuntimeTypeInfoPointer(codeGen.ctx(), rightOperandTypeRef))
            return emitTypeInfoCompareBool(codeGen, resultTypeRef, tokId, leftPayload, leftOperandTypeRef, rightPayload, rightOperandTypeRef, codeGen.typeMgr().typeTypeInfo());

        // An aggregate (struct/array) wider than a machine register must be compared over its full
        // content. Interfaces compare both their receiver and method table. An aggregate
        // holding a member with an answer of its own must be compared part by
        // part whatever its size. The scalar path below only compares a single register-sized
        // load, which would ignore every field beyond the first machine word and every answer but
        // the storage.
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            (compareType.isStruct() || compareType.isArray() || compareType.isAggregate() || compareType.isInterface()))
        {
            SmallVector<ComparePart> parts;
            appendCompareParts(codeGen, parts, compareType, 0);
            const bool isWiderThanRegister = compareType.sizeOf(codeGen.ctx()) > sizeof(uint64_t);
            if (isWiderThanRegister || hasOwnAnswerPart(parts.span()))
            {
                // Every part reads its operand through an address. A value wider than a register
                // is always memory-backed; a narrower one reaches here only because a member has
                // an answer of its own, and such a member is only ever reached through a place.
                SWC_ASSERT(isWiderThanRegister || (leftOperandPayload.isAddress() && rightOperandPayload.isAddress()));
                return emitAggregateEqualsBool(codeGen, resultTypeRef, tokId, leftOperandPayload, rightOperandPayload, parts.span());
            }
        }

        const MicroOpBits opBits = CodeGenTypeHelpers::compareBits(compareType, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeCompareOperand(leftReg, codeGen, leftOperandPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightOperandPayload, rightOperandTypeRef, compareTypeRef);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        MicroBuilder& builder             = codeGen.builder();
        builder.emitCmpRegReg(leftReg, rightReg, opBits);

        const CodeGenCompareHelpers::CompareCondition condition = buildCompareCondition(tokId, compareType);
        CodeGenCompareHelpers::emitConditionBool(codeGen, resultPayload.reg, compareType, condition);
        return Result::Continue;
    }

    Result emitThreeWayCompare(CodeGen& codeGen, TypeRef resultTypeRef, const AstRelationalExpr& node)
    {
        const CodeGenNodePayload& leftPayload         = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = codeGen.payload(node.nodeRightRef);
        TypeRef                   leftOperandTypeRef  = resolveRelationalOperandTypeRef(codeGen, node.nodeLeftRef, leftPayload);
        TypeRef                   rightOperandTypeRef = resolveRelationalOperandTypeRef(codeGen, node.nodeRightRef, rightPayload);
        SWC_ASSERT(leftOperandTypeRef.isValid());
        SWC_ASSERT(rightOperandTypeRef.isValid());
        CodeGenNodePayload leftOperandPayload  = leftPayload;
        CodeGenNodePayload rightOperandPayload = rightPayload;
        const TypeRef      leftCompareTypeRef  = normalizeScalarReferenceOperand(codeGen, leftOperandPayload, leftOperandTypeRef);
        const TypeRef      rightCompareTypeRef = normalizeScalarReferenceOperand(codeGen, rightOperandPayload, rightOperandTypeRef);

        const TypeRef     compareTypeRef = resolveCompareTypeRef(codeGen, leftCompareTypeRef, rightCompareTypeRef);
        const TypeInfo&   compareType    = codeGen.typeMgr().get(compareTypeRef);
        const MicroOpBits opBits         = CodeGenTypeHelpers::compareBits(compareType, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeCompareOperand(leftReg, codeGen, leftOperandPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightOperandPayload, rightOperandTypeRef, compareTypeRef);

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

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        // `<=>` is reconstructed from two predicates: `left > right` minus `left < right` yields
        // {+1, 0, -1} without needing a dedicated three-way compare opcode.
        builder.emitLoadRegReg(resultPayload.reg, greatReg, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(resultPayload.reg, lessReg, MicroOp::Subtract, MicroOpBits::B32);
        return Result::Continue;
    }

    // Element-wise simd compare: the result is a mask vector, not a bool.
    Result emitRelationalVector(CodeGen& codeGen, TypeRef resultTypeRef, const AstRelationalExpr& node, TokenId tokId)
    {
        const SemaNodeView leftView = codeGen.viewType(node.nodeLeftRef);
        const TypeInfo&    vecType  = SemaHelpers::aliasEnumType(codeGen.sema(), leftView);
        SWC_ASSERT(vecType.isSimd());
        const TypeInfo& laneType = codeGen.typeMgr().get(vecType.payloadSimdLaneTypeRef());

        const MicroReg lhsReg  = CodeGenVectorHelpers::loadVectorOperand(codeGen, codeGen.payload(node.nodeLeftRef));
        const MicroReg rhsReg  = CodeGenVectorHelpers::loadVectorOperand(codeGen, codeGen.payload(node.nodeRightRef));
        const MicroReg maskReg = CodeGenVectorHelpers::emitCompare(codeGen, tokId, lhsReg, rhsReg, laneType);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = maskReg;
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
        const auto& calledFn = *relationalPayload->calledFn;
        if (calledFn.specOpKind() == SpecOpKind::OpEquals || calledFn.specOpKind() == SpecOpKind::OpCompare)
            return emitSpecialRelational(codeGen, tok.id, calledFn, resultTypeRef, *relationalPayload);
    }

    const SemaNodeView resultView    = codeGen.curViewType();
    const TypeRef      resultTypeRef = resultView.typeRef();
    if (resultView.type() && resultView.type()->isSimd())
        return emitRelationalVector(codeGen, resultTypeRef, *this, tok.id);

    if (tok.id == TokenId::SymLessEqualGreater)
        return emitThreeWayCompare(codeGen, resultTypeRef, *this);

    SWC_INTERNAL_CHECK(Token::isOpRelational(tok.id));
    return emitRelationalBool(codeGen, resultTypeRef, *this, tok.id);
}

SWC_END_NAMESPACE();
