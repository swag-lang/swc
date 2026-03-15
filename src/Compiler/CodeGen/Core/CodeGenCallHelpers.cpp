#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
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

        uint32_t  shardIndex = 0;
        const Ref ref        = codeGen.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(value));
        if (ref != INVALID_REF)
            codeGen.builder().emitLoadRegPtrReloc(reg, value, cstRef);
        else
            codeGen.builder().emitLoadRegPtrImm(reg, value);
    }

    bool shouldMaterializeAddressBackedValue(CodeGen& codeGen, const TypeInfo& typeInfo, const ABITypeNormalize::NormalizedType& normalizedType)
    {
        if (normalizedType.isIndirect)
            return false;
        if (normalizedType.isFloat)
            return false;
        if (normalizedType.numBits != 64)
            return false;

        return typeInfo.sizeOf(codeGen.ctx()) > sizeof(uint64_t);
    }

    ABICall::PreparedArgKind abiPreparedArgKind(CallArgumentPassKind passKind)
    {
        switch (passKind)
        {
            case CallArgumentPassKind::Direct:
                return ABICall::PreparedArgKind::Direct;

            case CallArgumentPassKind::InterfaceObject:
                return ABICall::PreparedArgKind::InterfaceObject;

            default:
                SWC_UNREACHABLE();
        }
    }

    void setPayloadStorageKind(CodeGenNodePayload& payload, bool isIndirect)
    {
        if (isIndirect)
            payload.setIsAddress();
        else
            payload.setIsValue();
    }

    TypeRef resolveNormalizedArgTypeRef(CodeGen& codeGen, const std::vector<SymbolVariable*>& params, size_t argIndex, const SemaNodeView& argView)
    {
        TypeRef normalizedTypeRef = TypeRef::invalid();
        if (argIndex < params.size())
        {
            const SymbolVariable* param = params[argIndex];
            SWC_ASSERT(param != nullptr);
            normalizedTypeRef = param->typeRef();
        }

        if (normalizedTypeRef.isInvalid())
            return argView.typeRef();

        const TypeInfo& paramType = codeGen.ctx().typeMgr().get(normalizedTypeRef);
        if (paramType.isAnyVariadic())
            return argView.typeRef();

        return normalizedTypeRef;
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
                builder.emitLoadRegImm(outPayload.reg, ApInt(0, 64), MicroOpBits::B64);
                outPayload.setIsValue();
                return true;

            case ConstantKind::EnumValue:
                return emitMaterializedConstantPayload(codeGen, outPayload, targetTypeRef, cst.getEnumValue());

            case ConstantKind::Struct:
                builder.emitLoadRegPtrReloc(outPayload.reg, reinterpret_cast<uint64_t>(cst.getStruct().data()), cstRef);
                outPayload.setIsAddress();
                return true;

            case ConstantKind::Array:
                builder.emitLoadRegPtrReloc(outPayload.reg, reinterpret_cast<uint64_t>(cst.getArray().data()), cstRef);
                outPayload.setIsAddress();
                return true;

            case ConstantKind::Slice:
            {
                const ByteSpan    sliceBytes      = cst.getSlice();
                const TypeRef     runtimeTypeRef  = targetTypeRef.isValid() ? targetTypeRef : cst.typeRef();
                const TypeInfo&   sliceType       = codeGen.typeMgr().get(runtimeTypeRef);
                const TypeInfo&   elementType     = codeGen.typeMgr().get(sliceType.payloadTypeRef());
                const uint64_t    elementSize     = elementType.sizeOf(codeGen.ctx());
                const uint64_t    elementCount    = elementSize ? sliceBytes.size() / elementSize : 0;
                const ConstantRef runtimeSliceRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, runtimeTypeRef, sliceBytes.data(), elementCount);
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

        const ConstantValue& defaultCst = codeGen.cstMgr().get(defaultCstRef);
        if (defaultCst.typeRef().isValid())
        {
            const TypeRef defaultTypeRef = ctx.typeMgr().get(defaultCst.typeRef()).unwrap(ctx, defaultCst.typeRef(), TypeExpandE::Alias);
            if (defaultTypeRef.isValid() && defaultTypeRef == storageTypeRef && emitMaterializedConstantPayload(codeGen, outPayload, targetTypeRef, defaultCstRef))
                return true;
        }

        const TypeInfo& storageType = ctx.typeMgr().get(storageTypeRef);
        const uint64_t  rawSize     = storageType.sizeOf(ctx);
        if (rawSize == 0 || rawSize > std::numeric_limits<uint32_t>::max())
            return false;

        SmallVector<std::byte> rawBytes;
        rawBytes.resize(rawSize);
        std::memset(rawBytes.data(), 0, rawBytes.size());
        ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{rawBytes.data(), rawBytes.size()}, defaultCstRef, storageTypeRef);

        ConstantRef materializedCstRef = ConstantRef::invalid();
        if (storageType.isStruct() || storageType.isArray() || storageType.isAny() || storageType.isInterface())
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

    void materializePreparedDirectScalarArg(CodeGen& codeGen, CodeGenNodePayload& argPayload, TypeRef normalizedTypeRef, const ABITypeNormalize::NormalizedType& normalizedArg)
    {
        if (!normalizedTypeRef.isValid() || normalizedArg.isIndirect)
            return;

        TaskContext&    ctx            = codeGen.ctx();
        MicroBuilder&   builder        = codeGen.builder();
        const TypeInfo& normalizedType = ctx.typeMgr().get(normalizedTypeRef);
        if (normalizedType.isReference())
            return;

        const TypeRef   normalizedTypeUnwrapped = normalizedType.unwrap(ctx, normalizedTypeRef, TypeExpandE::Alias);
        const TypeRef   dstTypeRef              = normalizedTypeUnwrapped.isValid() ? normalizedTypeUnwrapped : normalizedTypeRef;
        const TypeInfo& dstType                 = ctx.typeMgr().get(dstTypeRef);

        if (argPayload.typeRef.isValid())
        {
            const TypeInfo& srcTypeInfo      = ctx.typeMgr().get(argPayload.typeRef);
            const TypeRef   srcTypeUnwrapped = srcTypeInfo.unwrap(ctx, argPayload.typeRef, TypeExpandE::Alias);
            const TypeRef   srcTypeRef       = srcTypeUnwrapped.isValid() ? srcTypeUnwrapped : argPayload.typeRef;
            const TypeInfo& srcType          = ctx.typeMgr().get(srcTypeRef);
            const auto      srcBits          = CodeGenTypeHelpers::numericOrBoolBits(srcType);
            const auto      dstBits          = CodeGenTypeHelpers::numericOrBoolBits(dstType);

            if (srcType.isIntLike() && dstType.isFloat() && srcBits != MicroOpBits::Zero && dstBits != MicroOpBits::Zero)
            {
                MicroReg srcReg = argPayload.reg;
                if (argPayload.isAddress())
                {
                    srcReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegMem(srcReg, argPayload.reg, 0, srcBits);
                }

                if (getNumBits(srcBits) < 32 || (dstBits == MicroOpBits::B64 && getNumBits(srcBits) == 32))
                {
                    const MicroReg    widenedReg  = codeGen.nextVirtualIntRegister();
                    const MicroOpBits widenedBits = dstBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                    if (srcType.isIntSigned())
                        builder.emitLoadSignedExtendRegReg(widenedReg, srcReg, widenedBits, srcBits);
                    else
                        builder.emitLoadZeroExtendRegReg(widenedReg, srcReg, widenedBits, srcBits);
                    srcReg = widenedReg;
                }

                const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
                builder.emitClearReg(dstReg, dstBits);
                builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertIntToFloat, dstBits);
                argPayload.reg     = dstReg;
                argPayload.typeRef = normalizedTypeRef;
                argPayload.setIsValue();
                return;
            }

            if (srcType.isFloat() && dstType.isFloat() && srcBits != MicroOpBits::Zero && dstBits != MicroOpBits::Zero)
            {
                MicroReg srcReg = argPayload.reg;
                if (argPayload.isAddress())
                {
                    srcReg = codeGen.nextVirtualFloatRegister();
                    builder.emitLoadRegMem(srcReg, argPayload.reg, 0, srcBits);
                }

                if (srcBits == dstBits)
                {
                    argPayload.reg     = srcReg;
                    argPayload.typeRef = normalizedTypeRef;
                    argPayload.setIsValue();
                    return;
                }

                const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
                builder.emitClearReg(dstReg, dstBits);
                builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertFloatToFloat, srcBits);
                argPayload.reg     = dstReg;
                argPayload.typeRef = normalizedTypeRef;
                argPayload.setIsValue();
                return;
            }
        }

        if (!argPayload.isAddress())
            return;

        MicroReg dstReg   = MicroReg::invalid();
        auto     loadBits = MicroOpBits::Zero;
        if (normalizedArg.isFloat)
        {
            if (normalizedArg.numBits != 32 && normalizedArg.numBits != 64)
                return;

            dstReg   = codeGen.nextVirtualFloatRegister();
            loadBits = microOpBitsFromBitWidth(normalizedArg.numBits);
        }
        else if (normalizedArg.numBits == 64 && normalizedType.sizeOf(codeGen.ctx()) == sizeof(uint64_t))
        {
            dstReg   = codeGen.nextVirtualIntRegister();
            loadBits = MicroOpBits::B64;
        }
        else
        {
            return;
        }

        builder.emitLoadRegMem(dstReg, argPayload.reg, 0, loadBits);
        argPayload.reg = dstReg;
        argPayload.setIsValue();
    }

    void fillPreparedDirectArgType(ABICall::PreparedArg& outPreparedArg, CodeGen& codeGen, const CallConv& callConv, const CodeGenNodePayload& argPayload, TypeRef normalizedTypeRef)
    {
        if (normalizedTypeRef.isInvalid())
            return;

        const TypeInfo&                        normalizedType = codeGen.ctx().typeMgr().get(normalizedTypeRef);
        const ABITypeNormalize::NormalizedType normalizedArg  = ABITypeNormalize::normalize(codeGen.ctx(), callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
        SWC_ASSERT(!shouldMaterializeAddressBackedValue(codeGen, normalizedType, normalizedArg));
        const bool passAddressRef  = normalizedType.isReference();
        outPreparedArg.isFloat     = normalizedArg.isFloat;
        outPreparedArg.numBits     = normalizedArg.numBits;
        outPreparedArg.isAddressed = argPayload.isAddress() && !normalizedArg.isIndirect && !passAddressRef;
    }

    void appendPreparedFixedArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, const std::vector<SymbolVariable*>& params, size_t argIndex, const ResolvedCallArgument& arg)
    {
        CodeGenNodePayload argPayload;
        TypeRef            normalizedTypeRef = TypeRef::invalid();
        const AstNodeRef   argRef            = arg.argRef;
        if (argRef.isValid())
        {
            const SemaNodeView argView = codeGen.viewType(argRef);
            normalizedTypeRef          = resolveNormalizedArgTypeRef(codeGen, params, argIndex, argView);
            if (const CodeGenNodePayload* payload = codeGen.safePayload(argRef))
            {
                argPayload = *payload;

                bool requiresTypedConstMaterialization = false;
                if (normalizedTypeRef.isValid() && argPayload.typeRef.isValid())
                {
                    const TaskContext& ctx             = codeGen.ctx();
                    const TypeRef      expectedTypeRef = ctx.typeMgr().get(normalizedTypeRef).unwrap(ctx, normalizedTypeRef, TypeExpandE::Alias);
                    const TypeRef      payloadTypeRef  = ctx.typeMgr().get(argPayload.typeRef).unwrap(ctx, argPayload.typeRef, TypeExpandE::Alias);
                    requiresTypedConstMaterialization  = expectedTypeRef.isValid() && payloadTypeRef.isValid() && expectedTypeRef != payloadTypeRef;
                }

                if (requiresTypedConstMaterialization)
                {
                    const SemaNodeView argConstView = codeGen.viewTypeConstant(argRef);
                    if (argConstView.cstRef().isValid())
                        SWC_INTERNAL_CHECK(materializeDefaultConstantPayload(codeGen, argPayload, normalizedTypeRef, argConstView.cstRef()));
                }
            }
            else
            {
                const SemaNodeView argConstView = codeGen.viewTypeConstant(argRef);
                SWC_ASSERT(argConstView.cstRef().isValid());
                SWC_INTERNAL_CHECK(materializeDefaultConstantPayload(codeGen, argPayload, normalizedTypeRef, argConstView.cstRef()));
            }
        }
        else
        {
            const SymbolVariable* param = params[argIndex];
            SWC_ASSERT(param != nullptr);
            SWC_ASSERT(argIndex < params.size());
            SWC_ASSERT(arg.defaultCstRef.isValid());
            normalizedTypeRef = param->typeRef();
            SWC_INTERNAL_CHECK(materializeDefaultConstantPayload(codeGen, argPayload, normalizedTypeRef, arg.defaultCstRef));
        }

        ABICall::PreparedArg preparedArg;
        if (normalizedTypeRef.isValid())
        {
            const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
            materializePreparedDirectScalarArg(codeGen, argPayload, normalizedTypeRef, normalizedArg);
        }

        preparedArg.srcReg = argPayload.reg;

        fillPreparedDirectArgType(preparedArg, codeGen, callConv, argPayload, normalizedTypeRef);
        preparedArg.kind = abiPreparedArgKind(arg.passKind);
        outArgs.push_back(preparedArg);
    }

    const CodeGenNodePayload* resolveCallPayload(CodeGen& codeGen, AstNodeRef calleeRef)
    {
        if (const CodeGenNodePayload* payload = codeGen.safePayload(calleeRef))
            return payload;

        const AstNodeRef resolvedRef = codeGen.viewZero(calleeRef).nodeRef();
        if (resolvedRef.isValid() && resolvedRef != calleeRef)
            return codeGen.safePayload(resolvedRef);

        return nullptr;
    }

    MicroReg materializeCallTargetReg(CodeGen& codeGen, const CodeGenNodePayload& calleePayload, const CallConv& callConv)
    {
        MicroBuilder&  builder   = codeGen.builder();
        const MicroReg targetReg = codeGen.nextVirtualIntRegister();
        if (calleePayload.isAddress())
            builder.emitLoadRegMem(targetReg, calleePayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(targetReg, calleePayload.reg, MicroOpBits::B64);

        builder.addVirtualRegForbiddenPhysRegs(targetReg, callConv.intArgRegs);
        builder.addVirtualRegForbiddenPhysReg(targetReg, callConv.intReturn);
        return targetReg;
    }

    void emitFunctionCall(CodeGen& codeGen, SymbolFunction& calledFunction, const ABICall::PreparedCall& preparedCall, MicroReg callTargetReg)
    {
        MicroBuilder&      builder      = codeGen.builder();
        const CallConvKind callConvKind = calledFunction.callConvKind();

        if (callTargetReg.isValid())
        {
            ABICall::callReg(builder, callConvKind, callTargetReg, preparedCall);
            return;
        }

        if (calledFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &calledFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &calledFunction, preparedCall);
    }

    void storeTypedVariadicElement(CodeGen& codeGen, MicroReg dstAddressReg, const CodeGenNodePayload& srcPayload, uint32_t elemSize)
    {
        MicroBuilder& builder = codeGen.builder();
        if (srcPayload.isAddress())
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, elemSize);
            return;
        }

        if (elemSize > 8)
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, elemSize);
            return;
        }

        if (elemSize == 1 || elemSize == 2 || elemSize == 4 || elemSize == 8)
        {
            builder.emitLoadMemReg(dstAddressReg, 0, srcPayload.reg, microOpBitsFromChunkSize(elemSize));
            return;
        }

        builder.emitLoadMemReg(dstAddressReg, 0, srcPayload.reg, MicroOpBits::B64);
    }
    void packTypedVariadicArgument(ABICall::PreparedArg& outPreparedArg, uint32_t& outTransientStackSize, CodeGen& codeGen, const CallConv& callConv, std::span<const ResolvedCallArgument> args, TypeRef variadicElemTypeRef, const ABITypeNormalize::NormalizedType& normalizedVariadic)
    {
        MicroBuilder& builder = codeGen.builder();
        SWC_ASSERT(normalizedVariadic.numBits == 64);
        SWC_ASSERT(!normalizedVariadic.isIndirect);

        TaskContext&    ctx          = codeGen.ctx();
        const TypeInfo& variadicType = ctx.typeMgr().get(variadicElemTypeRef);
        const uint64_t  rawElemSize  = variadicType.sizeOf(ctx);
        SWC_ASSERT(rawElemSize > 0 && rawElemSize <= std::numeric_limits<uint32_t>::max());

        const auto     elemSize      = static_cast<uint32_t>(rawElemSize);
        const uint32_t elemAlign     = std::max<uint32_t>(variadicType.alignOf(ctx), 1);
        const uint64_t variadicCount = args.size();

        uint64_t totalStorageSize = 0;
        for (uint64_t i = 0; i < variadicCount; ++i)
        {
            totalStorageSize = Math::alignUpU64(totalStorageSize, elemAlign);
            totalStorageSize += elemSize;
        }
        constexpr uint64_t sliceAlign     = alignof(Runtime::Slice<std::byte>);
        const uint64_t     sliceOffset    = Math::alignUpU64(totalStorageSize, sliceAlign);
        const uint64_t     totalFrameSize = sliceOffset + sizeof(Runtime::Slice<std::byte>);
        SWC_ASSERT(totalFrameSize <= std::numeric_limits<uint32_t>::max());

        outTransientStackSize = static_cast<uint32_t>(totalFrameSize);
        if (outTransientStackSize)
            builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(outTransientStackSize, 64), MicroOp::Subtract, MicroOpBits::B64);

        const MicroReg frameBaseReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);

        uint64_t offset = 0;
        for (uint64_t i = 0; i < variadicCount; ++i)
        {
            const AstNodeRef argRef = args[i].argRef;
            if (argRef.isInvalid())
                continue;

            const CodeGenNodePayload& argPayload = codeGen.payload(argRef);
            offset                               = Math::alignUpU64(offset, elemAlign);
            MicroReg dstAddressReg               = frameBaseReg;
            if (offset)
            {
                dstAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(dstAddressReg, frameBaseReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(dstAddressReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
            }
            storeTypedVariadicElement(codeGen, dstAddressReg, argPayload, elemSize);
            offset += elemSize;
        }

        MicroReg sliceAddrReg = frameBaseReg;
        if (sliceOffset)
        {
            sliceAddrReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(sliceAddrReg, frameBaseReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(sliceAddrReg, ApInt(sliceOffset, 64), MicroOp::Add, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, ptr), frameBaseReg, MicroOpBits::B64);
        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, ApInt(variadicCount, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, count), countReg, MicroOpBits::B64);

        outPreparedArg.srcReg      = sliceAddrReg;
        outPreparedArg.kind        = ABICall::PreparedArgKind::Direct;
        outPreparedArg.isFloat     = normalizedVariadic.isFloat;
        outPreparedArg.numBits     = normalizedVariadic.numBits;
        outPreparedArg.isAddressed = false;
    }

    struct UntypedVariadicArgInfo
    {
        AstNodeRef         argRef = AstNodeRef::invalid();
        CodeGenNodePayload argPayload;
        TypeRef            argTypeRef     = TypeRef::invalid();
        ConstantRef        typeInfoCstRef = ConstantRef::invalid();
        uint32_t           valueSize      = 0;
        uint32_t           valueAlign     = 1;
        bool               needsSpill     = false;
        uint64_t           spillOffset    = 0;
    };

    void packUntypedVariadicArgument(ABICall::PreparedArg& outPreparedArg, uint32_t& outTransientStackSize, CodeGen& codeGen, const CallConv& callConv, std::span<const ResolvedCallArgument> args, const ABITypeNormalize::NormalizedType& normalizedVariadic)
    {
        MicroBuilder& builder = codeGen.builder();
        SWC_ASSERT(normalizedVariadic.numBits == 64);
        SWC_ASSERT(!normalizedVariadic.isIndirect);

        TaskContext&                        ctx = codeGen.ctx();
        SmallVector<UntypedVariadicArgInfo> variadicInfos;
        variadicInfos.reserve(args.size());

        for (const ResolvedCallArgument& resolvedArg : args)
        {
            if (resolvedArg.argRef.isInvalid())
                continue;

            const CodeGenNodePayload& argPayload = codeGen.payload(resolvedArg.argRef);

            const SemaNodeView argView = codeGen.viewType(resolvedArg.argRef);
            SWC_ASSERT(argView.type());

            const TypeInfo& argType    = ctx.typeMgr().get(argView.typeRef());
            const uint64_t  rawArgSize = argType.sizeOf(ctx);
            SWC_ASSERT(rawArgSize > 0 && rawArgSize <= std::numeric_limits<uint32_t>::max());

            UntypedVariadicArgInfo info;
            info.argRef     = resolvedArg.argRef;
            info.argPayload = argPayload;
            info.argTypeRef = argView.typeRef();
            info.valueSize  = static_cast<uint32_t>(rawArgSize);
            info.valueAlign = std::max<uint32_t>(argType.alignOf(ctx), 1);

            ConstantRef  typeInfoCstRef = ConstantRef::invalid();
            const Result typeInfoRes    = codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, info.argTypeRef, info.argRef);
            SWC_INTERNAL_CHECK(typeInfoRes == Result::Continue);
            info.typeInfoCstRef = typeInfoCstRef;
            if (info.argPayload.reg == callConv.stackPointer)
            {
                info.argPayload.reg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(info.argPayload.reg, callConv.stackPointer, MicroOpBits::B64);
            }

            info.needsSpill = info.argPayload.isValue() && (info.valueSize <= 8 || argType.isAny());
            SWC_ASSERT(info.typeInfoCstRef.isValid());
            variadicInfos.push_back(info);
        }

        uint64_t spillStorageSize = 0;
        for (uint64_t i = 0; i < variadicInfos.size(); ++i)
        {
            UntypedVariadicArgInfo& info = variadicInfos[i];
            if (!info.needsSpill && info.argPayload.isValue() && info.valueSize > 8 && i + 1 < variadicInfos.size())
                info.needsSpill = true;

            if (info.needsSpill)
            {
                spillStorageSize = Math::alignUpU64(spillStorageSize, info.valueAlign);
                info.spillOffset = spillStorageSize;
                spillStorageSize += info.valueSize;
            }
        }

        const uint64_t     variadicCount = variadicInfos.size();
        constexpr uint64_t anyAlign      = alignof(Runtime::Any);
        const uint64_t     anyOffset     = Math::alignUpU64(spillStorageSize, anyAlign);
        const uint64_t     anyStorage    = variadicCount * sizeof(Runtime::Any);

        constexpr uint64_t sliceAlign     = alignof(Runtime::Slice<std::byte>);
        const uint64_t     sliceOffset    = Math::alignUpU64(anyOffset + anyStorage, sliceAlign);
        const uint64_t     totalFrameSize = sliceOffset + sizeof(Runtime::Slice<std::byte>);
        SWC_ASSERT(totalFrameSize <= std::numeric_limits<uint32_t>::max());

        outTransientStackSize = static_cast<uint32_t>(totalFrameSize);
        if (outTransientStackSize)
            builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(outTransientStackSize, 64), MicroOp::Subtract, MicroOpBits::B64);

        const MicroReg frameBaseReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);

        MicroReg anyBaseReg = frameBaseReg;
        if (anyOffset)
        {
            anyBaseReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(anyBaseReg, frameBaseReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(anyBaseReg, ApInt(anyOffset, 64), MicroOp::Add, MicroOpBits::B64);
        }

        for (uint64_t i = 0; i < variadicCount; ++i)
        {
            const UntypedVariadicArgInfo& info = variadicInfos[i];

            MicroReg anyEntryReg = anyBaseReg;
            if (i)
            {
                anyEntryReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(anyEntryReg, anyBaseReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(anyEntryReg, ApInt(i * sizeof(Runtime::Any), 64), MicroOp::Add, MicroOpBits::B64);
            }

            MicroReg valuePtrReg;
            if (info.needsSpill)
            {
                valuePtrReg = frameBaseReg;
                if (info.spillOffset)
                {
                    valuePtrReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(valuePtrReg, frameBaseReg, MicroOpBits::B64);
                    builder.emitOpBinaryRegImm(valuePtrReg, ApInt(info.spillOffset, 64), MicroOp::Add, MicroOpBits::B64);
                }
                storeTypedVariadicElement(codeGen, valuePtrReg, info.argPayload, info.valueSize);
            }
            else if (info.argPayload.isAddress())
            {
                valuePtrReg = info.argPayload.reg;
            }
            else
            {
                valuePtrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(valuePtrReg, info.argPayload.reg, MicroOpBits::B64);
            }

            builder.emitLoadMemReg(anyEntryReg, offsetof(Runtime::Any, value), valuePtrReg, MicroOpBits::B64);

            const ConstantValue& typeInfoCst = codeGen.cstMgr().get(info.typeInfoCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());

            const MicroReg typeInfoReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrReloc(typeInfoReg, typeInfoCst.getValuePointer(), info.typeInfoCstRef);
            builder.emitLoadMemReg(anyEntryReg, offsetof(Runtime::Any, type), typeInfoReg, MicroOpBits::B64);
        }

        MicroReg sliceAddrReg = frameBaseReg;
        if (sliceOffset)
        {
            sliceAddrReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(sliceAddrReg, frameBaseReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(sliceAddrReg, ApInt(sliceOffset, 64), MicroOp::Add, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, ptr), anyBaseReg, MicroOpBits::B64);
        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, ApInt(variadicCount, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, count), countReg, MicroOpBits::B64);

        outPreparedArg.srcReg      = sliceAddrReg;
        outPreparedArg.kind        = ABICall::PreparedArgKind::Direct;
        outPreparedArg.isFloat     = normalizedVariadic.isFloat;
        outPreparedArg.numBits     = normalizedVariadic.numBits;
        outPreparedArg.isAddressed = false;
    }

    void buildPreparedABIArguments(CodeGen& codeGen, const SymbolFunction& calledFunction, std::span<const ResolvedCallArgument> args, SmallVector<ABICall::PreparedArg>& outArgs, uint32_t& outTransientStackSize)
    {
        // Convert resolved semantic arguments into ABI-prepared argument descriptors.
        outArgs.clear();
        outArgs.reserve(args.size());
        outTransientStackSize                            = 0;
        const CallConvKind                  callConvKind = calledFunction.callConvKind();
        const CallConv&                     callConv     = CallConv::get(callConvKind);
        const std::vector<SymbolVariable*>& params       = calledFunction.parameters();
        const size_t                        numParams    = params.size();

        bool    hasVariadic           = false;
        bool    hasTypedVariadic      = false;
        size_t  variadicParamIdx      = 0;
        TypeRef typedVariadicElemType = TypeRef::invalid();

        if (!params.empty())
        {
            const SymbolVariable* lastParam = params.back();
            SWC_ASSERT(lastParam != nullptr);

            const TypeInfo& lastParamType = codeGen.ctx().typeMgr().get(lastParam->typeRef());
            if (lastParamType.isTypedVariadic())
            {
                hasVariadic           = true;
                hasTypedVariadic      = true;
                variadicParamIdx      = numParams - 1;
                typedVariadicElemType = lastParamType.payloadTypeRef();
            }
            else if (lastParamType.isVariadic())
            {
                hasVariadic      = true;
                hasTypedVariadic = false;
                variadicParamIdx = numParams - 1;
            }
        }

        size_t numFixedArgs = args.size();
        if (hasVariadic)
            numFixedArgs = std::min(args.size(), variadicParamIdx);

        for (size_t i = 0; i < numFixedArgs; ++i)
            appendPreparedFixedArg(outArgs, codeGen, callConv, params, i, args[i]);

        if (!hasVariadic)
            return;

        ABICall::PreparedArg variadicPreparedArg;
        SWC_ASSERT(params[variadicParamIdx] != nullptr);
        const TypeRef                               variadicParamTypeRef = params[variadicParamIdx]->typeRef();
        const ABITypeNormalize::NormalizedType      normalizedVariadic   = ABITypeNormalize::normalize(codeGen.ctx(), callConv, variadicParamTypeRef, ABITypeNormalize::Usage::Argument);
        const std::span<const ResolvedCallArgument> variadicArgs         = args.subspan(numFixedArgs);
        if (hasTypedVariadic)
            packTypedVariadicArgument(variadicPreparedArg, outTransientStackSize, codeGen, callConv, variadicArgs, typedVariadicElemType, normalizedVariadic);
        else
            packUntypedVariadicArgument(variadicPreparedArg, outTransientStackSize, codeGen, callConv, variadicArgs, normalizedVariadic);
        outArgs.push_back(variadicPreparedArg);
    }
}

