#include <utility>

#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenReferenceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Index.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef unwrapAliasTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return typeRef;

        const TypeRef unwrappedTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (unwrappedTypeRef.isValid())
            return unwrappedTypeRef;

        return typeRef;
    }

    TypeRef normalizeIndexOperandTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeRef normalizedTypeRef = unwrapAliasTypeRef(codeGen, typeRef);
        if (!normalizedTypeRef.isValid())
            return normalizedTypeRef;

        const TypeInfo& normalizedType = codeGen.typeMgr().get(normalizedTypeRef);
        if (normalizedType.isEnum() && normalizedType.payloadSymEnum().attributes().hasRtFlag(RtAttributeFlagsE::EnumIndex))
            return normalizedType.payloadSymEnum().underlyingTypeRef();

        return normalizedTypeRef;
    }

    MicroReg copyAddressBaseReg(CodeGen& codeGen, const MicroReg baseReg)
    {
        MicroBuilder& builder = codeGen.builder();
        const auto    copyReg = codeGen.nextVirtualIntRegister();
        if (baseReg.isInt())
            builder.addVirtualRegForbiddenPhysReg(copyReg, baseReg);
        builder.emitLoadRegReg(copyReg, baseReg, MicroOpBits::B64);
        return copyReg;
    }

    void emitCStringCountReg(CodeGen& codeGen, MicroReg countReg, MicroReg cstrReg)
    {
        MicroBuilder& builder = codeGen.builder();
        builder.emitClearReg(countReg, MicroOpBits::B64);

        const MicroLabelRef loopLabel = builder.createLabel();
        const MicroLabelRef doneLabel = builder.createLabel();
        builder.emitCmpRegImm(cstrReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

        const MicroReg scanReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(scanReg, cstrReg, MicroOpBits::B64);
        builder.placeLabel(loopLabel);

        const MicroReg charReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(charReg, scanReg, 0, MicroOpBits::B8);
        builder.emitCmpRegImm(charReg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
        builder.emitOpBinaryRegImm(scanReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopLabel);
        builder.placeLabel(doneLabel);
    }

    void normalizeIndexReferenceOperand(CodeGen& codeGen, CodeGenNodePayload& ioPayload, TypeRef& ioTypeRef)
    {
        const TypeRef normalizedTypeRef = normalizeIndexOperandTypeRef(codeGen, ioTypeRef);
        if (!normalizedTypeRef.isValid())
            return;

        const TypeInfo& normalizedType = codeGen.typeMgr().get(normalizedTypeRef);
        if (!normalizedType.isReference())
        {
            ioTypeRef = normalizedTypeRef;
            return;
        }

        const TypeRef payloadTypeRef = normalizedType.payloadTypeRef();
        if (!codeGen.typeMgr().get(payloadTypeRef).isInt())
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
        codeGen.builder().emitLoadRegMem(ioPayload.reg, referenceSlotReg, 0, MicroOpBits::B64);
        ioPayload.setIsAddress();
    }

    MicroReg materializeIndexReg(CodeGen& codeGen, AstNodeRef indexRef, MicroOpBits& outIndexBits)
    {
        const CodeGenNodePayload& rawIndexPayload = codeGen.payload(indexRef);
        const SemaNodeView        indexView       = codeGen.viewType(indexRef);
        SWC_ASSERT(indexView.type());

        CodeGenNodePayload indexPayload = rawIndexPayload;
        TypeRef            indexTypeRef = indexPayload.effectiveTypeRef(indexView.typeRef());
        normalizeIndexReferenceOperand(codeGen, indexPayload, indexTypeRef);

        const TypeInfo& indexType = codeGen.typeMgr().get(indexTypeRef);
        outIndexBits              = CodeGenTypeHelpers::copyBits(indexType);
        const bool indexSigned    = indexType.isIntSigned();

        if (outIndexBits == MicroOpBits::B64 && indexPayload.isValue())
            return indexPayload.reg;

        const MicroReg indexReg = codeGen.nextVirtualIntRegister();
        MicroBuilder&  builder  = codeGen.builder();
        if (indexPayload.isAddress())
        {
            if (outIndexBits == MicroOpBits::B64)
                builder.emitLoadRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64);
            else if (indexSigned)
                builder.emitLoadSignedExtendRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64, outIndexBits);
            else
                builder.emitLoadZeroExtendRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64, outIndexBits);
        }
        else
        {
            if (indexSigned)
                builder.emitLoadSignedExtendRegReg(indexReg, indexPayload.reg, MicroOpBits::B64, outIndexBits);
            else
                builder.emitLoadZeroExtendRegReg(indexReg, indexPayload.reg, MicroOpBits::B64, outIndexBits);
        }

        outIndexBits = MicroOpBits::B64;
        return indexReg;
    }

    MicroReg materializeAddressFromValue(CodeGen& codeGen, AstNodeRef payloadNodeRef, const CodeGenNodePayload& payload, const TypeInfo& typeInfo)
    {
        MicroBuilder&  builder     = codeGen.builder();
        const uint64_t sizeOfValue = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOfValue > 0);

        if (sizeOfValue != 1 && sizeOfValue != 2 && sizeOfValue != 4 && sizeOfValue != 8)
            return payload.reg;

        AstNodeRef spillOwnerRef = codeGen.curNodeRef();
        if (payloadNodeRef.isValid())
        {
            const CodeGenNodePayload* spillPayload = codeGen.safePayload(payloadNodeRef);
            if (spillPayload && spillPayload->runtimeStorageSym != nullptr)
                spillOwnerRef = payloadNodeRef;
        }

        // When the source expression already owns a storage slot, spill there first so the destination node
        // can keep its own runtime storage for the index/slice result.
        const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(spillOwnerRef);
        builder.emitLoadMemReg(spillAddrReg, 0, payload.reg, CodeGenTypeHelpers::bitsFromStorageSize(sizeOfValue));
        return spillAddrReg;
    }

    MicroReg resolveIndexBaseAddress(CodeGen& codeGen, AstNodeRef indexedNodeRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload)
    {
        MicroBuilder& builder = codeGen.builder();

        if (indexedType.isArray())
        {
            if (indexedPayload.isAddress())
                return indexedPayload.reg;
            return materializeAddressFromValue(codeGen, indexedNodeRef, indexedPayload, indexedType);
        }

        if (indexedType.isAnyPointer() || indexedType.isCString())
        {
            if (indexedPayload.isValue())
                return indexedPayload.reg;

            const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(pointerReg, indexedPayload.reg, 0, MicroOpBits::B64);
            return pointerReg;
        }

        if (indexedType.isString() || indexedType.isSlice() || indexedType.isVariadic() || indexedType.isTypedVariadic())
        {
            const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(pointerReg, indexedPayload.reg, offsetof(Runtime::Slice<std::byte>, ptr), MicroOpBits::B64);
            return pointerReg;
        }

        SWC_UNREACHABLE();
    }

    uint64_t resolveIndexStrideSize(CodeGen& codeGen, const TypeInfo& indexedType)
    {
        TypeManager& typeMgr = codeGen.sema().typeMgr();
        if (indexedType.isArray())
        {
            const auto& dims       = indexedType.payloadArrayDims();
            const auto  elementRef = indexedType.payloadArrayElemTypeRef();
            if (dims.size() <= 1)
                return typeMgr.get(elementRef).sizeOf(codeGen.ctx());

            SmallVector<uint64_t> remainingDims;
            remainingDims.reserve(dims.size() - 1);
            for (size_t i = 1; i < dims.size(); ++i)
                remainingDims.push_back(dims[i]);

            const TypeRef strideTypeRef = typeMgr.addType(TypeInfo::makeArray(remainingDims.span(), elementRef, indexedType.flags()));
            return typeMgr.get(strideTypeRef).sizeOf(codeGen.ctx());
        }

        if (indexedType.isPointerOrReference() || indexedType.isSlice() || indexedType.isTypedVariadic())
            return typeMgr.get(indexedType.payloadTypeRef()).sizeOf(codeGen.ctx());
        if (indexedType.isString() || indexedType.isCString())
            return typeMgr.get(typeMgr.typeU8()).sizeOf(codeGen.ctx());
        if (indexedType.isVariadic())
            return typeMgr.get(typeMgr.typeAny()).sizeOf(codeGen.ctx());

        SWC_UNREACHABLE();
    }

    TypeRef resolveIndexedResultTypeRef(CodeGen& codeGen, const TypeInfo& indexedType)
    {
        TypeManager& typeMgr = codeGen.sema().typeMgr();
        if (indexedType.isArray())
        {
            const auto& dims = indexedType.payloadArrayDims();
            if (dims.size() <= 1)
                return indexedType.payloadArrayElemTypeRef();

            SmallVector<uint64_t> remainingDims;
            remainingDims.reserve(dims.size() - 1);
            for (size_t i = 1; i < dims.size(); ++i)
                remainingDims.push_back(dims[i]);

            return typeMgr.addType(TypeInfo::makeArray(remainingDims.span(), indexedType.payloadArrayElemTypeRef(), indexedType.flags()));
        }

        if (indexedType.isPointerOrReference() || indexedType.isSlice() || indexedType.isTypedVariadic())
            return indexedType.payloadTypeRef();
        if (indexedType.isString() || indexedType.isCString())
            return typeMgr.typeU8();
        if (indexedType.isVariadic())
            return typeMgr.typeAny();

        SWC_UNREACHABLE();
    }

    bool resolveAggregateArrayConstIndexInfo(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, uint32_t& outOffset, TypeRef& outResultTypeRef)
    {
        outOffset        = 0;
        outResultTypeRef = TypeRef::invalid();
        if (!indexedType.isAggregateArray())
            return false;

        const SemaNodeView indexView = codeGen.viewConstant(indexRef);
        if (indexView.cstRef().isInvalid())
            return false;

        const ConstantValue& indexCst = codeGen.cstMgr().get(indexView.cstRef());
        if (!codeGen.typeMgr().get(indexCst.typeRef()).isIntLike())
            return false;

        const int64_t constIndex = indexCst.getIntLike().asI64();
        if (constIndex < 0)
            return false;

        const auto& aggregateTypes = indexedType.payloadAggregate().types;
        if (std::cmp_greater_equal(constIndex, aggregateTypes.size()))
            return false;

        uint64_t offset = 0;
        for (size_t i = 0; i < aggregateTypes.size(); ++i)
        {
            const TypeInfo& elemType  = codeGen.typeMgr().get(aggregateTypes[i]);
            const uint32_t  elemAlign = std::max<uint32_t>(elemType.alignOf(codeGen.ctx()), 1);
            const uint64_t  elemSize  = elemType.sizeOf(codeGen.ctx());
            if (elemSize)
                offset = ((offset + static_cast<uint64_t>(elemAlign) - 1) / static_cast<uint64_t>(elemAlign)) * static_cast<uint64_t>(elemAlign);

            if (std::cmp_equal(i, constIndex))
            {
                SWC_ASSERT(offset <= std::numeric_limits<uint32_t>::max());
                outOffset        = static_cast<uint32_t>(offset);
                outResultTypeRef = aggregateTypes[i];
                return true;
            }

            offset += elemSize;
        }

        return false;
    }

    Result emitAggregateArrayConstIndexAddress(CodeGen& codeGen, CodeGenNodePayload& outPayload, AstNodeRef indexedNodeRef, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload)
    {
        uint32_t   fieldOffset   = 0;
        TypeRef    resultTypeRef = TypeRef::invalid();
        const bool hasConstInfo  = resolveAggregateArrayConstIndexInfo(codeGen, indexRef, indexedType, fieldOffset, resultTypeRef);
        SWC_ASSERT(hasConstInfo);
        SWC_ASSERT(resultTypeRef.isValid());

        MicroReg baseReg = indexedPayload.reg;
        if (!indexedPayload.isAddress())
        {
            const uint64_t sizeOfValue = indexedType.sizeOf(codeGen.ctx());
            SWC_ASSERT(sizeOfValue > 0);
            if (sizeOfValue == 1 || sizeOfValue == 2 || sizeOfValue == 4 || sizeOfValue == 8)
                baseReg = materializeAddressFromValue(codeGen, indexedNodeRef, indexedPayload, indexedType);
            else
                SWC_UNREACHABLE();
        }

        outPayload.typeRef = resultTypeRef;
        outPayload.setIsAddress();
        outPayload.reg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadAddressRegMem(outPayload.reg, baseReg, fieldOffset, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitIndexAddress(CodeGen& codeGen, CodeGenNodePayload& outPayload, AstNodeRef indexedNodeRef, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, TypeRef resultTypeRef)
    {
        auto           indexBits = MicroOpBits::B64;
        const MicroReg indexReg  = materializeIndexReg(codeGen, indexRef, indexBits);
        SWC_RESULT(CodeGenSafety::emitBoundCheck(codeGen, indexRef, indexedType, indexedPayload, indexReg));
        MicroReg baseReg = resolveIndexBaseAddress(codeGen, indexedNodeRef, indexedType, indexedPayload);

        if (indexedType.isArray() && indexedPayload.isAddress())
        {
            const CodeGenNodePayload& indexPayload = codeGen.payload(indexRef);
            if (indexPayload.isAddress())
                baseReg = copyAddressBaseReg(codeGen, baseReg);
        }

        // Multidimensional indexing is just repeated address computation with the stride of the current
        // element type.
        const uint64_t resultSize = resolveIndexStrideSize(codeGen, indexedType);
        SWC_ASSERT(resultSize > 0);

        outPayload.typeRef = resultTypeRef;
        outPayload.setIsAddress();
        outPayload.reg        = codeGen.nextVirtualIntRegister();
        MicroBuilder& builder = codeGen.builder();
        builder.emitLoadAddressAmcRegMem(outPayload.reg, MicroOpBits::B64, baseReg, indexReg, resultSize, 0, indexBits);
        return Result::Continue;
    }

    Result emitSliceValue(CodeGen& codeGen, const AstIndexExpr& node)
    {
        const auto* slicePayload = codeGen.sema().semaPayload<SliceIndexSemaPayload>(codeGen.curNodeRef());
        SWC_ASSERT(slicePayload != nullptr);

        CodeGenNodePayload indexedPayload = codeGen.payload(node.nodeExprRef);
        const SemaNodeView indexedView    = codeGen.viewType(node.nodeExprRef);
        TypeRef            indexedTypeRef = indexedPayload.effectiveTypeRef(indexedView.typeRef());
        CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, indexedPayload, indexedTypeRef);
        const SemaNodeView resultView = codeGen.curViewType();
        SWC_ASSERT(indexedView.type());
        SWC_ASSERT(resultView.type());

        const TypeInfo& indexedType = codeGen.typeMgr().get(indexedTypeRef);
        const TypeInfo& resultType  = *resultView.type();
        MicroBuilder&   builder     = codeGen.builder();

        const MicroReg baseReg = resolveIndexBaseAddress(codeGen, node.nodeExprRef, indexedType, indexedPayload);

        const MicroReg lowReg = codeGen.nextVirtualIntRegister();
        if (slicePayload->lowerBoundRef.isValid())
        {
            auto       lowBits   = MicroOpBits::B64;
            const auto rawLowReg = materializeIndexReg(codeGen, slicePayload->lowerBoundRef, lowBits);
            builder.emitLoadRegReg(lowReg, rawLowReg, MicroOpBits::B64);
        }
        else
        {
            builder.emitLoadRegImm(lowReg, ApInt(0, 64), MicroOpBits::B64);
        }

        const MicroReg endExclusiveReg = codeGen.nextVirtualIntRegister();
        if (slicePayload->upperBoundRef.isValid())
        {
            auto       upBits   = MicroOpBits::B64;
            const auto rawUpReg = materializeIndexReg(codeGen, slicePayload->upperBoundRef, upBits);
            builder.emitLoadRegReg(endExclusiveReg, rawUpReg, MicroOpBits::B64);
            if (slicePayload->inclusive)
                builder.emitOpBinaryRegImm(endExclusiveReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        }
        else if (indexedType.isArray())
        {
            const uint64_t count = indexedType.payloadArrayDims().empty() ? 0 : indexedType.payloadArrayDims()[0];
            builder.emitLoadRegImm(endExclusiveReg, ApInt(count, 64), MicroOpBits::B64);
        }
        else if (indexedType.isString())
        {
            builder.emitLoadRegMem(endExclusiveReg, indexedPayload.reg, offsetof(Runtime::String, length), MicroOpBits::B64);
        }
        else if (indexedType.isCString())
        {
            emitCStringCountReg(codeGen, endExclusiveReg, baseReg);
        }
        else if (indexedType.isSlice())
        {
            builder.emitLoadRegMem(endExclusiveReg, indexedPayload.reg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
        }
        else
        {
            SWC_UNREACHABLE();
        }

        const uint64_t strideSize = resolveIndexStrideSize(codeGen, indexedType);
        const MicroReg dataReg    = codeGen.nextVirtualIntRegister();
        builder.emitLoadAddressAmcRegMem(dataReg, MicroOpBits::B64, baseReg, lowReg, strideSize, 0, MicroOpBits::B64);

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(countReg, endExclusiveReg, MicroOpBits::B64);
        builder.emitOpBinaryRegReg(countReg, lowReg, MicroOp::Subtract, MicroOpBits::B64);

        const MicroReg runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, ptr), dataReg, MicroOpBits::B64);

        const uint32_t countOffset = resultType.isString() ? offsetof(Runtime::String, length) : offsetof(Runtime::Slice<std::byte>, count);
        builder.emitLoadMemReg(runtimeValueReg, countOffset, countReg, MicroOpBits::B64);

        CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultView.typeRef());
        payload.reg                 = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(payload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result materializeSliceSpecOpBoundReg(MicroReg& outReg, CodeGen& codeGen, const SliceSpecOpSemaPayload& specOpPayload, bool upperBound)
    {
        MicroBuilder& builder = codeGen.builder();
        if (!upperBound)
        {
            outReg = codeGen.nextVirtualIntRegister();
            if (!specOpPayload.lowerBoundRef.isValid())
            {
                builder.emitLoadRegImm(outReg, ApInt(0, 64), MicroOpBits::B64);
                return Result::Continue;
            }

            auto       lowerBits = MicroOpBits::B64;
            const auto lowerReg  = materializeIndexReg(codeGen, specOpPayload.lowerBoundRef, lowerBits);
            builder.emitLoadRegReg(outReg, lowerReg, MicroOpBits::B64);
            return Result::Continue;
        }

        outReg = codeGen.nextVirtualIntRegister();
        if (specOpPayload.upperBoundRef.isValid())
        {
            auto       upperBits = MicroOpBits::B64;
            const auto upperReg  = materializeIndexReg(codeGen, specOpPayload.upperBoundRef, upperBits);
            builder.emitLoadRegReg(outReg, upperReg, MicroOpBits::B64);
            if (!specOpPayload.inclusive)
                builder.emitOpBinaryRegImm(outReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
            return Result::Continue;
        }

        SWC_ASSERT(specOpPayload.countFn != nullptr);
        SmallVector<ResolvedCallArgument> resolvedArgs;
        codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), resolvedArgs);
        SWC_ASSERT(!resolvedArgs.empty());
        ResolvedCallArgument receiverArg = resolvedArgs.front();

        SWC_RESULT(CodeGenCallHelpers::emitCallWithResolvedArgsToReg(codeGen, codeGen.curNodeRef(), *specOpPayload.countFn, std::span<const ResolvedCallArgument>(&receiverArg, 1), outReg));
        builder.emitOpBinaryRegImm(outReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        return Result::Continue;
    }

    Result materializeSliceSpecOpArgPayloads(CodeGen& codeGen, const SliceSpecOpSemaPayload& specOpPayload)
    {
        const TypeRef u64TypeRef = codeGen.typeMgr().typeU64();
        MicroReg      lowerReg   = MicroReg::invalid();
        MicroReg      upperReg   = MicroReg::invalid();
        SWC_RESULT(materializeSliceSpecOpBoundReg(lowerReg, codeGen, specOpPayload, false));
        SWC_RESULT(materializeSliceSpecOpBoundReg(upperReg, codeGen, specOpPayload, true));

        CodeGenNodePayload& lowerPayload = codeGen.setPayloadValue(specOpPayload.lowerArgRef, u64TypeRef);
        lowerPayload.reg                 = lowerReg;

        CodeGenNodePayload& upperPayload = codeGen.setPayloadValue(specOpPayload.upperArgRef, u64TypeRef);
        upperPayload.reg                 = upperReg;
        return Result::Continue;
    }

    Result emitIndexSpecOpCall(CodeGen& codeGen, SymbolFunction& calledFn)
    {
        const TypeRef semanticTypeRef = codeGen.curViewType().typeRef();
        const bool    wasLValue       = codeGen.sema().isLValue(codeGen.curNodeRef());

        codeGen.sema().setSymbol(codeGen.curNodeRef(), &calledFn);
        SWC_RESULT(CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid()));
        codeGen.sema().setType(codeGen.curNodeRef(), semanticTypeRef);
        if (wasLValue)
            codeGen.sema().setIsLValue(codeGen.curNodeRef());
        else
            codeGen.sema().unsetIsLValue(codeGen.curNodeRef());

        const TypeInfo& returnType = codeGen.typeMgr().get(calledFn.returnTypeRef());
        if (returnType.isReference())
        {
            const CodeGenNodePayload& callPayload = codeGen.payload(codeGen.curNodeRef());
            codeGen.setPayloadAddressReg(codeGen.curNodeRef(), callPayload.reg, semanticTypeRef);
        }

        return Result::Continue;
    }
}

