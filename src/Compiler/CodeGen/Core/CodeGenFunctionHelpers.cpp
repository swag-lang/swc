#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

    CodeGenNodePayload resolveCallRuntimeStoragePayload(CodeGen& codeGen, const SymbolVariable& storageSym)
    {
        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(storageSym))
            return *symbolPayload;

        if (!storageSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return {};
        if (!codeGen.localStackBaseReg().isValid())
            return {};

        CodeGenNodePayload localPayload;
        localPayload.typeRef = storageSym.typeRef();
        localPayload.setIsAddress();
        if (!storageSym.offset())
        {
            localPayload.reg = codeGen.localStackBaseReg();
        }
        else
        {
            MicroBuilder& builder = codeGen.builder();
            localPayload.reg      = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(localPayload.reg, codeGen.localStackBaseReg(), MicroOpBits::B64);
            builder.emitOpBinaryRegImm(localPayload.reg, ApInt(storageSym.offset(), 64), MicroOp::Add, MicroOpBits::B64);
        }

        codeGen.setVariablePayload(storageSym, localPayload);
        return localPayload;
    }

    MicroReg callRuntimeStorageAddressReg(CodeGen& codeGen, AstNodeRef callExprRef)
    {
        const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(callExprRef);
        if (!payload || payload->runtimeStorageSym == nullptr)
            return MicroReg::invalid();

        const CodeGenNodePayload storagePayload = resolveCallRuntimeStoragePayload(codeGen, *(payload->runtimeStorageSym));
        if (!storagePayload.isAddress())
            return MicroReg::invalid();
        if (!storagePayload.reg.isValid())
            return MicroReg::invalid();

        return storagePayload.reg;
    }

    MicroOpBits functionParameterLoadBits(bool isFloat, uint8_t numBits)
    {
        if (isFloat)
            return microOpBitsFromBitWidth(numBits);
        return MicroOpBits::B64;
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
        const uint64_t  rawSize     = storageType.sizeOf(ctx);
        if (rawSize == 0 || rawSize > std::numeric_limits<uint32_t>::max())
            return false;

        SmallVector<std::byte> rawBytes;
        rawBytes.resize(rawSize);
        std::memset(rawBytes.data(), 0, rawBytes.size());
        ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{rawBytes.data(), rawBytes.size()}, defaultCstRef, storageTypeRef);

        const std::string_view payloadView(reinterpret_cast<const char*>(rawBytes.data()), rawBytes.size());
        const std::string_view storedPayload = codeGen.cstMgr().addPayloadBuffer(payloadView);
        outPayload.typeRef                   = targetTypeRef;
        outPayload.setIsAddress();
        outPayload.reg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(outPayload.reg, reinterpret_cast<uint64_t>(storedPayload.data()), defaultCstRef);
        return true;
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
                    const TaskContext&  ctx           = codeGen.ctx();
                    const TypeRef expectedTypeRef     = codeGen.ctx().typeMgr().get(normalizedTypeRef).unwrap(ctx, normalizedTypeRef, TypeExpandE::Alias);
                    const TypeRef payloadTypeRef      = codeGen.ctx().typeMgr().get(argPayload.typeRef).unwrap(ctx, argPayload.typeRef, TypeExpandE::Alias);
                    requiresTypedConstMaterialization = expectedTypeRef.isValid() && payloadTypeRef.isValid() && expectedTypeRef != payloadTypeRef;
                }

                if (requiresTypedConstMaterialization)
                {
                    const SemaNodeView argConstView = codeGen.viewTypeConstant(argRef);
                    if (!argConstView.cstRef().isValid())
                        return;
                    if (!materializeDefaultConstantPayload(codeGen, argPayload, normalizedTypeRef, argConstView.cstRef()))
                        return;
                }
            }
            else
            {
                const SemaNodeView argConstView = codeGen.viewTypeConstant(argRef);
                if (!materializeDefaultConstantPayload(codeGen, argPayload, normalizedTypeRef, argConstView.cstRef()))
                    return;
            }
        }
        else
        {
            if (arg.defaultCstRef.isInvalid())
                return;
            if (argIndex >= params.size())
                return;
            const SymbolVariable* param = params[argIndex];
            SWC_ASSERT(param != nullptr);
            normalizedTypeRef = param->typeRef();
            if (!materializeDefaultConstantPayload(codeGen, argPayload, normalizedTypeRef, arg.defaultCstRef))
                return;
        }

        ABICall::PreparedArg preparedArg;
        preparedArg.srcReg = argPayload.reg;

        fillPreparedDirectArgType(preparedArg, codeGen, callConv, argPayload, normalizedTypeRef);
        preparedArg.kind = abiPreparedArgKind(arg.passKind);
        outArgs.push_back(preparedArg);
    }

    void emitFunctionCall(CodeGen& codeGen, SymbolFunction& calledFunction, const AstNodeRef& calleeRef, const ABICall::PreparedCall& preparedCall)
    {
        MicroBuilder&             builder       = codeGen.builder();
        const CallConvKind        callConvKind  = calledFunction.callConvKind();
        const CodeGenNodePayload* calleePayload = codeGen.safePayload(calleeRef);

        if (calleePayload)
        {
            ABICall::callReg(builder, callConvKind, calleePayload->reg, preparedCall);
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
            SWC_ASSERT(typeInfoRes == Result::Continue);
            if (typeInfoRes != Result::Continue)
                SWC_INTERNAL_ERROR();
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

CodeGenFunctionHelpers::FunctionParameterInfo CodeGenFunctionHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, bool hasIndirectReturnArg)
{
    SWC_ASSERT(symVar.hasParameterIndex());

    FunctionParameterInfo                  result;
    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const uint32_t                         parameterIndex  = symVar.parameterIndex();
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar.typeRef(), ABITypeNormalize::Usage::Argument);

    result.slotIndex     = hasIndirectReturnArg ? parameterIndex + 1 : parameterIndex;
    result.isFloat       = normalizedParam.isFloat;
    result.isIndirect    = normalizedParam.isIndirect;
    result.opBits        = functionParameterLoadBits(normalizedParam.isFloat, normalizedParam.numBits);
    result.isRegisterArg = result.slotIndex < callConv.numArgRegisterSlots();
    return result;
}

