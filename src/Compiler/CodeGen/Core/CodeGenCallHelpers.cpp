#include "pch.h"
#include "Support/Report/Assert.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void emitPointerConstant(CodeGen& codeGen, MicroReg reg, uint64_t value, ConstantRef cstRef)
    {
        if (!value)
        {
            codeGen.builder().emitLoadRegImm(reg, ApInt(0, 64), MicroOpBits::B64);
            return;
        }

        DataSegmentRef sourceRef;
        if (codeGen.cstMgr().resolveConstantDataSegmentRef(sourceRef, cstRef, reinterpret_cast<const void*>(value)))
            codeGen.builder().emitLoadRegPtrReloc(reg, value, cstRef);
        else
            codeGen.builder().emitLoadRegPtrImm(reg, value);
    }

    bool prefersAddressBackedCallConstantPayload(const TypeInfo& typeInfo)
    {
        return typeInfo.isStruct() ||
               typeInfo.isArray() ||
               typeInfo.isAggregateStruct() ||
               typeInfo.isAggregateArray() ||
               typeInfo.isAny() ||
               typeInfo.isInterface() ||
               typeInfo.isString() ||
               typeInfo.isSlice();
    }

    bool emitMaterializedConstantPayload(CodeGen& codeGen, CodeGenNodePayload& outPayload, TypeRef targetTypeRef, ConstantRef cstRef)
    {
        if (!cstRef.isValid())
            return false;

        const ConstantValue& cst     = codeGen.cstMgr().get(cstRef);
        MicroBuilder&        builder = codeGen.builder();

        outPayload.typeRef = targetTypeRef;
        outPayload.reg     = codeGen.nextVirtualIntRegister();

        switch (cst.kind())
        {
            case ConstantKind::Bool:
                builder.emitLoadRegImm(outPayload.reg, ApInt(cst.getBool() ? 1 : 0, 64), MicroOpBits::B64);
                outPayload.setIsValue();
                return true;

            case ConstantKind::Int:
            {
                const ApsInt& val = cst.getInt();
                if (!val.fits64())
                    return false;

                builder.emitLoadRegImm(outPayload.reg, ApInt(static_cast<uint64_t>(val.asI64()), 64), MicroOpBits::B64);
                outPayload.setIsValue();
                return true;
            }

            case ConstantKind::Float:
            {
                const ApFloat& value = cst.getFloat();
                outPayload.reg       = codeGen.nextVirtualFloatRegister();
                if (value.bitWidth() == 32)
                {
                    const double   widenedValue = value.asFloat();
                    const uint64_t widenedBits  = std::bit_cast<uint64_t>(widenedValue);
                    const MicroReg widenedReg   = codeGen.nextVirtualFloatRegister();
                    builder.emitLoadRegImm(widenedReg, ApInt(widenedBits, 64), MicroOpBits::B64);
                    builder.emitClearReg(outPayload.reg, MicroOpBits::B32);
                    builder.emitOpBinaryRegReg(outPayload.reg, widenedReg, MicroOp::ConvertFloatToFloat, MicroOpBits::B64);
                    outPayload.setIsValue();
                    return true;
                }

                if (value.bitWidth() == 64)
                {
                    const auto bits = std::bit_cast<uint64_t>(value.asDouble());
                    builder.emitLoadRegImm(outPayload.reg, ApInt(bits, 64), MicroOpBits::B64);
                    outPayload.setIsValue();
                    return true;
                }

                return false;
            }

            case ConstantKind::String:
            {
                const std::string_view value               = cst.getString();
                const TypeRef          runtimeTypeRef      = targetTypeRef.isValid() ? targetTypeRef : codeGen.typeMgr().typeString();
                const ConstantRef      runtimeStringCstRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, runtimeTypeRef, value.data(), value.size());
                if (runtimeStringCstRef.isInvalid())
                    return false;
                const ConstantValue& runtimeStringCst = codeGen.cstMgr().get(runtimeStringCstRef);
                builder.emitLoadRegPtrReloc(outPayload.reg, reinterpret_cast<uint64_t>(runtimeStringCst.getStruct().data()), runtimeStringCstRef);
                outPayload.setIsValue();
                return true;
            }

            case ConstantKind::ValuePointer:
                emitPointerConstant(codeGen, outPayload.reg, cst.getValuePointer(), cstRef);
                outPayload.setIsValue();
                return true;

            case ConstantKind::BlockPointer:
                emitPointerConstant(codeGen, outPayload.reg, cst.getBlockPointer(), cstRef);
                outPayload.setIsValue();
                return true;

            case ConstantKind::Null:
            {
                if (targetTypeRef.isValid())
                {
                    const TypeInfo& targetType = codeGen.typeMgr().get(targetTypeRef);
                    const uint64_t  rawSize    = targetType.sizeOf(codeGen.ctx());
                    if (rawSize > sizeof(uint64_t))
                    {
                        SWC_ASSERT(rawSize <= std::numeric_limits<uint32_t>::max());

                        SmallVector<std::byte> rawBytes;
                        rawBytes.resize(rawSize);
                        std::memset(rawBytes.data(), 0, rawBytes.size());
                        SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{rawBytes.data(), rawBytes.size()}, cstRef, targetTypeRef) == Result::Continue);

                        ConstantRef typedNullCstRef = ConstantRef::invalid();
                        if (targetType.isStruct() || targetType.isArray() || targetType.isAny() || targetType.isInterface() || targetType.isString() || targetType.isSlice())
                        {
                            typedNullCstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, targetTypeRef, ByteSpan{rawBytes.data(), rawBytes.size()});
                        }
                        else
                        {
                            const ConstantValue typedNullCst = ConstantValue::make(codeGen.ctx(), rawBytes.data(), targetTypeRef);
                            if (typedNullCst.kind() == ConstantKind::Invalid)
                                return false;

                            typedNullCstRef = codeGen.cstMgr().addConstant(codeGen.ctx(), typedNullCst);
                        }

                        if (typedNullCstRef.isInvalid())
                            return false;

                        return emitMaterializedConstantPayload(codeGen, outPayload, targetTypeRef, typedNullCstRef);
                    }
                }

                builder.emitLoadRegImm(outPayload.reg, ApInt(0, 64), MicroOpBits::B64);
                outPayload.setIsValue();
                return true;
            }

            case ConstantKind::EnumValue:
                return emitMaterializedConstantPayload(codeGen, outPayload, targetTypeRef, cst.getEnumValue());

            case ConstantKind::Struct:
            {
                const ConstantRef safeCstRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, cstRef, targetTypeRef.isValid() ? targetTypeRef : cst.typeRef());
                if (safeCstRef.isInvalid())
                    return false;
                const ConstantValue& safeCst = codeGen.cstMgr().get(safeCstRef);
                builder.emitLoadRegPtrReloc(outPayload.reg, reinterpret_cast<uint64_t>(safeCst.getStruct().data()), safeCstRef);
                outPayload.setIsAddress();
                return true;
            }

            case ConstantKind::Array:
            {
                const ConstantRef safeCstRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, cstRef, targetTypeRef.isValid() ? targetTypeRef : cst.typeRef());
                if (safeCstRef.isInvalid())
                    return false;
                const ConstantValue& safeCst = codeGen.cstMgr().get(safeCstRef);
                builder.emitLoadRegPtrReloc(outPayload.reg, reinterpret_cast<uint64_t>(safeCst.getArray().data()), safeCstRef);
                outPayload.setIsAddress();
                return true;
            }

            case ConstantKind::Slice:
            {
                const ByteSpan    sliceBytes      = cst.getSlice();
                const TypeRef     runtimeTypeRef  = targetTypeRef.isValid() ? targetTypeRef : cst.typeRef();
                const TypeInfo&   sliceType       = codeGen.typeMgr().get(runtimeTypeRef);
                const uint64_t    elementCount    = cst.getSliceCount();
                const ConstantRef safeArrayCstRef = CodeGenConstantHelpers::materializeStaticArrayBufferConstant(codeGen, sliceType.payloadTypeRef(), sliceBytes, elementCount);
                if (safeArrayCstRef.isInvalid())
                    return false;
                const ConstantValue& safeArrayCst    = codeGen.cstMgr().get(safeArrayCstRef);
                const ConstantRef    runtimeSliceRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, runtimeTypeRef, safeArrayCst.getArray().data(), elementCount);
                if (runtimeSliceRef.isInvalid())
                    return false;
                const ConstantValue& runtimeSliceCst = codeGen.cstMgr().get(runtimeSliceRef);
                builder.emitLoadRegPtrReloc(outPayload.reg, reinterpret_cast<uint64_t>(runtimeSliceCst.getStruct().data()), runtimeSliceRef);
                outPayload.setIsValue();
                return true;
            }

            default:
                return false;
        }
    }

    bool materializeDefaultConstantPayload(CodeGen& codeGen, CodeGenNodePayload& outPayload, TypeRef targetTypeRef, ConstantRef defaultCstRef)
    {
        if (!targetTypeRef.isValid() || !defaultCstRef.isValid())
            return false;

        TaskContext&    ctx              = codeGen.ctx();
        const TypeInfo& targetType       = ctx.typeMgr().get(targetTypeRef);
        TypeRef         storageTypeRef   = targetTypeRef;
        const TypeRef   unaliasedTypeRef = targetType.unwrap(ctx, targetTypeRef, TypeExpandE::Alias);
        if (unaliasedTypeRef.isValid())
            storageTypeRef = unaliasedTypeRef;
        const TypeInfo& storageType = ctx.typeMgr().get(storageTypeRef);

        const ConstantValue& defaultCst = codeGen.cstMgr().get(defaultCstRef);
        if (prefersAddressBackedCallConstantPayload(storageType))
        {
            const uint64_t rawSize = storageType.sizeOf(ctx);
            if (rawSize == 0 || rawSize > std::numeric_limits<uint32_t>::max())
                return false;

            SmallVector<std::byte> rawBytes;
            rawBytes.resize(rawSize);
            std::memset(rawBytes.data(), 0, rawBytes.size());
            if (ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{rawBytes.data(), rawBytes.size()}, defaultCstRef, storageTypeRef) != Result::Continue)
                return false;

            const ConstantRef materializedCstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, storageTypeRef, ByteSpan{rawBytes.data(), rawBytes.size()});
            if (materializedCstRef.isInvalid())
                return false;

            return emitMaterializedConstantPayload(codeGen, outPayload, targetTypeRef, materializedCstRef);
        }

        if ((defaultCst.isNull() || defaultCst.isValuePointer() || defaultCst.isBlockPointer()) &&
            emitMaterializedConstantPayload(codeGen, outPayload, targetTypeRef, defaultCstRef))
            return true;

        if (defaultCst.typeRef().isValid())
        {
            const TypeRef defaultTypeRef = ctx.typeMgr().get(defaultCst.typeRef()).unwrap(ctx, defaultCst.typeRef(), TypeExpandE::Alias);
            if (defaultTypeRef.isValid() && defaultTypeRef == storageTypeRef && emitMaterializedConstantPayload(codeGen, outPayload, targetTypeRef, defaultCstRef))
                return true;
        }

        const uint64_t rawSize = storageType.sizeOf(ctx);
        if (rawSize == 0 || rawSize > std::numeric_limits<uint32_t>::max())
            return false;

        SmallVector<std::byte> rawBytes;
        rawBytes.resize(rawSize);
        std::memset(rawBytes.data(), 0, rawBytes.size());
        if (ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{rawBytes.data(), rawBytes.size()}, defaultCstRef, storageTypeRef) != Result::Continue)
            return false;

        ConstantRef materializedCstRef = ConstantRef::invalid();
        if (storageType.isStruct() || storageType.isArray() || storageType.isAggregateStruct() || storageType.isAggregateArray() || storageType.isAny() || storageType.isInterface() || storageType.isString() || storageType.isSlice())
        {
            materializedCstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, storageTypeRef, ByteSpan{rawBytes.data(), rawBytes.size()});
        }
        else
        {
            const ConstantValue materializedCst = ConstantValue::make(codeGen.ctx(), rawBytes.data(), storageTypeRef);
            if (materializedCst.kind() == ConstantKind::Invalid)
                return false;

            materializedCstRef = codeGen.cstMgr().addConstant(codeGen.ctx(), materializedCst);
        }

        if (materializedCstRef.isInvalid())
            return false;

        return emitMaterializedConstantPayload(codeGen, outPayload, targetTypeRef, materializedCstRef);
    }
}