Result AstIndexExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* payloadBase = codeGen.sema().semaPayload<IndexSpecOpPayloadBase>(codeGen.curNodeRef());
    if (payloadBase && payloadBase->kind == IndexSpecOpPayloadKind::DeferredAssign)
        return Result::Continue;

    SymbolFunction* calledFn = nullptr;
    if (payloadBase && payloadBase->kind == IndexSpecOpPayloadKind::Read)
    {
        const auto* specOpPayload = reinterpret_cast<const IndexSpecOpSemaPayload*>(payloadBase);
        calledFn                  = specOpPayload->calledFn;
    }
    else if (payloadBase && payloadBase->kind == IndexSpecOpPayloadKind::ReadSlice)
    {
        const auto* specOpPayload = reinterpret_cast<const SliceSpecOpSemaPayload*>(payloadBase);
        calledFn                  = specOpPayload->calledFn;
        SWC_RESULT(materializeSliceSpecOpArgPayloads(codeGen, *specOpPayload));
    }
    else
    {
        const SemaNodeView symView = codeGen.curViewSymbol();
        if (symView.sym() && symView.sym()->isFunction())
        {
            calledFn = &symView.sym()->cast<SymbolFunction>();
        }
        else
        {
            const SemaNodeView storedSymView(codeGen.sema(), codeGen.curNodeRef(), SemaNodeViewPartE::Symbol, SemaNodeViewResolveE::Stored);
            if (storedSymView.sym() && storedSymView.sym()->isFunction())
                calledFn = &storedSymView.sym()->cast<SymbolFunction>();
        }
    }

    if (codeGen.node(nodeArgRef).is(AstNodeId::RangeExpr) && (!payloadBase || payloadBase->kind != IndexSpecOpPayloadKind::ReadSlice))
        return emitSliceValue(codeGen, *this);

    if (calledFn != nullptr)
        return emitIndexSpecOpCall(codeGen, *calledFn);

    CodeGenNodePayload indexedPayload = codeGen.payload(nodeExprRef);
    const SemaNodeView indexedView    = codeGen.viewType(nodeExprRef);
    TypeRef            indexedTypeRef = indexedPayload.effectiveTypeRef(indexedView.typeRef());
    CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, indexedPayload, indexedTypeRef);
    const SemaNodeView resultView = codeGen.curViewType();

    SWC_ASSERT(indexedView.type());
    SWC_ASSERT(resultView.type());

    const TypeInfo& indexedType = codeGen.typeMgr().get(indexedTypeRef);
    if (indexedType.isAggregateArray())
    {
        CodeGenNodePayload indexedResultPayload;
        SWC_RESULT(emitAggregateArrayConstIndexAddress(codeGen, indexedResultPayload, nodeExprRef, nodeArgRef, indexedType, indexedPayload));
        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), indexedResultPayload.reg, indexedResultPayload.typeRef);
        return Result::Continue;
    }

    const TypeRef      resultTypeRef = resolveIndexedResultTypeRef(codeGen, indexedType);
    CodeGenNodePayload indexedResultPayload;
    SWC_RESULT(emitIndexAddress(codeGen, indexedResultPayload, nodeExprRef, nodeArgRef, indexedType, indexedPayload, resultTypeRef));
    codeGen.setPayloadAddressReg(codeGen.curNodeRef(), indexedResultPayload.reg, resultTypeRef);
    return Result::Continue;
}