CodeGenFunctionHelpers::FunctionParameterInfo CodeGenFunctionHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    const CallConv&                        callConv      = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);
    return functionParameterInfo(codeGen, symbolFunc, symVar, normalizedRet.isIndirect);
}

void CodeGenFunctionHelpers::emitLoadFunctionParameterToReg(CodeGen& codeGen, const SymbolFunction& symbolFunc, const FunctionParameterInfo& paramInfo, MicroReg dstReg)
{
    const CallConv& callConv = CallConv::get(symbolFunc.callConvKind());
    MicroBuilder&   builder  = codeGen.builder();

    if (paramInfo.isRegisterArg)
    {
        if (paramInfo.isFloat)
        {
            SWC_ASSERT(paramInfo.slotIndex < callConv.floatArgRegs.size());
            builder.emitLoadRegReg(dstReg, callConv.floatArgRegs[paramInfo.slotIndex], paramInfo.opBits);
        }
        else
        {
            SWC_ASSERT(paramInfo.slotIndex < callConv.intArgRegs.size());
            builder.emitLoadRegReg(dstReg, callConv.intArgRegs[paramInfo.slotIndex], paramInfo.opBits);
        }
    }
    else
    {
        const uint64_t frameOffset = ABICall::incomingArgFrameOffset(callConv, paramInfo.slotIndex);
        builder.emitLoadRegMem(dstReg, callConv.framePointer, frameOffset, paramInfo.opBits);
    }
}

CodeGenNodePayload CodeGenFunctionHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo)
{
    CodeGenNodePayload outPayload;

    outPayload.typeRef = symVar.typeRef();
    outPayload.reg     = codeGen.nextVirtualRegisterForType(symVar.typeRef());
    emitLoadFunctionParameterToReg(codeGen, symbolFunc, paramInfo, outPayload.reg);

    if (paramInfo.isIndirect)
        outPayload.setIsAddress();
    else
        outPayload.setIsValue();

    codeGen.setVariablePayload(symVar, outPayload);
    return outPayload;
}

CodeGenNodePayload CodeGenFunctionHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    const FunctionParameterInfo paramInfo = functionParameterInfo(codeGen, symbolFunc, symVar);
    return materializeFunctionParameter(codeGen, symbolFunc, symVar, paramInfo);
}

Result CodeGenFunctionHelpers::codeGenCallExprCommon(CodeGen& codeGen, AstNodeRef calleeRef)
{
    MicroBuilder&                          builder        = codeGen.builder();
    const SemaNodeView                     calleeView     = codeGen.viewZero(calleeRef);
    const SemaNodeView                     currentView    = codeGen.curViewTypeSymbol();
    auto&                                  calledFunction = currentView.sym()->cast<SymbolFunction>();
    const CallConvKind                     callConvKind   = calledFunction.callConvKind();
    const CallConv&                        callConv       = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet  = ABITypeNormalize::normalize(codeGen.ctx(), callConv, currentView.typeRef(), ABITypeNormalize::Usage::Return);

    SmallVector<ResolvedCallArgument> args;
    SmallVector<ABICall::PreparedArg> preparedArgs;
    codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), args);
    uint32_t transientStackSize = 0;
    buildPreparedABIArguments(codeGen, calledFunction, args, preparedArgs, transientStackSize);
    MicroReg hiddenRetStorageReg = MicroReg::invalid();
    if (normalizedRet.isIndirect)
        hiddenRetStorageReg = callRuntimeStorageAddressReg(codeGen, codeGen.curNodeRef());

    // prepareArgs handles register placement, stack slots, and hidden indirect return arg.
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs, normalizedRet, hiddenRetStorageReg);
    CodeGenNodePayload&         nodePayload  = codeGen.setPayload(codeGen.curNodeRef(), currentView.typeRef());
    emitFunctionCall(codeGen, calledFunction, calleeView.nodeRef(), preparedCall);
    if (transientStackSize)
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(transientStackSize, 64), MicroOp::Add, MicroOpBits::B64);

    ABICall::materializeReturnToReg(builder, nodePayload.reg, callConvKind, normalizedRet);
    setPayloadStorageKind(nodePayload, normalizedRet.isIndirect);

    return Result::Continue;
}

SWC_END_NAMESPACE();