void CodeGenCallHelpers::appendDirectPreparedArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, TypeRef argTypeRef, MicroReg srcReg)
{
    const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, argTypeRef, ABITypeNormalize::Usage::Argument);

    ABICall::PreparedArg arg;
    arg.srcReg      = srcReg;
    arg.kind        = ABICall::PreparedArgKind::Direct;
    arg.isFloat     = normalizedArg.isFloat;
    arg.isSigned    = normalizedArg.isSigned;
    arg.isAddressed = false;
    arg.numBits     = normalizedArg.numBits;
    outArgs.push_back(arg);
}

void CodeGenCallHelpers::appendPreparedStringCompareArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, const CodeGenNodePayload& operandPayload, TypeRef argTypeRef)
{
    const TypeInfo&                        argType       = codeGen.typeMgr().get(argTypeRef);
    const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, argTypeRef, ABITypeNormalize::Usage::Argument);

    ABICall::PreparedArg preparedArg;
    preparedArg.srcReg      = operandPayload.reg;
    preparedArg.kind        = ABICall::PreparedArgKind::Direct;
    preparedArg.isFloat     = normalizedArg.isFloat;
    preparedArg.isAddressed = operandPayload.isAddress() && !normalizedArg.isIndirect && !argType.isReference();
    preparedArg.numBits     = normalizedArg.numBits;
    outArgs.push_back(preparedArg);
}
bool CodeGenCallHelpers::materializeTypedConstantPayload(CodeGen& codeGen, CodeGenNodePayload& outPayload, TypeRef targetTypeRef, ConstantRef constantRef)
{
    return materializeDefaultConstantPayload(codeGen, outPayload, targetTypeRef, constantRef);
}
SWC_END_NAMESPACE();