Result CodeGenCallHelpers::codeGenCallExprCommon(CodeGen& codeGen, AstNodeRef calleeRef)
{
    MicroBuilder&                          builder        = codeGen.builder();
    const SemaNodeView                     currentView    = codeGen.curViewTypeSymbol();
    auto&                                  calledFunction = currentView.sym()->cast<SymbolFunction>();
    const CallConvKind                     callConvKind   = calledFunction.callConvKind();
    const CallConv&                        callConv       = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet  = ABITypeNormalize::normalize(codeGen.ctx(), callConv, currentView.typeRef(), ABITypeNormalize::Usage::Return);
    const CodeGenNodePayload*              calleePayload  = resolveCallPayload(codeGen, calleeRef);
    MicroReg                               callTargetReg  = MicroReg::invalid();

    if (calleePayload)
        callTargetReg = materializeCallTargetReg(codeGen, *calleePayload, callConv);

    SmallVector<ResolvedCallArgument> args;
    SmallVector<ABICall::PreparedArg> preparedArgs;
    codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), args);
    uint32_t transientStackSize = 0;
    buildPreparedABIArguments(codeGen, calledFunction, args, preparedArgs, transientStackSize);
    MicroReg hiddenRetStorageReg = MicroReg::invalid();
    if (normalizedRet.isIndirect)
    {
        const CodeGenNodePayload* nodePayload = codeGen.safePayload(codeGen.curNodeRef());
        if (nodePayload &&
            nodePayload->runtimeStorageSym != nullptr &&
            nodePayload->runtimeStorageSym->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) &&
            codeGen.localStackBaseReg().isValid())
            hiddenRetStorageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
    }

    // prepareArgs handles register placement, stack slots, and hidden indirect return arg.
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs, normalizedRet, hiddenRetStorageReg);
    CodeGenNodePayload&         nodePayload  = codeGen.setPayload(codeGen.curNodeRef(), currentView.typeRef());
    emitFunctionCall(codeGen, calledFunction, preparedCall, callTargetReg);
    if (transientStackSize)
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(transientStackSize, 64), MicroOp::Add, MicroOpBits::B64);

    ABICall::materializeReturnToReg(builder, nodePayload.reg, callConvKind, normalizedRet);
    setPayloadStorageKind(nodePayload, normalizedRet.isIndirect);

    return Result::Continue;
}

SWC_END_NAMESPACE();