Result AstIndexListExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* payloadBase = codeGen.sema().semaPayload<IndexSpecOpPayloadBase>(codeGen.curNodeRef());
    if (payloadBase && payloadBase->kind == IndexSpecOpPayloadKind::DeferredAssign)
        return Result::Continue;

    SymbolFunction* calledFn = nullptr;
    if (payloadBase && payloadBase->kind == IndexSpecOpPayloadKind::Read)
    {
        const auto* specOpPayload = reinterpret_cast<const IndexSpecOpSemaPayload*>(payloadBase);
        calledFn                  = specOpPayload->calledFn;
    }
    else
    {
        const SemaNodeView symView = codeGen.curViewSymbol();
        if (symView.sym() && symView.sym()->isFunction())
        {
            calledFn = &symView.sym()->cast<SymbolFunction>();
        }
        else
        {
            const SemaNodeView storedSymView(codeGen.sema(), codeGen.curNodeRef(), SemaNodeViewPartE::Symbol, SemaNodeViewResolveE::Stored);
            if (storedSymView.sym() && storedSymView.sym()->isFunction())
                calledFn = &storedSymView.sym()->cast<SymbolFunction>();
        }
    }

    if (calledFn != nullptr)
        return emitIndexSpecOpCall(codeGen, *calledFn);

    SmallVector<AstNodeRef> indexRefs;
    codeGen.ast().appendNodes(indexRefs, spanChildrenRef);
    SWC_ASSERT(!indexRefs.empty());

    TypeRef currentTypeRef = codeGen.viewType(nodeExprRef).typeRef();
    SWC_ASSERT(currentTypeRef.isValid());

    CodeGenNodePayload currentPayload = codeGen.payload(nodeExprRef);
    CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, currentPayload, currentTypeRef);
    AstNodeRef currentSourceRef = nodeExprRef;
    for (const AstNodeRef indexRef : indexRefs)
    {
        const TypeInfo& currentType = codeGen.typeMgr().get(currentTypeRef);

        if (currentType.isAggregateArray())
        {
            SWC_RESULT(emitAggregateArrayConstIndexAddress(codeGen, currentPayload, currentSourceRef, indexRef, currentType, currentPayload));
            currentTypeRef   = currentPayload.typeRef;
            currentSourceRef = AstNodeRef::invalid();
            continue;
        }

        const TypeRef nextTypeRef = resolveIndexedResultTypeRef(codeGen, currentType);
        SWC_RESULT(emitIndexAddress(codeGen, currentPayload, currentSourceRef, indexRef, currentType, currentPayload, nextTypeRef));
        currentTypeRef   = nextTypeRef;
        currentSourceRef = AstNodeRef::invalid();
    }

    codeGen.setPayloadAddressReg(codeGen.curNodeRef(), currentPayload.reg, currentTypeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
