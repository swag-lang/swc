#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenInterfaceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenReferenceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using CodeGenInterfaceHelpers::InterfaceCastInfo;

    MicroReg emitUnsignedIntToFloatReg(CodeGen& codeGen, MicroReg srcReg, const TypeInfo& srcType, TypeRef dstTypeRef);

    bool isExplicitBitCast(const CodeGen& codeGen)
    {
        const AstNode& node = codeGen.node(codeGen.curNodeRef());
        return node.is(AstNodeId::CastExpr) && node.cast<AstCastExpr>().modifierFlags.has(AstModifierFlagsE::Bit);
    }

    uint64_t sliceCountFromArrayCast(CodeGen& codeGen, const TypeInfo& srcArrayType, const TypeInfo& dstElementType)
    {
        const uint64_t dstElementSize = dstElementType.sizeOf(codeGen.ctx());
        if (dstElementSize)
            return srcArrayType.sizeOf(codeGen.ctx()) / dstElementSize;

        uint64_t totalCount = 1;
        for (const uint64_t dim : srcArrayType.payloadArrayDims())
            totalCount *= dim;
        return totalCount;
    }

    TypeRef sliceCastSourceArrayTypeRef(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef srcTypeRef, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        if (srcType.isArray())
            return srcTypeRef;
        if (!srcType.isAggregateArray())
            return TypeRef::invalid();

        const SymbolVariable* storageSym = codeGen.runtimeStorageSymbol(srcNodeRef);
        if (!storageSym || storageSym->typeRef().isInvalid())
            return TypeRef::invalid();

        const TypeRef   storageTypeRef = storageSym->typeRef();
        const TypeInfo& storageType    = codeGen.typeMgr().get(storageTypeRef);
        if (!storageType.isArray())
        {
            const auto& elemTypes = srcType.payloadAggregate().types;
            for (const TypeRef elemTypeRef : elemTypes)
            {
                if (elemTypeRef != dstType.payloadTypeRef())
                    return TypeRef::invalid();
            }

            SmallVector4<uint64_t> dims;
            dims.push_back(elemTypes.size());
            return codeGen.typeMgr().addType(TypeInfo::makeArray(dims, dstType.payloadTypeRef()));
        }

        return storageTypeRef;
    }

    using CodeGenInterfaceHelpers::loadInterfaceMethodTableAddress;
    using CodeGenInterfaceHelpers::resolveInterfaceCastInfo;

    bool anyCastAsValueBits(CodeGen& codeGen, TypeRef typeRef, MicroOpBits& outBits)
    {
        if (!typeRef.isValid())
        {
            outBits = MicroOpBits::Zero;
            return false;
        }

        const TypeRef storageTypeRef = codeGen.typeMgr().get(typeRef).unwrapAliasEnum(codeGen.ctx(), typeRef);
        if (!storageTypeRef.isValid())
        {
            outBits = MicroOpBits::Zero;
            return false;
        }

        const TypeInfo& storageType = codeGen.typeMgr().get(storageTypeRef);
        outBits                     = CodeGenTypeHelpers::scalarStoreBits(storageType, codeGen.ctx());
        return outBits != MicroOpBits::Zero;
    }

    TypeRef unwrapAliasEnumTypeRef(const TypeManager& typeMgr, const TaskContext& ctx, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeRef unwrappedTypeRef = typeMgr.get(typeRef).unwrapAliasEnum(ctx, typeRef);
        if (unwrappedTypeRef.isValid())
            return unwrappedTypeRef;

        return typeRef;
    }

    TypeRef interfaceObjectStructTypeRef(CodeGen& codeGen, TypeRef sourceTypeRef)
    {
        const TypeRef resolvedSourceTypeRef = unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), sourceTypeRef);
        if (!resolvedSourceTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& sourceType = codeGen.typeMgr().get(resolvedSourceTypeRef);
        if (sourceType.isStruct())
            return resolvedSourceTypeRef;

        if (!sourceType.isAnyPointer() && !sourceType.isReference() && !sourceType.isMoveReference())
            return TypeRef::invalid();

        const TypeRef objectTypeRef = unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), sourceType.payloadTypeRef());
        if (!objectTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& objectType = codeGen.typeMgr().get(objectTypeRef);
        if (!objectType.isStruct())
            return TypeRef::invalid();

        return objectTypeRef;
    }

    MicroReg materializePointerLikeInterfaceObjectReg(CodeGen& codeGen, const CodeGenNodePayload& srcPayload)
    {
        if (!srcPayload.isAddress())
            return srcPayload.reg;

        const MicroReg objectReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(objectReg, srcPayload.reg, 0, MicroOpBits::B64);
        return objectReg;
    }

    CodeGenNodePayload sourcePayloadForCast(CodeGen& codeGen, AstNodeRef srcNodeRef)
    {
        if (codeGen.resolvedNodeRef(srcNodeRef) == codeGen.curNodeRef())
        {
            const auto* payload = codeGen.safeNodePayload<CodeGenNodePayload>(srcNodeRef);
            if (payload && payload->reg.isValid())
                return *payload;
        }

        return codeGen.payload(srcNodeRef);
    }

    MicroReg materializeArrayCastSourceAddress(CodeGen& codeGen, AstNodeRef srcNodeRef, const CodeGenNodePayload& srcPayload, const TypeInfo& srcType)
    {
        if (srcPayload.isAddress())
            return srcPayload.reg;

        const uint64_t sourceSize = srcType.sizeOf(codeGen.ctx());
        if (sourceSize != 1 && sourceSize != 2 && sourceSize != 4 && sourceSize != 8)
            return srcPayload.reg;

        AstNodeRef spillOwnerRef = codeGen.curNodeRef();
        if (const CodeGenNodePayload* spillPayload = codeGen.safePayload(srcNodeRef))
        {
            if (spillPayload->runtimeStorageSym != nullptr)
                spillOwnerRef = srcNodeRef;
        }

        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(spillOwnerRef);
        builder.emitLoadMemReg(spillAddrReg, 0, srcPayload.reg, CodeGenTypeHelpers::bitsFromStorageSize(sourceSize));
        return spillAddrReg;
    }

    bool usingPathHasPointerStep(const SmallVector<SymbolStructUsingPathStep>& usingPath)
    {
        for (const auto& step : usingPath)
        {
            if (step.isPointer)
                return true;
        }

        return false;
    }

    bool resolveUsingStructCastPath(CodeGen& codeGen, TypeRef srcStructTypeRef, TypeRef dstStructTypeRef, SmallVector<SymbolStructUsingPathStep>& outSteps)
    {
        outSteps.clear();
        const TypeManager& typeMgr = codeGen.typeMgr();

        srcStructTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), srcStructTypeRef);
        dstStructTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstStructTypeRef);
        if (!srcStructTypeRef.isValid() || !dstStructTypeRef.isValid())
            return false;

        const TypeInfo& srcStructType = typeMgr.get(srcStructTypeRef);
        const TypeInfo& dstStructType = typeMgr.get(dstStructTypeRef);
        if (!srcStructType.isStruct() || !dstStructType.isStruct())
            return false;

        if (!srcStructType.payloadSymStruct().resolveUsingFieldPath(codeGen.ctx(), dstStructType.payloadSymStruct(), outSteps))
            return false;

        return !outSteps.empty() && !usingPathHasPointerStep(outSteps);
    }

    bool resolveUsingPointerLikeCastPath(CodeGen& codeGen, TypeRef sourceTypeRef, TypeRef dstTypeRef, SmallVector<SymbolStructUsingPathStep>& outSteps)
    {
        const TypeManager& typeMgr               = codeGen.typeMgr();
        const TypeRef      resolvedSourceTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceTypeRef);
        const TypeRef      resolvedDstTypeRef    = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstTypeRef);
        if (!resolvedSourceTypeRef.isValid() || !resolvedDstTypeRef.isValid())
            return false;

        const TypeInfo& sourceType = typeMgr.get(resolvedSourceTypeRef);
        const TypeInfo& dstType    = typeMgr.get(resolvedDstTypeRef);
        if (!(sourceType.isAnyPointer() || sourceType.isReference() || sourceType.isMoveReference()))
            return false;
        if (!(dstType.isAnyPointer() || dstType.isReference() || dstType.isMoveReference()))
            return false;

        return resolveUsingStructCastPath(codeGen, sourceType.payloadTypeRef(), dstType.payloadTypeRef(), outSteps);
    }

    bool tryEmitAddressBackedPointerLikeCast(CodeGen& codeGen, const CodeGenNodePayload& srcPayload, TypeRef sourceTypeRef, TypeRef dstTypeRef)
    {
        if (!srcPayload.isAddress())
            return false;

        const TypeManager& typeMgr               = codeGen.typeMgr();
        const TypeRef      resolvedSourceTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceTypeRef);
        const TypeRef      sourceTypeToCheck     = resolvedSourceTypeRef.isValid() ? resolvedSourceTypeRef : sourceTypeRef;
        if (!sourceTypeToCheck.isValid())
            return false;

        const TypeInfo& sourceType = typeMgr.get(sourceTypeToCheck);
        const TypeInfo& dstType    = typeMgr.get(dstTypeRef);
        if (sourceType.isPointerOrReference() || sourceType.isNull())
            return false;
        if (!(dstType.isReference() || dstType.isMoveReference() || dstType.isAnyPointer()))
            return false;

        MicroReg pointeeAddressReg = srcPayload.reg;
        if (dstType.isReference() || dstType.isMoveReference())
        {
            const TypeRef resolvedDstPointeeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstType.payloadTypeRef());
            const TypeRef dstPointeeTypeRef     = resolvedDstPointeeRef.isValid() ? resolvedDstPointeeRef : dstType.payloadTypeRef();
            if (!dstPointeeTypeRef.isValid())
                return false;

            if (sourceTypeToCheck != dstPointeeTypeRef)
            {
                SmallVector<SymbolStructUsingPathStep> usingPath;
                if (!resolveUsingStructCastPath(codeGen, sourceTypeRef, dstType.payloadTypeRef(), usingPath))
                    return false;

                for (const auto& step : usingPath)
                {
                    SWC_ASSERT(step.field != nullptr);
                    SWC_ASSERT(!step.isPointer);
                    pointeeAddressReg = codeGen.offsetAddressReg(pointeeAddressReg, step.field->offset());
                }
            }
        }
        else
        {
            const TypeRef resolvedDstPointeeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstType.payloadTypeRef());
            const TypeRef dstPointeeTypeRef     = resolvedDstPointeeRef.isValid() ? resolvedDstPointeeRef : dstType.payloadTypeRef();
            if (!dstPointeeTypeRef.isValid())
                return false;

            if (sourceTypeToCheck != dstPointeeTypeRef && dstPointeeTypeRef != typeMgr.typeVoid())
                return false;
        }

        // Addressable values cast to references/pointers must become the pointer value itself.
        // Keeping them as an address payload causes later member/index lowering to dereference one level too far.
        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = pointeeAddressReg;
        dstPayload.markMaterializedPointerLikeValue();
        return true;
    }

    bool tryEmitValueBackedPointerLikeCast(CodeGen& codeGen, const CodeGenNodePayload& srcPayload, TypeRef sourceTypeRef, TypeRef dstTypeRef, const CodeGenLoweringPayload* castPayload)
    {
        if (!srcPayload.isValue() || srcPayload.hasMaterializedPointerLikeValue())
            return false;
        if (!castPayload || castPayload->runtimeStorageSym == nullptr)
            return false;

        const TypeManager& typeMgr               = codeGen.typeMgr();
        const TypeRef      resolvedSourceTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceTypeRef);
        const TypeRef      sourceTypeToCheck     = resolvedSourceTypeRef.isValid() ? resolvedSourceTypeRef : sourceTypeRef;
        if (!sourceTypeToCheck.isValid())
            return false;

        const TypeInfo& sourceType = typeMgr.get(sourceTypeToCheck);
        const TypeInfo& dstType    = typeMgr.get(dstTypeRef);
        if (sourceType.isPointerOrReference() || sourceType.isNull())
            return false;
        if (!(dstType.isReference() || dstType.isMoveReference() || dstType.isAnyPointer()))
            return false;

        const TypeRef resolvedDstPointeeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstType.payloadTypeRef());
        const TypeRef dstPointeeTypeRef     = resolvedDstPointeeRef.isValid() ? resolvedDstPointeeRef : dstType.payloadTypeRef();
        if (!dstPointeeTypeRef.isValid())
            return false;

        SmallVector<SymbolStructUsingPathStep> usingPath;
        if (dstType.isReference() || dstType.isMoveReference())
        {
            if (sourceTypeToCheck != dstPointeeTypeRef &&
                !resolveUsingStructCastPath(codeGen, sourceTypeRef, dstType.payloadTypeRef(), usingPath))
                return false;
        }
        else if (sourceTypeToCheck != dstPointeeTypeRef && dstPointeeTypeRef != typeMgr.typeVoid())
        {
            return false;
        }

        const uint64_t sourceSize = sourceType.sizeOf(codeGen.ctx());
        SWC_ASSERT(sourceSize > 0);
        if (sourceSize != 1 && sourceSize != 2 && sourceSize != 4 && sourceSize != 8)
            return false;

        MicroReg storageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        codeGen.builder().emitLoadMemReg(storageReg, 0, srcPayload.reg, CodeGenTypeHelpers::bitsFromStorageSize(sourceSize));

        for (const auto& step : usingPath)
        {
            SWC_ASSERT(step.field != nullptr);
            SWC_ASSERT(!step.isPointer);
            storageReg = codeGen.offsetAddressReg(storageReg, step.field->offset());
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = storageReg;
        dstPayload.markMaterializedPointerLikeValue();
        return true;
    }

    bool tryEmitReferenceToPointerCast(CodeGen& codeGen, const CodeGenNodePayload& srcPayload, TypeRef sourceTypeRef, TypeRef dstTypeRef)
    {
        const TypeManager& typeMgr               = codeGen.typeMgr();
        const TypeRef      resolvedSourceTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceTypeRef);
        const TypeRef      resolvedDstTypeRef    = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstTypeRef);
        if (!resolvedSourceTypeRef.isValid() || !resolvedDstTypeRef.isValid())
            return false;

        const TypeInfo& sourceType = typeMgr.get(resolvedSourceTypeRef);
        const TypeInfo& dstType    = typeMgr.get(resolvedDstTypeRef);
        if (!sourceType.isReference() || !dstType.isAnyPointer())
            return false;

        const TypeRef sourcePointeeTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceType.payloadTypeRef());
        const TypeRef dstPointeeTypeRef    = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstType.payloadTypeRef());
        if (!sourcePointeeTypeRef.isValid() || !dstPointeeTypeRef.isValid())
            return false;
        if (sourcePointeeTypeRef != dstPointeeTypeRef && dstPointeeTypeRef != typeMgr.typeVoid())
            return false;

        MicroReg pointerReg = srcPayload.reg;
        if (srcPayload.isAddress())
        {
            pointerReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(pointerReg, srcPayload.reg, 0, MicroOpBits::B64);
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = pointerReg;
        dstPayload.markMaterializedPointerLikeValue();
        return true;
    }

    bool tryEmitIndirectValueCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef sourceTypeRef, TypeRef dstTypeRef)
    {
        if (!Cast::indirectValueCastTypeRef(codeGen.sema(), sourceTypeRef, dstTypeRef).isValid())
            return false;

        TypeRef            readTypeRef          = sourceTypeRef;
        CodeGenNodePayload readPayload          = sourcePayloadForCast(codeGen, srcNodeRef);
        const TypeManager& typeMgr              = codeGen.typeMgr();
        const TypeRef      sourceTypeToCheckRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceTypeRef);
        const TypeInfo&    sourceType           = typeMgr.get(sourceTypeToCheckRef.isValid() ? sourceTypeToCheckRef : sourceTypeRef);
        if (sourceType.isAnyPointer())
        {
            if (readPayload.isAddress())
            {
                const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
                codeGen.builder().emitLoadRegMem(pointerReg, readPayload.reg, 0, MicroOpBits::B64);
                readPayload.reg = pointerReg;
            }

            readTypeRef         = sourceType.payloadTypeRef();
            readPayload.typeRef = readTypeRef;
            readPayload.setIsAddress();
        }
        else
        {
            CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, readPayload, readTypeRef);
        }
        SWC_ASSERT(readTypeRef.isValid());
        SWC_ASSERT(!codeGen.typeMgr().get(readTypeRef).isReference());
        SWC_ASSERT(readPayload.isAddress());

        const TypeRef     resolvedReadTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), readTypeRef);
        const TypeInfo&   readType            = codeGen.typeMgr().get(resolvedReadTypeRef.isValid() ? resolvedReadTypeRef : readTypeRef);
        const MicroOpBits directBits          = CodeGenTypeHelpers::scalarStoreBits(readType, codeGen.ctx());
        MicroBuilder&     builder             = codeGen.builder();
        if (directBits != MicroOpBits::Zero)
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitLoadRegMem(dstPayload.reg, readPayload.reg, 0, directBits);
            return true;
        }

        const auto* castPayload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(castPayload != nullptr);
        SWC_ASSERT(castPayload->runtimeStorageSym != nullptr);

        const MicroReg storageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        const uint64_t valueSize  = readType.sizeOf(codeGen.ctx());
        if (valueSize)
        {
            SWC_ASSERT(valueSize <= std::numeric_limits<uint32_t>::max());
            CodeGenMemoryHelpers::emitMemCopy(codeGen, storageReg, readPayload.reg, static_cast<uint32_t>(valueSize));
        }

        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), storageReg, dstTypeRef);
        return true;
    }

    Result tryEmitReferenceScalarNumericCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef sourceTypeRef, TypeRef dstTypeRef, bool& outHandled)
    {
        outHandled                            = false;
        const TypeManager& typeMgr            = codeGen.typeMgr();
        const TypeRef      resolvedSourceRef  = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceTypeRef);
        const TypeRef      resolvedDstTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstTypeRef);
        if (!resolvedSourceRef.isValid() || !resolvedDstTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& sourceType = typeMgr.get(resolvedSourceRef);
        const TypeInfo& dstType    = typeMgr.get(resolvedDstTypeRef);
        if (!(sourceType.isReference() || sourceType.isMoveReference()))
            return Result::Continue;

        const TypeRef pointeeTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceType.payloadTypeRef());
        if (!pointeeTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& pointeeType = typeMgr.get(pointeeTypeRef);
        if (!pointeeType.isScalarNumeric() || !dstType.isScalarNumeric())
            return Result::Continue;

        const bool srcFloatType   = pointeeType.isFloat();
        const bool srcIntLikeType = pointeeType.isNumericIntLike();
        const bool dstFloatType   = dstType.isFloat();
        const bool dstIntLikeType = dstType.isNumericIntLike();
        if (!((srcIntLikeType && dstIntLikeType) || (srcIntLikeType && dstFloatType) || (srcFloatType && dstFloatType) || (srcFloatType && dstIntLikeType)))
            return Result::Continue;

        CodeGenNodePayload readPayload = sourcePayloadForCast(codeGen, srcNodeRef);
        TypeRef            readTypeRef = sourceTypeRef;
        CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, readPayload, readTypeRef);
        SWC_ASSERT(readTypeRef.isValid());
        SWC_ASSERT(readPayload.isAddress());

        const TypeRef     resolvedReadTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), readTypeRef);
        const TypeInfo&   readType            = typeMgr.get(resolvedReadTypeRef.isValid() ? resolvedReadTypeRef : readTypeRef);
        const MicroOpBits srcOpBits           = CodeGenTypeHelpers::numericOrBoolBits(readType);
        const MicroOpBits dstOpBits           = CodeGenTypeHelpers::numericOrBoolBits(dstType);
        SWC_ASSERT(srcOpBits != MicroOpBits::Zero);
        SWC_ASSERT(dstOpBits != MicroOpBits::Zero);
        if (srcOpBits == MicroOpBits::Zero || dstOpBits == MicroOpBits::Zero)
            return Result::Continue;

        MicroBuilder& builder = codeGen.builder();
        MicroReg      srcReg  = codeGen.nextVirtualRegisterForType(readTypeRef);
        builder.emitLoadRegMem(srcReg, readPayload.reg, 0, srcOpBits);

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        outHandled                     = true;

        if (srcIntLikeType && dstIntLikeType)
        {
            SWC_RESULT(CodeGenSafety::emitIntLikeCastOverflowCheck(codeGen, codeGen.node(codeGen.curNodeRef()), srcReg, readType, dstType));
            dstPayload.reg = codeGen.nextVirtualIntRegister();

            if (dstType.isBool())
            {
                CodeGenCompareHelpers::emitTruthyBool(codeGen, dstPayload.reg, srcReg, readType, srcOpBits);
                return Result::Continue;
            }

            const uint32_t srcWidth = getNumBits(srcOpBits);
            const uint32_t dstWidth = getNumBits(dstOpBits);
            if (srcWidth == dstWidth || srcWidth > dstWidth)
            {
                builder.emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (readType.isNumericSigned())
            {
                builder.emitLoadSignedExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
                return Result::Continue;
            }

            builder.emitLoadZeroExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
            return Result::Continue;
        }

        if (srcIntLikeType && dstFloatType)
        {
            if (pointeeType.isIntLikeUnsigned())
            {
                dstPayload.reg = emitUnsignedIntToFloatReg(codeGen, srcReg, pointeeType, dstTypeRef);
                return Result::Continue;
            }

            if (getNumBits(srcOpBits) < 32 || (dstOpBits == MicroOpBits::B64 && getNumBits(srcOpBits) == 32))
            {
                const MicroReg    widenedReg  = codeGen.nextVirtualIntRegister();
                const MicroOpBits widenedBits = dstOpBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                builder.emitLoadSignedExtendRegReg(widenedReg, srcReg, widenedBits, srcOpBits);
                srcReg = widenedReg;
            }

            dstPayload.reg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstPayload.reg, dstOpBits);
            builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertIntToFloat, dstOpBits);
            return Result::Continue;
        }

        if (srcFloatType && dstFloatType)
        {
            if (srcOpBits == dstOpBits)
            {
                dstPayload.reg = srcReg;
                return Result::Continue;
            }

            dstPayload.reg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstPayload.reg, dstOpBits);
            builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToFloat, srcOpBits);
            return Result::Continue;
        }

        if (srcFloatType && dstType.isBool())
        {
            dstPayload.reg = codeGen.nextVirtualIntRegister();
            CodeGenCompareHelpers::emitTruthyBool(codeGen, dstPayload.reg, srcReg, readType, srcOpBits);
            return Result::Continue;
        }

        dstPayload.reg = codeGen.nextVirtualRegisterForType(dstTypeRef);
        SWC_RESULT(CodeGenSafety::emitFloatToIntCastOverflowCheck(codeGen, codeGen.node(codeGen.curNodeRef()), srcReg, readType, dstType));
        builder.emitClearReg(dstPayload.reg, dstOpBits);
        builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToInt, srcOpBits);
        return Result::Continue;
    }

    Result emitUsingPointerLikeCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef sourceTypeRef, TypeRef dstTypeRef, const SmallVector<SymbolStructUsingPathStep>& usingPath)
    {
        const TypeRef resolvedSourceTypeRef = unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), sourceTypeRef);
        SWC_ASSERT(resolvedSourceTypeRef.isValid());

        const CodeGenNodePayload srcPayload = sourcePayloadForCast(codeGen, srcNodeRef);
        MicroBuilder&            builder    = codeGen.builder();

        MicroReg objectReg = srcPayload.reg;
        if (srcPayload.isAddress())
        {
            objectReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(objectReg, srcPayload.reg, 0, MicroOpBits::B64);
        }

        const TypeInfo& resolvedSourceType = codeGen.typeMgr().get(resolvedSourceTypeRef);
        SWC_ASSERT(resolvedSourceType.isAnyPointer() || resolvedSourceType.isReference() || resolvedSourceType.isMoveReference());
        for (const auto& step : usingPath)
        {
            SWC_ASSERT(step.field != nullptr);
            SWC_ASSERT(!step.isPointer);
            objectReg = codeGen.offsetAddressReg(objectReg, step.field->offset());
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = objectReg;
        return Result::Continue;
    }

    MicroReg narrowF64ToFloatBits(CodeGen& codeGen, MicroReg f64Reg, MicroOpBits dstBits, TypeRef dstTypeRef)
    {
        if (dstBits == MicroOpBits::B64)
            return f64Reg;

        MicroBuilder&  builder = codeGen.builder();
        const MicroReg dstReg  = codeGen.nextVirtualRegisterForType(dstTypeRef);
        builder.emitClearReg(dstReg, dstBits);
        builder.emitOpBinaryRegReg(dstReg, f64Reg, MicroOp::ConvertFloatToFloat, MicroOpBits::B64);
        return dstReg;
    }

    MicroReg emitUnsignedIntToFloatReg(CodeGen& codeGen, MicroReg srcReg, const TypeInfo& srcType, TypeRef dstTypeRef)
    {
        MicroBuilder&     builder = codeGen.builder();
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstTypeRef);
        const MicroOpBits srcBits = CodeGenTypeHelpers::numericOrBoolBits(srcType);
        const MicroOpBits dstBits = CodeGenTypeHelpers::numericOrBoolBits(dstType);
        SWC_ASSERT(srcType.isIntLikeUnsigned());
        SWC_ASSERT(dstType.isFloat());
        SWC_ASSERT(srcBits != MicroOpBits::Zero);
        SWC_ASSERT(dstBits == MicroOpBits::B32 || dstBits == MicroOpBits::B64);

        if (srcBits == MicroOpBits::B64)
        {
            const MicroLabelRef directLabel = builder.createLabel();
            const MicroLabelRef doneLabel   = builder.createLabel();
            const MicroReg      dstF64Reg   = codeGen.nextVirtualFloatRegister();

            builder.emitCmpRegImm(srcReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B32, directLabel);

            const MicroReg shiftedReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(shiftedReg, srcReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(shiftedReg, ApInt(1, 64), MicroOp::ShiftRight, MicroOpBits::B64);

            const MicroReg lsbReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(lsbReg, srcReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(lsbReg, ApInt(1, 64), MicroOp::And, MicroOpBits::B64);
            builder.emitOpBinaryRegReg(shiftedReg, lsbReg, MicroOp::Or, MicroOpBits::B64);

            builder.emitClearReg(dstF64Reg, MicroOpBits::B64);
            builder.emitOpBinaryRegReg(dstF64Reg, shiftedReg, MicroOp::ConvertIntToFloat, MicroOpBits::B64);
            builder.emitOpBinaryRegReg(dstF64Reg, dstF64Reg, MicroOp::FloatAdd, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

            builder.placeLabel(directLabel);
            builder.emitClearReg(dstF64Reg, MicroOpBits::B64);
            builder.emitOpBinaryRegReg(dstF64Reg, srcReg, MicroOp::ConvertIntToFloat, MicroOpBits::B64);
            builder.placeLabel(doneLabel);
            return narrowF64ToFloatBits(codeGen, dstF64Reg, dstBits, dstTypeRef);
        }

        MicroReg    convertReg  = srcReg;
        MicroOpBits convertBits = srcBits;
        if (getNumBits(srcBits) < 32 || dstBits == MicroOpBits::B64 || srcBits == MicroOpBits::B32)
        {
            const MicroOpBits widenedBits = dstBits == MicroOpBits::B64 || srcBits == MicroOpBits::B32 ? MicroOpBits::B64 : MicroOpBits::B32;
            const MicroReg    widenedReg  = codeGen.nextVirtualIntRegister();
            builder.emitLoadZeroExtendRegReg(widenedReg, srcReg, widenedBits, srcBits);
            convertReg  = widenedReg;
            convertBits = widenedBits;
        }

        if (convertBits == MicroOpBits::B64)
        {
            const MicroReg dstF64Reg = codeGen.nextVirtualFloatRegister();
            builder.emitClearReg(dstF64Reg, MicroOpBits::B64);
            builder.emitOpBinaryRegReg(dstF64Reg, convertReg, MicroOp::ConvertIntToFloat, MicroOpBits::B64);
            return narrowF64ToFloatBits(codeGen, dstF64Reg, dstBits, dstTypeRef);
        }

        const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
        builder.emitClearReg(dstReg, dstBits);
        builder.emitOpBinaryRegReg(dstReg, convertReg, MicroOp::ConvertIntToFloat, dstBits);
        return dstReg;
    }

    Result emitDynamicStructCast(CodeGen& codeGen, AstNodeRef sourceRef, TypeRef targetTypeRef, bool checkOnly)
    {
        const CodeGenNodePayload& sourcePayload = codeGen.payload(sourceRef);
        const TypeRef             sourceTypeRef = codeGen.viewType(sourceRef).typeRef();

        DynamicStructCastSourceInfo sourceInfo;
        const bool                  hasSourceInfo = resolveDynamicStructCastSourceInfo(codeGen.sema(), sourceRef, sourceTypeRef, sourceInfo);
        SWC_ASSERT(hasSourceInfo);

        const TypeRef targetResolvedTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), targetTypeRef);

        const auto* runtimePayload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(runtimePayload != nullptr);
        SWC_ASSERT(runtimePayload->runtimeFunctionSymbol != nullptr);
        const auto& runtimeFunction = *runtimePayload->runtimeFunctionSymbol;

        const TypeRef       resultTypeRef = codeGen.curViewType().typeRef();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&       builder       = codeGen.builder();
        const MicroOpBits   resultBits    = checkOnly ? MicroOpBits::B8 : MicroOpBits::B64;
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(resultPayload.reg, ApInt(0, 64), resultBits);

        MicroReg targetTypeReg = MicroReg::invalid();
        SWC_RESULT(CodeGenConstantHelpers::loadTypeInfoConstantReg(targetTypeReg, codeGen, targetResolvedTypeRef));

        MicroReg sourceTypeReg = MicroReg::invalid();
        MicroReg sourcePtrReg  = MicroReg::invalid();
        switch (sourceInfo.kind)
        {
            case DynamicStructCastSourceKind::StructAddress:
                SWC_RESULT(CodeGenConstantHelpers::loadTypeInfoConstantReg(sourceTypeReg, codeGen, sourceInfo.structTypeRef));
                sourcePtrReg = sourcePayload.reg;
                if (!sourcePtrReg.isValid())
                    return Result::Error;
                break;

            case DynamicStructCastSourceKind::StructPointerLike:
                SWC_RESULT(CodeGenConstantHelpers::loadTypeInfoConstantReg(sourceTypeReg, codeGen, sourceInfo.structTypeRef));
                sourcePtrReg = codeGen.nextVirtualIntRegister();
                if (sourcePayload.isAddress())
                    builder.emitLoadRegMem(sourcePtrReg, sourcePayload.reg, 0, MicroOpBits::B64);
                else
                    builder.emitLoadRegReg(sourcePtrReg, sourcePayload.reg, MicroOpBits::B64);
                break;

            case DynamicStructCastSourceKind::Interface:
            {
                SWC_ASSERT(sourcePayload.isAddress());
                const MicroReg itableReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(itableReg, sourcePayload.reg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);

                sourceTypeReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegImm(sourceTypeReg, ApInt(0, 64), MicroOpBits::B64);
                const MicroLabelRef typeDoneLabel = builder.createLabel();
                builder.emitCmpRegImm(itableReg, ApInt(0, 64), MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, typeDoneLabel);
                builder.emitLoadRegMem(sourceTypeReg, itableReg, 0, MicroOpBits::B64);
                builder.placeLabel(typeDoneLabel);

                sourcePtrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(sourcePtrReg, sourcePayload.reg, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
                break;
            }

            case DynamicStructCastSourceKind::Any:
            {
                SWC_ASSERT(sourcePayload.isAddress());
                sourceTypeReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(sourceTypeReg, sourcePayload.reg, offsetof(Runtime::Any, type), MicroOpBits::B64);

                if (!checkOnly)
                {
                    sourcePtrReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegMem(sourcePtrReg, sourcePayload.reg, offsetof(Runtime::Any, value), MicroOpBits::B64);
                }
                break;
            }

            default:
                return Result::Error;
        }

        if (checkOnly)
        {
            const MicroReg args[] = {targetTypeReg, sourceTypeReg};
            return CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, runtimeFunction, args, resultPayload.reg);
        }

        const MicroReg args[] = {targetTypeReg, sourceTypeReg, sourcePtrReg};
        return CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, runtimeFunction, args, resultPayload.reg);
    }

    Result emitArrayToStringCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const TypeInfo& srcType)
    {
        MicroBuilder&            builder    = codeGen.builder();
        const CodeGenNodePayload srcPayload = sourcePayloadForCast(codeGen, srcNodeRef);

        const SemaNodeView srcConstView = codeGen.viewConstant(srcNodeRef);
        if (srcConstView.hasConstant())
        {
            const ConstantValue& srcConst = codeGen.cstMgr().get(srcConstView.cstRef());
            if (srcConst.isArray())
            {
                const ByteSpan    arrayBytes       = srcConst.getArray();
                const ConstantRef runtimeStringRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, dstTypeRef, arrayBytes.data(), arrayBytes.size());
                SWC_ASSERT(runtimeStringRef.isValid());
                const ConstantValue&      runtimeStringCst = codeGen.cstMgr().get(runtimeStringRef);
                const CodeGenNodePayload& dstPayload       = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
                builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(runtimeStringCst.getStruct().data()), runtimeStringRef);
                return Result::Continue;
            }
        }

        const uint64_t length          = srcType.sizeOf(codeGen.ctx());
        const MicroReg runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        const MicroReg srcDataReg      = materializeArrayCastSourceAddress(codeGen, srcNodeRef, srcPayload, srcType);

        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::String, ptr), srcDataReg, MicroOpBits::B64);

        const MicroReg lengthReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(lengthReg, ApInt(length, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::String, length), lengthReg, MicroOpBits::B64);

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitArrayToSliceCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        SWC_ASSERT(dstType.isSlice());

        const TypeInfo& dstElementType = codeGen.typeMgr().get(dstType.payloadTypeRef());
        const uint64_t  elementCount   = sliceCountFromArrayCast(codeGen, srcType, dstElementType);

        MicroBuilder&            builder    = codeGen.builder();
        const CodeGenNodePayload srcPayload = sourcePayloadForCast(codeGen, srcNodeRef);

        const SemaNodeView srcConstView = codeGen.viewConstant(srcNodeRef);
        if (srcConstView.hasConstant())
        {
            const ConstantValue& srcConst = codeGen.cstMgr().get(srcConstView.cstRef());
            if (srcConst.isArray())
            {
                const ConstantRef safeArrayCstRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, srcConstView.cstRef(), srcConst.typeRef());
                SWC_ASSERT(safeArrayCstRef.isValid());
                const ConstantValue& safeArrayCst    = codeGen.cstMgr().get(safeArrayCstRef);
                const ConstantRef    runtimeSliceRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, dstTypeRef, safeArrayCst.getArray().data(), elementCount);
                SWC_ASSERT(runtimeSliceRef.isValid());
                const ConstantValue&      runtimeSliceCst = codeGen.cstMgr().get(runtimeSliceRef);
                const CodeGenNodePayload& dstPayload      = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
                builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(runtimeSliceCst.getStruct().data()), runtimeSliceRef);
                return Result::Continue;
            }
        }

        const MicroReg runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        const MicroReg srcDataReg      = materializeArrayCastSourceAddress(codeGen, srcNodeRef, srcPayload, srcType);

        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, ptr), srcDataReg, MicroOpBits::B64);

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, ApInt(elementCount, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, count), countReg, MicroOpBits::B64);

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitArrayToPointerCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const TypeInfo& srcType)
    {
        MicroBuilder&            builder    = codeGen.builder();
        const CodeGenNodePayload srcPayload = sourcePayloadForCast(codeGen, srcNodeRef);

        const SemaNodeView srcConstView = codeGen.viewConstant(srcNodeRef);
        if (srcConstView.hasConstant())
        {
            const ConstantValue& srcConst = codeGen.cstMgr().get(srcConstView.cstRef());
            if (srcConst.isArray())
            {
                const ConstantRef safeArrayCstRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, srcConstView.cstRef(), srcConst.typeRef());
                SWC_ASSERT(safeArrayCstRef.isValid());
                const ConstantValue& safeArrayCst = codeGen.cstMgr().get(safeArrayCstRef);

                CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
                builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(safeArrayCst.getArray().data()), safeArrayCstRef);
                dstPayload.markMaterializedPointerLikeValue();
                return Result::Continue;
            }
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = materializeArrayCastSourceAddress(codeGen, srcNodeRef, srcPayload, srcType);
        dstPayload.markMaterializedPointerLikeValue();
        return Result::Continue;
    }

    MicroReg emitLoadCStringReg(CodeGen& codeGen, const CodeGenNodePayload& payload)
    {
        const MicroReg cstrReg = codeGen.nextVirtualIntRegister();
        if (payload.isAddress())
            codeGen.builder().emitLoadRegMem(cstrReg, payload.reg, 0, MicroOpBits::B64);
        else
            codeGen.builder().emitLoadRegReg(cstrReg, payload.reg, MicroOpBits::B64);
        return cstrReg;
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

    Result emitCStringToStringOrSliceCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const TypeInfo& dstType)
    {
        SWC_ASSERT(dstType.isString() || dstType.isSlice());

        MicroBuilder&            builder    = codeGen.builder();
        const CodeGenNodePayload srcPayload = sourcePayloadForCast(codeGen, srcNodeRef);
        const MicroReg           cstrReg    = emitLoadCStringReg(codeGen, srcPayload);

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        emitCStringCountReg(codeGen, countReg, cstrReg);

        const MicroReg runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, ptr), cstrReg, MicroOpBits::B64);

        const uint32_t countOffset = dstType.isString() ? offsetof(Runtime::String, length) : offsetof(Runtime::Slice<std::byte>, count);
        builder.emitLoadMemReg(runtimeValueReg, countOffset, countReg, MicroOpBits::B64);

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }

    // Emit a DynCast safety panic call using the generic safety panic function.
    Result emitDynCastPanic(CodeGen& codeGen, const AstNode& node)
    {
        const IdentifierRef idRef = codeGen.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SafetyPanic);
        SWC_ASSERT(idRef.isValid());
        SymbolFunction* panicFn = codeGen.compiler().runtimeFunctionSymbol(idRef);
        SWC_ASSERT(panicFn != nullptr);
        return CodeGenSafety::emitDynCastCheck(codeGen, *panicFn, node);
    }

    Result emitAnyRuntimeAsCall(MicroReg& outResultReg, CodeGen& codeGen, const SymbolFunction& asFn, TypeRef targetTypeRef, MicroReg sourceTypeReg, MicroReg valueAddrReg)
    {
        MicroBuilder& builder = codeGen.builder();

        MicroReg targetTypeReg = MicroReg::invalid();
        SWC_RESULT(CodeGenConstantHelpers::loadTypeInfoConstantReg(targetTypeReg, codeGen, targetTypeRef));

        outResultReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(outResultReg, ApInt(0, 64), MicroOpBits::B64);
        const MicroReg args[] = {targetTypeReg, sourceTypeReg, valueAddrReg};
        return CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, asFn, args, outResultReg);
    }

    Result emitAnyReferenceCast(CodeGen& codeGen, const CodeGenNodePayload& srcPayload, const TypeInfo& dstType, TypeRef dstTypeRef, const CodeGenLoweringPayload* castPayload, bool hasDynCastSafety, MicroReg valueAddrReg)
    {
        MicroBuilder& builder           = codeGen.builder();
        MicroReg      finalValueAddrReg = valueAddrReg;
        if (castPayload && castPayload->runtimeFunctionSymbol)
        {
            const auto&    runtimeAsFn   = *castPayload->runtimeFunctionSymbol;
            const MicroReg sourceTypeReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(sourceTypeReg, srcPayload.reg, offsetof(Runtime::Any, type), MicroOpBits::B64);

            MicroReg asResultReg = MicroReg::invalid();
            SWC_RESULT(emitAnyRuntimeAsCall(asResultReg, codeGen, runtimeAsFn, dstType.payloadTypeRef(), sourceTypeReg, valueAddrReg));

            if (hasDynCastSafety)
            {
                const MicroLabelRef okLabel = builder.createLabel();
                builder.emitCmpRegImm(asResultReg, ApInt(0, 64), MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, okLabel);
                SWC_RESULT(emitDynCastPanic(codeGen, codeGen.node(codeGen.curNodeRef())));
                builder.placeLabel(okLabel);
                finalValueAddrReg = asResultReg;
            }
            else
            {
                finalValueAddrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(finalValueAddrReg, valueAddrReg, MicroOpBits::B64);

                const MicroLabelRef keepOriginalLabel = builder.createLabel();
                builder.emitCmpRegImm(asResultReg, ApInt(0, 64), MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, keepOriginalLabel);
                builder.emitLoadRegReg(finalValueAddrReg, asResultReg, MicroOpBits::B64);
                builder.placeLabel(keepOriginalLabel);
            }
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(dstPayload.reg, finalValueAddrReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitAnyPointerCast(CodeGen& codeGen, const CodeGenNodePayload& srcPayload, const TypeInfo& dstType, TypeRef dstTypeRef, const CodeGenLoweringPayload* castPayload, MicroReg valueAddrReg)
    {
        MicroBuilder& builder = codeGen.builder();

        MicroReg asValueAddrReg   = MicroReg::invalid();
        MicroReg asPointerAddrReg = MicroReg::invalid();
        MicroReg asMutablePtrReg  = MicroReg::invalid();
        if (castPayload && castPayload->runtimeFunctionSymbol)
        {
            const auto& runtimeAsFn = *castPayload->runtimeFunctionSymbol;

            const MicroReg sourceTypeReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(sourceTypeReg, srcPayload.reg, offsetof(Runtime::Any, type), MicroOpBits::B64);

            SWC_RESULT(emitAnyRuntimeAsCall(asPointerAddrReg, codeGen, runtimeAsFn, dstTypeRef, sourceTypeReg, valueAddrReg));

            if (dstType.isConst())
            {
                SWC_RESULT(emitAnyRuntimeAsCall(asValueAddrReg, codeGen, runtimeAsFn, dstType.payloadTypeRef(), sourceTypeReg, valueAddrReg));

                TypeInfoFlags mutableFlags = dstType.flags();
                mutableFlags.remove(TypeInfoFlagsE::Const);
                const TypeRef mutablePtrTypeRef = dstType.isBlockPointer() ? codeGen.typeMgr().addType(TypeInfo::makeBlockPointer(dstType.payloadTypeRef(), mutableFlags)) : codeGen.typeMgr().addType(TypeInfo::makeValuePointer(dstType.payloadTypeRef(), mutableFlags));
                if (mutablePtrTypeRef != dstTypeRef)
                    SWC_RESULT(emitAnyRuntimeAsCall(asMutablePtrReg, codeGen, runtimeAsFn, mutablePtrTypeRef, sourceTypeReg, valueAddrReg));
            }
        }

        auto valueBits = MicroOpBits::Zero;
        if (anyCastAsValueBits(codeGen, dstTypeRef, valueBits))
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);

            if (asValueAddrReg.isValid() || asPointerAddrReg.isValid() || asMutablePtrReg.isValid())
            {
                const MicroLabelRef tryPointerLabel = builder.createLabel();
                const MicroLabelRef tryMutableLabel = builder.createLabel();
                const MicroLabelRef fallbackLabel   = builder.createLabel();
                const MicroLabelRef doneLabel       = builder.createLabel();

                if (asValueAddrReg.isValid())
                {
                    builder.emitCmpRegImm(asValueAddrReg, ApInt(0, 64), MicroOpBits::B64);
                    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, tryPointerLabel);
                    builder.emitLoadRegReg(dstPayload.reg, asValueAddrReg, MicroOpBits::B64);
                    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
                }
                else
                {
                    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, tryPointerLabel);
                }

                builder.placeLabel(tryPointerLabel);
                if (asPointerAddrReg.isValid())
                {
                    const MicroLabelRef pointerMissLabel = asMutablePtrReg.isValid() ? tryMutableLabel : fallbackLabel;
                    builder.emitCmpRegImm(asPointerAddrReg, ApInt(0, 64), MicroOpBits::B64);
                    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, pointerMissLabel);
                    builder.emitLoadRegMem(dstPayload.reg, asPointerAddrReg, 0, valueBits);
                    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
                }
                else if (asMutablePtrReg.isValid())
                {
                    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, tryMutableLabel);
                }
                else
                {
                    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, fallbackLabel);
                }

                if (asMutablePtrReg.isValid())
                {
                    builder.placeLabel(tryMutableLabel);
                    builder.emitCmpRegImm(asMutablePtrReg, ApInt(0, 64), MicroOpBits::B64);
                    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, fallbackLabel);
                    builder.emitLoadRegMem(dstPayload.reg, asMutablePtrReg, 0, valueBits);
                    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
                }

                builder.placeLabel(fallbackLabel);
                builder.emitLoadRegMem(dstPayload.reg, valueAddrReg, 0, valueBits);
                builder.placeLabel(doneLabel);
                return Result::Continue;
            }

            builder.emitLoadRegMem(dstPayload.reg, valueAddrReg, 0, valueBits);
            return Result::Continue;
        }

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadAddressReg(codeGen.curNodeRef(), codeGen.nextVirtualIntRegister(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, valueAddrReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitAnyCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef)
    {
        if (dstTypeRef.isInvalid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef);
            return Result::Continue;
        }

        const CodeGenNodePayload srcPayload = sourcePayloadForCast(codeGen, srcNodeRef);

        const SemaNodeView srcView = codeGen.viewType(srcNodeRef);
        SWC_ASSERT(srcView.type());
        const TypeRef   resolvedSrcTypeRef = unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), srcView.typeRef());
        const TypeInfo& resolvedSrcType    = codeGen.typeMgr().get(resolvedSrcTypeRef);
        if (!resolvedSrcType.isAny())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const TypeRef   resolvedDstTypeRef = unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), dstTypeRef);
        const TypeInfo& dstType            = codeGen.typeMgr().get(resolvedDstTypeRef);
        if (dstType.isAny())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const AstNode& castNode                        = codeGen.node(codeGen.curNodeRef());
        const bool     isImplicitNullableAnyStringCast = castNode.is(AstNodeId::CastExpr) &&
                                                     !castNode.cast<AstCastExpr>().hasFlag(AstCastExprFlagsE::Explicit) &&
                                                     resolvedSrcType.isNullable() &&
                                                     dstType.isString() &&
                                                     dstType.isNullable();

        SWC_ASSERT(srcPayload.isAddress());

        const auto* castPayload      = codeGen.loweringPayload(codeGen.curNodeRef());
        const bool  hasDynCastSafety = castPayload && castPayload->hasRuntimeSafety(Runtime::SafetyWhat::DynCast);

        MicroBuilder& builder = codeGen.builder();

        // Runtime `any` stores a type pointer plus an address to the erased value.
        const MicroReg valueAddrReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(valueAddrReg, srcPayload.reg, offsetof(Runtime::Any, value), MicroOpBits::B64);

        if (dstType.isReference() || dstType.isMoveReference())
            return emitAnyReferenceCast(codeGen, srcPayload, dstType, dstTypeRef, castPayload, hasDynCastSafety, valueAddrReg);

        if (dstType.isAnyPointer())
            return emitAnyPointerCast(codeGen, srcPayload, dstType, dstTypeRef, castPayload, valueAddrReg);

        MicroReg finalValueAddrReg = valueAddrReg;
        if (castPayload && castPayload->runtimeFunctionSymbol)
        {
            const auto& runtimeAsFn = *castPayload->runtimeFunctionSymbol;

            const MicroReg sourceTypeReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(sourceTypeReg, srcPayload.reg, offsetof(Runtime::Any, type), MicroOpBits::B64);

            MicroReg asResultReg = MicroReg::invalid();
            SWC_RESULT(emitAnyRuntimeAsCall(asResultReg, codeGen, runtimeAsFn, dstTypeRef, sourceTypeReg, valueAddrReg));

            if (hasDynCastSafety)
            {
                const MicroLabelRef okLabel = builder.createLabel();
                builder.emitCmpRegImm(asResultReg, ApInt(0, 64), MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, okLabel);
                SWC_RESULT(emitDynCastPanic(codeGen, codeGen.node(codeGen.curNodeRef())));
                builder.placeLabel(okLabel);
                finalValueAddrReg = asResultReg;
            }
            else if (isImplicitNullableAnyStringCast)
            {
                finalValueAddrReg = asResultReg;
            }
            else
            {
                finalValueAddrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(finalValueAddrReg, valueAddrReg, MicroOpBits::B64);

                const MicroLabelRef keepOriginalLabel = builder.createLabel();
                builder.emitCmpRegImm(asResultReg, ApInt(0, 64), MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, keepOriginalLabel);
                builder.emitLoadRegReg(finalValueAddrReg, asResultReg, MicroOpBits::B64);
                builder.placeLabel(keepOriginalLabel);
            }
        }

        if (dstType.isString() || dstType.isSlice() || dstType.isInterface() || dstType.isAnyVariadic())
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(dstPayload.reg, finalValueAddrReg, MicroOpBits::B64);
            return Result::Continue;
        }

        auto valueBits = MicroOpBits::Zero;
        if (anyCastAsValueBits(codeGen, dstTypeRef, valueBits))
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitLoadRegMem(dstPayload.reg, finalValueAddrReg, 0, valueBits);
            return Result::Continue;
        }

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadAddressReg(codeGen.curNodeRef(), codeGen.nextVirtualIntRegister(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, finalValueAddrReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitFunctionToClosureCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = codeGen.typeMgr().get(dstTypeRef);
        if (srcType.isLambdaClosure())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const auto* castPayload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(castPayload != nullptr);
        SWC_ASSERT(castPayload->runtimeStorageSym != nullptr);

        auto&           dstFunc = dstType.payloadSymFunction();
        SymbolFunction* adapter = nullptr;
        SWC_RESULT(dstFunc.ensureClosureAdapter(codeGen.ctx(), adapter));
        SWC_ASSERT(adapter != nullptr);
        codeGen.function().addCallDependency(adapter);

        MicroBuilder&            builder         = codeGen.builder();
        const CodeGenNodePayload srcPayload      = sourcePayloadForCast(codeGen, srcNodeRef);
        const MicroReg           runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        CodeGenMemoryHelpers::emitMemZero(codeGen, runtimeValueReg, sizeof(Runtime::ClosureValue));

        const MicroReg invokeReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(invokeReg, 0, ConstantRef::invalid(), adapter);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::ClosureValue, invoke), invokeReg, MicroOpBits::B64);

        MicroReg targetReg = srcPayload.reg;
        if (srcPayload.isAddress())
        {
            targetReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(targetReg, srcPayload.reg, 0, MicroOpBits::B64);
        }

        const MicroReg captureDstReg = codeGen.offsetAddressReg(runtimeValueReg, offsetof(Runtime::ClosureValue, capture));
        builder.emitLoadMemReg(captureDstReg, 0, targetReg, MicroOpBits::B64);
        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeValueReg, dstTypeRef);
        return Result::Continue;
    }

    Result initializeStructSetReceiverStorage(CodeGen& codeGen, MicroReg storageReg, TypeRef dstTypeRef, ConstantRef initCstRef)
    {
        if (!initCstRef.isValid())
            return Result::Continue;

        const uint64_t storageSize = codeGen.typeMgr().get(dstTypeRef).sizeOf(codeGen.ctx());
        if (!storageSize)
            return Result::Continue;

        SWC_ASSERT(storageSize <= std::numeric_limits<uint32_t>::max());
        SmallVector<std::byte> storageBytes;
        storageBytes.resize(storageSize);
        std::memset(storageBytes.data(), 0, storageBytes.size());
        SWC_RESULT(ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{storageBytes.data(), storageBytes.size()}, initCstRef, dstTypeRef));

        const ConstantRef    initPayloadCstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, dstTypeRef, ByteSpan{storageBytes.data(), storageBytes.size()});
        const ConstantValue& initPayloadCst    = codeGen.cstMgr().get(initPayloadCstRef);
        const MicroReg       initReg           = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(initReg, reinterpret_cast<uint64_t>(initPayloadCst.getStruct().data()), initPayloadCstRef);
        CodeGenMemoryHelpers::emitMemCopy(codeGen, storageReg, initReg, static_cast<uint32_t>(storageSize));
        return Result::Continue;
    }

    Result emitStructSetCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const CastSetPayload& setPayload)
    {
        SWC_UNUSED(srcNodeRef);

        const auto* castPayload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(castPayload != nullptr);
        SWC_ASSERT(castPayload->runtimeStorageSym != nullptr);
        SWC_ASSERT(setPayload.calledFn != nullptr);

        SmallVector<ResolvedCallArgument> resolvedArgs;
        codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), resolvedArgs);
        SWC_ASSERT(!resolvedArgs.empty() && resolvedArgs[0].argRef.isValid());

        const MicroReg runtimeStorageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        SWC_RESULT(initializeStructSetReceiverStorage(codeGen, runtimeStorageReg, dstTypeRef, setPayload.receiverInitCstRef));

        CodeGenNodePayload& receiverArg = codeGen.setPayload(resolvedArgs[0].argRef, dstTypeRef);
        receiverArg.reg                 = runtimeStorageReg;
        receiverArg.typeRef             = dstTypeRef;
        receiverArg.setIsAddress();

        const auto* receiverSym = codeGen.viewSymbol(resolvedArgs[0].argRef).sym();
        if (receiverSym && receiverSym->isVariable())
            codeGen.setVariablePayload(receiverSym->cast<SymbolVariable>(), receiverArg);

        codeGen.sema().setSymbol(codeGen.curNodeRef(), setPayload.calledFn);
        SWC_RESULT(CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid()));
        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeStorageReg, dstTypeRef);
        return Result::Continue;
    }

    Result emitStructOpCast(CodeGen& codeGen, const CastSpecOpPayload& castPayload)
    {
        SWC_ASSERT(castPayload.calledFn != nullptr);
        codeGen.sema().setSymbol(codeGen.curNodeRef(), castPayload.calledFn);
        return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
    }

    Result emitNumericCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef)
    {
        MicroBuilder&            builder             = codeGen.builder();
        const CodeGenNodePayload srcPayload          = sourcePayloadForCast(codeGen, srcNodeRef);
        const auto*              castPayload         = codeGen.loweringPayload(codeGen.curNodeRef());
        const bool               needsRuntimeStorage = castPayload && castPayload->runtimeStorageSym != nullptr;

        const TypeRef storedSourceTypeRef = codeGen.sema().viewStored(srcNodeRef, SemaNodeViewPartE::Type).typeRef();
        TypeRef       sourceTypeRef       = storedSourceTypeRef;
        if (!sourceTypeRef.isValid())
            sourceTypeRef = srcPayload.typeRef;

        if (dstTypeRef.isInvalid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef);
            return Result::Continue;
        }

        if (!sourceTypeRef.isValid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const auto* specOpPayload = codeGen.sema().semaPayload<CastSpecOpPayload>(codeGen.curNodeRef());
        if (specOpPayload &&
            specOpPayload->kind == CastSpecialOpPayloadKind::OpCast &&
            specOpPayload->calledFn != nullptr)
            return emitStructOpCast(codeGen, *specOpPayload);

        const auto* setPayload = codeGen.sema().semaPayload<CastSetPayload>(codeGen.curNodeRef());
        if (setPayload &&
            setPayload->kind == CastSpecialOpPayloadKind::Set &&
            setPayload->calledFn != nullptr)
            return emitStructSetCast(codeGen, srcNodeRef, dstTypeRef, *setPayload);

        const AstNodeRef resolvedSrcNodeRef = codeGen.viewZero(srcNodeRef).nodeRef();
        const AstNode&   srcNode            = codeGen.node(resolvedSrcNodeRef);
        if (!needsRuntimeStorage &&
            (srcNode.is(AstNodeId::CastExpr) || srcNode.is(AstNodeId::AutoCastExpr)) &&
            srcPayload.typeRef.isValid() &&
            srcPayload.typeRef == dstTypeRef &&
            storedSourceTypeRef.isValid() &&
            storedSourceTypeRef != dstTypeRef)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        TypeManager& typeMgr = codeGen.typeMgr();

        const TypeRef   resolvedSrcTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), sourceTypeRef);
        const TypeRef   resolvedDstTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), dstTypeRef);
        const TypeInfo& resolvedSrcType    = typeMgr.get(resolvedSrcTypeRef);
        const TypeInfo& resolvedDstType    = typeMgr.get(resolvedDstTypeRef);
        if (resolvedSrcType.isAny())
            return emitAnyCast(codeGen, srcNodeRef, dstTypeRef);

        const TypeInfo& srcType = typeMgr.get(sourceTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);
        if (srcType.isFunction() && dstType.isFunction() && !srcType.isLambdaClosure() && dstType.isLambdaClosure())
            return emitFunctionToClosureCast(codeGen, srcNodeRef, sourceTypeRef, dstTypeRef);
        if (resolvedSrcType.isInterface() && resolvedDstType.isAnyPointer())
        {
            const TypeRef dstPointeeTypeRef = unwrapAliasEnumTypeRef(typeMgr, codeGen.ctx(), resolvedDstType.payloadTypeRef());
            if (dstPointeeTypeRef.isValid() && typeMgr.get(dstPointeeTypeRef).isStruct())
                return emitDynamicStructCast(codeGen, srcNodeRef, dstPointeeTypeRef, false);
        }
        if (resolvedSrcType.isAnyPointer() &&
            resolvedSrcType.payloadTypeRef() == typeMgr.typeVoid() &&
            dstType.isFunction() &&
            !dstType.isLambdaClosure())
        {
            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, MicroOpBits::B64);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(dstPayload.reg, srcReg, MicroOpBits::B64);
            return Result::Continue;
        }

        const bool srcFloatType   = resolvedSrcType.isFloat();
        const bool srcIntLikeType = resolvedSrcType.isNumericIntLike();
        const bool dstFloatType   = resolvedDstType.isFloat();
        const bool dstIntLikeType = resolvedDstType.isNumericIntLike();

        if (resolvedSrcType.isNull() && resolvedDstType.isPointerLike())
        {
            const uint64_t dstSize = dstType.sizeOf(codeGen.ctx());
            if (dstSize <= sizeof(uint64_t))
            {
                codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                return Result::Continue;
            }

            SWC_ASSERT(dstSize <= std::numeric_limits<uint32_t>::max());
            // Large pointer-like layouts cannot be represented as a raw zero immediate; materialize a
            // typed zero blob that matches the destination runtime representation.
            SmallVector<std::byte> typedNullBytes;
            typedNullBytes.resize(dstSize);
            std::memset(typedNullBytes.data(), 0, typedNullBytes.size());

            const SemaNodeView srcConstView = codeGen.viewTypeConstant(srcNodeRef);
            const ConstantRef  nullCstRef   = srcConstView.cstRef().isValid() ? srcConstView.cstRef() : codeGen.cstMgr().cstNull();
            SWC_RESULT(ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{typedNullBytes.data(), typedNullBytes.size()}, nullCstRef, dstTypeRef));

            const ConstantRef         typedNullCstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, dstTypeRef, ByteSpan{typedNullBytes.data(), typedNullBytes.size()});
            const ConstantValue&      typedNullCst    = codeGen.cstMgr().get(typedNullCstRef);
            const CodeGenNodePayload& dstPayload      = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(typedNullCst.getStruct().data()), typedNullCstRef);
            return Result::Continue;
        }

        if (srcType.isString() &&
            dstType.isAnyPointer() &&
            dstType.isConst() &&
            (dstType.payloadTypeRef() == typeMgr.typeU8() || dstType.payloadTypeRef() == typeMgr.typeVoid()))
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(dstPayload.reg, srcPayload.reg, offsetof(Runtime::String, ptr), MicroOpBits::B64);
            return Result::Continue;
        }

        if (srcIntLikeType && resolvedDstType.isAnyPointer())
        {
            const MicroOpBits srcOpBits = CodeGenTypeHelpers::numericOrBoolBits(resolvedSrcType);
            SWC_ASSERT(srcOpBits != MicroOpBits::Zero);

            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            if (srcOpBits == MicroOpBits::B64)
                builder.emitLoadRegReg(dstPayload.reg, srcReg, MicroOpBits::B64);
            else
                builder.emitLoadZeroExtendRegReg(dstPayload.reg, srcReg, MicroOpBits::B64, srcOpBits);
            return Result::Continue;
        }

        bool handledReferenceScalarNumericCast = false;
        SWC_RESULT(tryEmitReferenceScalarNumericCast(codeGen, srcNodeRef, sourceTypeRef, dstTypeRef, handledReferenceScalarNumericCast));
        if (handledReferenceScalarNumericCast)
            return Result::Continue;

        if (tryEmitIndirectValueCast(codeGen, srcNodeRef, sourceTypeRef, dstTypeRef))
            return Result::Continue;

        if (tryEmitReferenceToPointerCast(codeGen, srcPayload, sourceTypeRef, dstTypeRef))
            return Result::Continue;

        if (tryEmitAddressBackedPointerLikeCast(codeGen, srcPayload, sourceTypeRef, dstTypeRef))
            return Result::Continue;

        if (tryEmitValueBackedPointerLikeCast(codeGen, srcPayload, sourceTypeRef, dstTypeRef, castPayload))
            return Result::Continue;

        if (resolvedSrcType.isArray() && resolvedDstType.isAnyPointer())
            return emitArrayToPointerCast(codeGen, srcNodeRef, dstTypeRef, resolvedSrcType);
        if (resolvedDstType.isString() && resolvedSrcType.isArray())
            return emitArrayToStringCast(codeGen, srcNodeRef, dstTypeRef, resolvedSrcType);
        if ((resolvedDstType.isString() || resolvedDstType.isSlice()) && resolvedSrcType.isCString())
            return emitCStringToStringOrSliceCast(codeGen, srcNodeRef, dstTypeRef, resolvedDstType);
        if (resolvedDstType.isSlice())
        {
            const TypeRef sourceArrayTypeRef = sliceCastSourceArrayTypeRef(codeGen, srcNodeRef, resolvedSrcTypeRef, resolvedSrcType, resolvedDstType);
            if (sourceArrayTypeRef.isValid())
                return emitArrayToSliceCast(codeGen, srcNodeRef, dstTypeRef, codeGen.typeMgr().get(sourceArrayTypeRef), resolvedDstType);
        }

        if (resolvedDstType.isAny() && !resolvedSrcType.isAny())
        {
            if (!castPayload || castPayload->runtimeStorageSym == nullptr)
            {
                codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                return Result::Continue;
            }

            const MicroReg runtimeAnyReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
            TypeRef        anyTypeRef    = sourceTypeRef;
            if (srcType.isChar())
                anyTypeRef = typeMgr.typeRune();

            MicroReg valuePtrReg = srcPayload.reg;
            if (!srcPayload.isAddress())
            {
                auto srcValueBits = MicroOpBits::Zero;
                if (!anyCastAsValueBits(codeGen, sourceTypeRef, srcValueBits))
                {
                    const uint64_t sourceSize = srcType.sizeOf(codeGen.ctx());
                    if (sourceSize == 1 || sourceSize == 2 || sourceSize == 4 || sourceSize == 8)
                    {
                        valuePtrReg = codeGen.nextVirtualIntRegister();
                        builder.emitLoadRegReg(valuePtrReg, runtimeAnyReg, MicroOpBits::B64);
                        builder.emitOpBinaryRegImm(valuePtrReg, ApInt(sizeof(Runtime::Any), 64), MicroOp::Add, MicroOpBits::B64);
                        builder.emitLoadMemReg(valuePtrReg, 0, srcPayload.reg, CodeGenTypeHelpers::bitsFromStorageSize(sourceSize));
                    }
                    else if (sourceSize == 0)
                    {
                        valuePtrReg = codeGen.nextVirtualIntRegister();
                        builder.emitLoadRegReg(valuePtrReg, runtimeAnyReg, MicroOpBits::B64);
                        builder.emitOpBinaryRegImm(valuePtrReg, ApInt(sizeof(Runtime::Any), 64), MicroOp::Add, MicroOpBits::B64);
                    }
                    else
                    {
                        codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                        return Result::Continue;
                    }
                }
                else
                {
                    valuePtrReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(valuePtrReg, runtimeAnyReg, MicroOpBits::B64);
                    builder.emitOpBinaryRegImm(valuePtrReg, ApInt(sizeof(Runtime::Any), 64), MicroOp::Add, MicroOpBits::B64);
                    builder.emitLoadMemReg(valuePtrReg, 0, srcPayload.reg, srcValueBits);
                }
            }

            builder.emitLoadMemReg(runtimeAnyReg, offsetof(Runtime::Any, value), valuePtrReg, MicroOpBits::B64);

            ConstantRef typeInfoCstRef = ConstantRef::invalid();
            SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, anyTypeRef, codeGen.curNodeRef()));
            const ConstantValue& typeInfoCst = codeGen.cstMgr().get(typeInfoCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());

            const MicroReg typeInfoReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrReloc(typeInfoReg, typeInfoCst.getValuePointer(), typeInfoCstRef);
            builder.emitLoadMemReg(runtimeAnyReg, offsetof(Runtime::Any, type), typeInfoReg, MicroOpBits::B64);

            codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeAnyReg, dstTypeRef);
            return Result::Continue;
        }

        const TypeRef interfaceObjectTypeRef = interfaceObjectStructTypeRef(codeGen, sourceTypeRef);
        if (interfaceObjectTypeRef.isValid() && dstType.isInterface())
        {
            SWC_ASSERT(castPayload && castPayload->runtimeStorageSym != nullptr);

            const TypeInfo&   objectType = typeMgr.get(interfaceObjectTypeRef);
            const auto&       srcStruct  = objectType.payloadSymStruct();
            const auto&       dstItf     = dstType.payloadSymInterface();
            InterfaceCastInfo castInfo;
            const bool        hasCastInfo = resolveInterfaceCastInfo(codeGen, srcStruct, dstItf, castInfo);
            SWC_ASSERT(hasCastInfo);
            SWC_ASSERT(castInfo.implSym != nullptr);

            constexpr uint64_t interfaceStorageSize = sizeof(Runtime::Interface);
            const bool         sourceIsPointerLike  = resolvedSrcType.isAnyPointer() || resolvedSrcType.isReference() || resolvedSrcType.isMoveReference();

            const MicroReg runtimeItfReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
            MicroReg       objectReg     = MicroReg::invalid();
            if (sourceIsPointerLike)
            {
                objectReg = materializePointerLikeInterfaceObjectReg(codeGen, srcPayload);
            }
            else
            {
                const uint64_t objectStorageSize     = objectType.sizeOf(codeGen.ctx());
                const bool     preserveSourceAddress = srcPayload.isAddress() && codeGen.sema().isLValue(srcNodeRef);

                objectReg = srcPayload.reg;
                if (!preserveSourceAddress)
                {
                    MicroReg objectStorageReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(objectStorageReg, runtimeItfReg, MicroOpBits::B64);
                    builder.emitOpBinaryRegImm(objectStorageReg, ApInt(interfaceStorageSize, 64), MicroOp::Add, MicroOpBits::B64);

                    if (objectStorageSize)
                    {
                        if (srcPayload.isAddress())
                        {
                            SWC_ASSERT(objectStorageSize <= std::numeric_limits<uint32_t>::max());
                            CodeGenMemoryHelpers::emitMemCopy(codeGen, objectStorageReg, srcPayload.reg, static_cast<uint32_t>(objectStorageSize));
                        }
                        else
                        {
                            const MicroOpBits storeBits = microOpBitsFromChunkSize(static_cast<uint32_t>(objectStorageSize));
                            SWC_ASSERT(storeBits != MicroOpBits::Zero);
                            builder.emitLoadMemReg(objectStorageReg, 0, srcPayload.reg, storeBits);
                        }
                    }

                    objectReg = objectStorageReg;
                }
            }

            if (castInfo.usingField)
            {
                const SymbolVariable& usingField = *castInfo.usingField;
                // The runtime object pointer must target the `using` field implementation, whether we reused the
                // original lvalue address or spilled a temporary copy.
                if (castInfo.usingFieldIsPointer)
                {
                    const MicroReg baseObjectReg = objectReg;
                    objectReg                    = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegMem(objectReg, baseObjectReg, usingField.offset(), MicroOpBits::B64);
                }
                else
                {
                    const MicroReg baseObjectReg = objectReg;
                    objectReg                    = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(objectReg, baseObjectReg, MicroOpBits::B64);
                    if (usingField.offset())
                        builder.emitOpBinaryRegImm(objectReg, ApInt(usingField.offset(), 64), MicroOp::Add, MicroOpBits::B64);
                }
            }

            builder.emitLoadMemReg(runtimeItfReg, offsetof(Runtime::Interface, obj), objectReg, MicroOpBits::B64);

            MicroReg itableReg = MicroReg::invalid();
            SWC_RESULT(loadInterfaceMethodTableAddress(itableReg, codeGen, castInfo));
            builder.emitLoadMemReg(runtimeItfReg, offsetof(Runtime::Interface, itable), itableReg, MicroOpBits::B64);

            codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeItfReg, dstTypeRef);
            return Result::Continue;
        }

        SmallVector<SymbolStructUsingPathStep> usingPath;
        if (resolveUsingPointerLikeCastPath(codeGen, sourceTypeRef, dstTypeRef, usingPath))
            return emitUsingPointerLikeCast(codeGen, srcNodeRef, sourceTypeRef, dstTypeRef, usingPath);

        if (resolvedDstType.isBool() && srcType.isEnum())
        {
            const TypeRef     enumSourceTypeRef = srcType.payloadSymEnum().underlyingTypeRef();
            const TypeInfo&   enumSourceType    = typeMgr.get(enumSourceTypeRef);
            const MicroOpBits srcOpBits         = CodeGenTypeHelpers::numericOrBoolBits(enumSourceType);
            SWC_ASSERT(srcOpBits != MicroOpBits::Zero);

            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualRegisterForType(enumSourceTypeRef);
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitCmpRegImm(srcReg, ApInt(0, 64), srcOpBits);
            builder.emitSetCondReg(dstPayload.reg, MicroCond::NotEqual);
            return Result::Continue;
        }

        if (resolvedDstType.isBool() && (resolvedSrcType.isPointerLike() || resolvedSrcType.isReference() || resolvedSrcType.isMoveReference() || resolvedSrcType.isNull()))
        {
            MicroReg   srcReg             = srcPayload.reg;
            const bool addressBackedValue = !srcPayload.isAddress() && srcType.sizeOf(codeGen.ctx()) > 8;
            if (srcPayload.isAddress() || addressBackedValue)
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, MicroOpBits::B64);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitCmpRegImm(srcReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitSetCondReg(dstPayload.reg, MicroCond::NotEqual);
            return Result::Continue;
        }

        if (resolvedSrcType.isAnyPointer() && dstTypeRef == typeMgr.typeU64())
        {
            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, MicroOpBits::B64);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(dstPayload.reg, srcReg, MicroOpBits::B64);
            return Result::Continue;
        }

        if (isExplicitBitCast(codeGen) && resolvedSrcType.isScalarNumeric() && resolvedDstType.isScalarNumeric())
        {
            const MicroOpBits srcOpBits = CodeGenTypeHelpers::numericOrBoolBits(resolvedSrcType);
            const MicroOpBits dstOpBits = CodeGenTypeHelpers::numericOrBoolBits(resolvedDstType);
            SWC_ASSERT(srcOpBits != MicroOpBits::Zero);
            SWC_ASSERT(dstOpBits != MicroOpBits::Zero);

            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualRegisterForType(resolvedSrcTypeRef);
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(resolvedDstTypeRef);

            const uint32_t srcWidth = getNumBits(srcOpBits);
            const uint32_t dstWidth = getNumBits(dstOpBits);
            if (srcWidth >= dstWidth)
            {
                builder.emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (resolvedSrcType.isNumericSigned())
                builder.emitLoadSignedExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
            else
                builder.emitLoadZeroExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
            return Result::Continue;
        }

        if (srcIntLikeType && dstIntLikeType)
        {
            const MicroOpBits srcOpBits = CodeGenTypeHelpers::numericOrBoolBits(resolvedSrcType);
            const MicroOpBits dstOpBits = CodeGenTypeHelpers::numericOrBoolBits(resolvedDstType);
            SWC_ASSERT(srcOpBits != MicroOpBits::Zero);
            SWC_ASSERT(dstOpBits != MicroOpBits::Zero);

            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
            }

            SWC_RESULT(CodeGenSafety::emitIntLikeCastOverflowCheck(codeGen, codeGen.node(codeGen.curNodeRef()), srcReg, resolvedSrcType, resolvedDstType));

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();

            if (resolvedDstType.isBool())
            {
                CodeGenCompareHelpers::emitTruthyBool(codeGen, dstPayload.reg, srcReg, resolvedSrcType, srcOpBits);
                return Result::Continue;
            }

            const uint32_t srcWidth = getNumBits(srcOpBits);
            const uint32_t dstWidth = getNumBits(dstOpBits);
            if (srcWidth == dstWidth)
            {
                builder.emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (srcWidth > dstWidth)
            {
                builder.emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (resolvedSrcType.isNumericSigned())
            {
                builder.emitLoadSignedExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
                return Result::Continue;
            }

            builder.emitLoadZeroExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
            return Result::Continue;
        }

        if (sourceTypeRef == dstTypeRef)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        if (!((srcIntLikeType && dstFloatType) || (srcFloatType && dstFloatType) || (srcFloatType && dstIntLikeType)))
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const MicroOpBits srcOpBits = CodeGenTypeHelpers::numericOrBoolBits(resolvedSrcType);
        const MicroOpBits dstOpBits = CodeGenTypeHelpers::numericOrBoolBits(resolvedDstType);
        if (srcOpBits == MicroOpBits::Zero || dstOpBits == MicroOpBits::Zero)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        MicroReg srcReg = srcPayload.reg;
        if (srcPayload.isAddress())
        {
            srcReg = codeGen.nextVirtualRegisterForType(resolvedSrcTypeRef);
            builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
        }

        if (srcIntLikeType && dstFloatType)
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            if (resolvedSrcType.isIntLikeUnsigned())
            {
                dstPayload.reg = emitUnsignedIntToFloatReg(codeGen, srcReg, resolvedSrcType, dstTypeRef);
                return Result::Continue;
            }

            if (getNumBits(srcOpBits) < 32 || (dstOpBits == MicroOpBits::B64 && getNumBits(srcOpBits) == 32))
            {
                const MicroReg    widenedReg  = codeGen.nextVirtualIntRegister();
                const MicroOpBits widenedBits = dstOpBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                builder.emitLoadSignedExtendRegReg(widenedReg, srcReg, widenedBits, srcOpBits);
                srcReg = widenedReg;
            }

            dstPayload.reg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstPayload.reg, dstOpBits);
            builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertIntToFloat, dstOpBits);
            return Result::Continue;
        }

        if (srcFloatType && dstFloatType)
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            if (srcOpBits == dstOpBits)
            {
                dstPayload.reg = srcReg;
                return Result::Continue;
            }

            dstPayload.reg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstPayload.reg, dstOpBits);
            builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToFloat, srcOpBits);
            return Result::Continue;
        }

        if (srcFloatType && resolvedDstType.isBool())
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            CodeGenCompareHelpers::emitTruthyBool(codeGen, dstPayload.reg, srcReg, resolvedSrcType, srcOpBits);
            return Result::Continue;
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
        SWC_RESULT(CodeGenSafety::emitFloatToIntCastOverflowCheck(codeGen, codeGen.node(codeGen.curNodeRef()), srcReg, resolvedSrcType, resolvedDstType));
        builder.emitClearReg(dstPayload.reg, dstOpBits);
        builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToInt, srcOpBits);

        return Result::Continue;
    }
}

Result AstAsCastExpr::codeGenPreNodeChild(const CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && codeGen.sema().semaPayload<DynamicStructSwitchAsCastPayload>(codeGen.curNodeRef()))
        return Result::SkipChildren;

    return Result::Continue;
}

Result AstAutoCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitNumericCast(codeGen, nodeExprRef, codeGen.curViewType().typeRef());
}

Result AstCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitNumericCast(codeGen, nodeExprRef, codeGen.transparentPayloadTypeRef());
}

Result AstAsCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    if (codeGen.sema().semaPayload<DynamicStructSwitchAsCastPayload>(codeGen.curNodeRef()))
        return Result::Continue;

    return emitDynamicStructCast(codeGen, nodeExprRef, codeGen.viewType(nodeTypeRef).typeRef(), false);
}

Result AstIsTypeExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitDynamicStructCast(codeGen, nodeExprRef, codeGen.viewType(nodeTypeRef).typeRef(), true);
}

SWC_END_NAMESPACE();
