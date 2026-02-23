#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool shouldPassAddressAsValue(CodeGen& codeGen, TypeRef typeRef, const ABITypeNormalize::NormalizedType& normalizedType)
    {
        if (typeRef.isInvalid())
            return false;
        if (normalizedType.isIndirect)
            return false;
        if (normalizedType.isFloat)
            return false;
        if (normalizedType.numBits != 64)
            return false;

        const TypeInfo& typeInfo = codeGen.ctx().typeMgr().get(typeRef);
        return typeInfo.sizeOf(codeGen.ctx()) > sizeof(uint64_t);
    }

    MicroReg materializeAddressValueCopy(CodeGen& codeGen, MicroReg srcAddressReg, uint32_t copySize)
    {
        SWC_ASSERT(copySize > 0);
        std::byte* const storage = codeGen.compiler().allocateArray<std::byte>(copySize);

        MicroBuilder&  builder  = codeGen.builder();
        const MicroReg dstReg   = codeGen.nextVirtualIntRegister();
        const uint64_t dstValue = reinterpret_cast<uint64_t>(storage);
        builder.emitLoadRegPtrImm(dstReg, dstValue);
        CodeGenHelpers::emitMemCopy(codeGen, dstReg, srcAddressReg, copySize);
        return dstReg;
    }

    void buildLocalStackLayout(CodeGen& codeGen)
    {
        const auto& localSymbols = codeGen.function().localVariables();
        if (localSymbols.empty())
            return;

        const CallConv& callConv  = CallConv::get(codeGen.function().callConvKind());
        uint64_t        frameSize = 0;
        for (const SymbolVariable* symVar : localSymbols)
        {
            SWC_ASSERT(symVar != nullptr);
            const TypeRef typeRef = symVar->typeRef();
            SWC_ASSERT(typeRef.isValid());

            const TypeInfo& typeInfo  = codeGen.typeMgr().get(typeRef);
            const uint32_t  size      = static_cast<uint32_t>(typeInfo.sizeOf(codeGen.ctx()));
            const uint32_t  alignment = std::max<uint32_t>(typeInfo.alignOf(codeGen.ctx()), 1);
            SWC_ASSERT(size > 0);

            const uint32_t symOffset = symVar->offset();
            codeGen.setLocalStackSlot(*symVar, {.offset = symOffset, .size = size, .align = alignment});
            frameSize = std::max<uint64_t>(frameSize, symOffset + size);
        }

        const uint32_t stackAlignment = callConv.stackAlignment ? callConv.stackAlignment : 16;
        frameSize                     = Math::alignUpU64(frameSize, stackAlignment);
        SWC_ASSERT(frameSize <= std::numeric_limits<uint32_t>::max());
        codeGen.setLocalStackFrameSize(static_cast<uint32_t>(frameSize));
    }

    void emitLocalStackFramePrologue(CodeGen& codeGen, CallConvKind callConvKind)
    {
        if (!codeGen.hasLocalStackFrame())
            return;

        const CallConv& callConv  = CallConv::get(callConvKind);
        MicroBuilder&   builder   = codeGen.builder();
        const uint32_t  frameSize = codeGen.localStackFrameSize();
        SWC_ASSERT(frameSize != 0);
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(frameSize, 64), MicroOp::Subtract, MicroOpBits::B64);

        const MicroReg frameBaseReg = callConv.framePointer;
        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);
        codeGen.setLocalStackBaseReg(frameBaseReg);
    }

    void emitLocalStackFrameEpilogue(CodeGen& codeGen, CallConvKind callConvKind)
    {
        if (!codeGen.hasLocalStackFrame())
            return;

        const CallConv& callConv = CallConv::get(callConvKind);
        codeGen.builder().emitOpBinaryRegImm(callConv.stackPointer, ApInt(codeGen.localStackFrameSize(), 64), MicroOp::Add, MicroOpBits::B64);
    }

    MicroReg parameterSourcePhysReg(const CallConv& callConv, const CodeGenHelpers::FunctionParameterInfo& paramInfo)
    {
        if (paramInfo.isFloat)
        {
            SWC_ASSERT(paramInfo.slotIndex < callConv.floatArgRegs.size());
            return callConv.floatArgRegs[paramInfo.slotIndex];
        }

        SWC_ASSERT(paramInfo.slotIndex < callConv.intArgRegs.size());
        return callConv.intArgRegs[paramInfo.slotIndex];
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

    void emitFunctionCall(CodeGen& codeGen, SymbolFunction& calledFunction, const AstNodeRef& calleeRef, const ABICall::PreparedCall& preparedCall)
    {
        MicroBuilder&             builder       = codeGen.builder();
        const CallConvKind        callConvKind  = calledFunction.callConvKind();
        const CodeGenNodePayload* calleePayload = codeGen.payload(calleeRef);

        if (calleePayload)
        {
            ABICall::callReg(builder, callConvKind, calleePayload->reg, preparedCall);
            return;
        }

        const MicroReg callTargetReg = codeGen.nextVirtualIntRegister();
        if (calledFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &calledFunction, callTargetReg, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &calledFunction, callTargetReg, preparedCall);
    }

    void collectFunctionParameterInfos(SmallVector<CodeGenHelpers::FunctionParameterInfo>& outParamInfos, CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        const std::vector<SymbolVariable*>& params = symbolFunc.parameters();
        outParamInfos.clear();
        if (params.empty())
            return;

        outParamInfos.resize(params.size());

        const CallConv&                        callConv             = CallConv::get(symbolFunc.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet        = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);
        const bool                             hasIndirectReturnArg = normalizedRet.isIndirect;
        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* const symVar = params[i];
            SWC_ASSERT(symVar != nullptr);
            outParamInfos[i] = CodeGenHelpers::functionParameterInfo(codeGen, symbolFunc, *symVar, hasIndirectReturnArg);
        }
    }

    void materializeRegisterParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc, std::span<const CodeGenHelpers::FunctionParameterInfo> paramInfos)
    {
        const CallConv&                     callConv = CallConv::get(symbolFunc.callConvKind());
        const std::vector<SymbolVariable*>& params   = symbolFunc.parameters();
        MicroBuilder&                       builder  = codeGen.builder();
        SWC_ASSERT(paramInfos.size() == params.size());

        SmallVector<uint32_t> registerParamIndices;
        registerParamIndices.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* const symVar = params[i];
            SWC_ASSERT(symVar != nullptr);
            const CodeGenHelpers::FunctionParameterInfo paramInfo = paramInfos[i];
            if (!paramInfo.isRegisterArg)
                continue;

            registerParamIndices.push_back(static_cast<uint32_t>(i));
        }

        for (size_t i = 0; i < registerParamIndices.size(); ++i)
        {
            const uint32_t              paramIndex = registerParamIndices[i];
            const SymbolVariable* const symVar     = params[paramIndex];
            SWC_ASSERT(symVar != nullptr);
            const CodeGenHelpers::FunctionParameterInfo paramInfo = paramInfos[paramIndex];

            CodeGenNodePayload symbolPayload;
            symbolPayload.reg     = paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            symbolPayload.typeRef = symVar->typeRef();

            SmallVector<MicroReg> futureSourceRegs;
            futureSourceRegs.reserve(registerParamIndices.size() - i - 1);
            for (size_t j = i + 1; j < registerParamIndices.size(); ++j)
            {
                const uint32_t                              laterParamIndex = registerParamIndices[j];
                const CodeGenHelpers::FunctionParameterInfo laterParamInfo  = paramInfos[laterParamIndex];
                futureSourceRegs.push_back(parameterSourcePhysReg(callConv, laterParamInfo));
            }

            builder.addVirtualRegForbiddenPhysRegs(symbolPayload.reg, futureSourceRegs);
            CodeGenHelpers::emitLoadFunctionParameterToReg(codeGen, symbolFunc, paramInfo, symbolPayload.reg);
            setPayloadStorageKind(symbolPayload, paramInfo.isIndirect);

            codeGen.setVariablePayload(*symVar, symbolPayload);
        }
    }

    void materializeStackParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc, std::span<const CodeGenHelpers::FunctionParameterInfo> paramInfos)
    {
        const std::vector<SymbolVariable*>& params = symbolFunc.parameters();
        SWC_ASSERT(paramInfos.size() == params.size());

        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* const symVar = params[i];
            SWC_ASSERT(symVar != nullptr);
            const CodeGenHelpers::FunctionParameterInfo paramInfo = paramInfos[i];
            if (paramInfo.isRegisterArg)
                continue;

            CodeGenHelpers::materializeFunctionParameter(codeGen, symbolFunc, *symVar, paramInfo);
        }
    }

    void storeTypedVariadicElement(CodeGen& codeGen, MicroReg dstAddressReg, const CodeGenNodePayload& srcPayload, uint32_t elemSize)
    {
        MicroBuilder& builder = codeGen.builder();
        if (srcPayload.isAddress())
        {
            CodeGenHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, elemSize);
            return;
        }

        if (elemSize > 8)
        {
            CodeGenHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, elemSize);
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

        const uint32_t elemSize      = static_cast<uint32_t>(rawElemSize);
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

            const CodeGenNodePayload* const argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);
            offset                 = Math::alignUpU64(offset, elemAlign);
            MicroReg dstAddressReg = frameBaseReg;
            if (offset)
            {
                dstAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(dstAddressReg, frameBaseReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(dstAddressReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
            }
            storeTypedVariadicElement(codeGen, dstAddressReg, *argPayload, elemSize);
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
        AstNodeRef                argRef         = AstNodeRef::invalid();
        const CodeGenNodePayload* argPayload     = nullptr;
        TypeRef                   argTypeRef     = TypeRef::invalid();
        ConstantRef               typeInfoCstRef = ConstantRef::invalid();
        uint32_t                  valueSize      = 0;
        uint32_t                  valueAlign     = 1;
        bool                      needsSpill     = false;
        uint64_t                  spillOffset    = 0;
    };

    void packUntypedVariadicArgument(ABICall::PreparedArg& outPreparedArg, uint32_t& outTransientStackSize, CodeGen& codeGen, const CallConv& callConv, std::span<const ResolvedCallArgument> args, const ABITypeNormalize::NormalizedType& normalizedVariadic)
    {
        MicroBuilder& builder = codeGen.builder();
        SWC_ASSERT(normalizedVariadic.numBits == 64);
        SWC_ASSERT(!normalizedVariadic.isIndirect);

        TaskContext&                        ctx = codeGen.ctx();
        SmallVector<UntypedVariadicArgInfo> variadicInfos;
        variadicInfos.reserve(args.size());

        uint64_t spillStorageSize = 0;
        for (const ResolvedCallArgument& resolvedArg : args)
        {
            if (resolvedArg.argRef.isInvalid())
                continue;

            const CodeGenNodePayload* const argPayload = codeGen.payload(resolvedArg.argRef);
            SWC_ASSERT(argPayload != nullptr);

            const SemaNodeView argView = codeGen.viewType(resolvedArg.argRef);
            SWC_ASSERT(argView.type());

            const TypeInfo& argType    = ctx.typeMgr().get(argView.typeRef());
            const uint64_t  rawArgSize = argType.sizeOf(ctx);
            SWC_ASSERT(rawArgSize > 0 && rawArgSize <= std::numeric_limits<uint32_t>::max());

            UntypedVariadicArgInfo info;
            info.argRef         = resolvedArg.argRef;
            info.argPayload     = argPayload;
            info.argTypeRef     = argView.typeRef();
            info.typeInfoCstRef = resolvedArg.typeInfoCstRef;
            info.valueSize      = static_cast<uint32_t>(rawArgSize);
            info.valueAlign     = std::max<uint32_t>(argType.alignOf(ctx), 1);
            info.needsSpill     = argPayload->isValue() && info.valueSize <= 8;
            SWC_ASSERT(info.typeInfoCstRef.isValid());

            if (info.needsSpill)
            {
                spillStorageSize = Math::alignUpU64(spillStorageSize, info.valueAlign);
                info.spillOffset = spillStorageSize;
                spillStorageSize += info.valueSize;
            }

            variadicInfos.push_back(info);
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

            MicroReg valuePtrReg = MicroReg::invalid();
            if (info.needsSpill)
            {
                valuePtrReg = frameBaseReg;
                if (info.spillOffset)
                {
                    valuePtrReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(valuePtrReg, frameBaseReg, MicroOpBits::B64);
                    builder.emitOpBinaryRegImm(valuePtrReg, ApInt(info.spillOffset, 64), MicroOp::Add, MicroOpBits::B64);
                }
                storeTypedVariadicElement(codeGen, valuePtrReg, *info.argPayload, info.valueSize);
            }
            else if (info.argPayload->isAddress())
            {
                valuePtrReg = info.argPayload->reg;
            }
            else
            {
                valuePtrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(valuePtrReg, info.argPayload->reg, MicroOpBits::B64);
            }

            builder.emitLoadMemReg(anyEntryReg, offsetof(Runtime::Any, value), valuePtrReg, MicroOpBits::B64);

            const ConstantValue& typeInfoCst = codeGen.cstMgr().get(info.typeInfoCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());

            const MicroReg typeInfoReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrImm(typeInfoReg, typeInfoCst.getValuePointer(), info.typeInfoCstRef);
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
            const SymbolVariable* const lastParam = params.back();
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
        {
            const auto&      arg    = args[i];
            const AstNodeRef argRef = arg.argRef;
            if (argRef.isInvalid())
                continue;
            const CodeGenNodePayload* argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);
            const SemaNodeView argView = codeGen.viewType(argRef);

            ABICall::PreparedArg preparedArg;
            preparedArg.srcReg = argPayload->reg;

            TypeRef normalizedTypeRef = TypeRef::invalid();
            if (i < params.size())
            {
                const SymbolVariable* const param = params[i];
                SWC_ASSERT(param != nullptr);
                normalizedTypeRef = param->typeRef();
            }

            if (normalizedTypeRef.isInvalid())
                normalizedTypeRef = argView.typeRef();
            else
            {
                const TypeInfo& paramType = codeGen.ctx().typeMgr().get(normalizedTypeRef);
                if (paramType.isAnyVariadic())
                    normalizedTypeRef = argView.typeRef();
            }

            if (normalizedTypeRef.isValid())
            {
                const TypeInfo&                        normalizedType           = codeGen.ctx().typeMgr().get(normalizedTypeRef);
                const ABITypeNormalize::NormalizedType normalizedArg            = ABITypeNormalize::normalize(codeGen.ctx(), callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
                const bool                             handleBackedAddressValue = shouldPassAddressAsValue(codeGen, normalizedTypeRef, normalizedArg);
                const bool                             passAddressAsValue       = normalizedType.isReference() || handleBackedAddressValue;
                preparedArg.isFloat                                             = normalizedArg.isFloat;
                preparedArg.numBits                                             = normalizedArg.numBits;
                preparedArg.isAddressed                                         = argPayload->isAddress() && !normalizedArg.isIndirect && !passAddressAsValue;
                if (handleBackedAddressValue && argPayload->isAddress())
                {
                    const uint64_t copySize = normalizedType.sizeOf(codeGen.ctx());
                    SWC_ASSERT(copySize > 0 && copySize <= std::numeric_limits<uint32_t>::max());
                    preparedArg.srcReg = materializeAddressValueCopy(codeGen, argPayload->reg, static_cast<uint32_t>(copySize));
                }
            }

            preparedArg.kind = abiPreparedArgKind(arg.passKind);

            outArgs.push_back(preparedArg);
        }

        if (!hasVariadic)
        {
            for (size_t i = numFixedArgs; i < args.size(); ++i)
            {
                const auto&      arg    = args[i];
                const AstNodeRef argRef = arg.argRef;
                if (argRef.isInvalid())
                    continue;
                const CodeGenNodePayload* argPayload = codeGen.payload(argRef);
                SWC_ASSERT(argPayload != nullptr);
                const SemaNodeView argView = codeGen.viewType(argRef);

                ABICall::PreparedArg preparedArg;
                preparedArg.srcReg = argPayload->reg;

                TypeRef normalizedTypeRef = TypeRef::invalid();
                if (i < numParams)
                {
                    const SymbolVariable* const param = params[i];
                    SWC_ASSERT(param != nullptr);
                    normalizedTypeRef = param->typeRef();
                }

                if (normalizedTypeRef.isInvalid())
                    normalizedTypeRef = argView.typeRef();
                else
                {
                    const TypeInfo& paramType = codeGen.ctx().typeMgr().get(normalizedTypeRef);
                    if (paramType.isAnyVariadic())
                        normalizedTypeRef = argView.typeRef();
                }

                if (normalizedTypeRef.isValid())
                {
                    const TypeInfo&                        normalizedType           = codeGen.ctx().typeMgr().get(normalizedTypeRef);
                    const ABITypeNormalize::NormalizedType normalizedArg            = ABITypeNormalize::normalize(codeGen.ctx(), callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
                    const bool                             handleBackedAddressValue = shouldPassAddressAsValue(codeGen, normalizedTypeRef, normalizedArg);
                    const bool                             passAddressAsValue       = normalizedType.isReference() || handleBackedAddressValue;
                    preparedArg.isFloat                                             = normalizedArg.isFloat;
                    preparedArg.numBits                                             = normalizedArg.numBits;
                    preparedArg.isAddressed                                         = argPayload->isAddress() && !normalizedArg.isIndirect && !passAddressAsValue;
                    if (handleBackedAddressValue && argPayload->isAddress())
                    {
                        const uint64_t copySize = normalizedType.sizeOf(codeGen.ctx());
                        SWC_ASSERT(copySize > 0 && copySize <= std::numeric_limits<uint32_t>::max());
                        preparedArg.srcReg = materializeAddressValueCopy(codeGen, argPayload->reg, static_cast<uint32_t>(copySize));
                    }
                }

                preparedArg.kind = abiPreparedArgKind(arg.passKind);
                outArgs.push_back(preparedArg);
            }

            return;
        }

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

    Result emitFunctionReturn(CodeGen& codeGen, const SymbolFunction& symbolFunc, AstNodeRef exprRef)
    {
        MicroBuilder&                          builder       = codeGen.builder();
        const CallConvKind                     callConvKind  = symbolFunc.callConvKind();
        const CallConv&                        callConv      = CallConv::get(callConvKind);
        const TypeRef                          returnTypeRef = symbolFunc.returnTypeRef();
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);

        if (normalizedRet.isVoid)
        {
            // Void returns only need control transfer; ABI return registers are irrelevant.
            emitLocalStackFrameEpilogue(codeGen, callConvKind);
            builder.emitRet();
            return Result::Continue;
        }

        SWC_ASSERT(exprRef.isValid());

        const CodeGenNodePayload* exprPayload = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
        if (normalizedRet.isIndirect)
        {
            // Hidden first argument points to caller-provided return storage.
            SWC_ASSERT(!callConv.intArgRegs.empty());

            const CodeGenNodePayload* fnPayload = codeGen.payload(symbolFunc.declNodeRef());
            SWC_ASSERT(fnPayload);
            SWC_ASSERT(fnPayload->isAddress());

            const MicroReg outputStorageReg = fnPayload->reg;
            SWC_ASSERT(exprPayload->isAddress());
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
            builder.emitLoadRegReg(callConv.intReturn, outputStorageReg, MicroOpBits::B64);
        }
        else
        {
            // Direct returns are normalized to ABI return registers (int/float lane).
            const bool isAddressed = exprPayload->isAddress();
            if (isAddressed && shouldPassAddressAsValue(codeGen, returnTypeRef, normalizedRet))
            {
                const TypeInfo& returnTypeInfo = codeGen.ctx().typeMgr().get(returnTypeRef);
                const uint64_t  copySize       = returnTypeInfo.sizeOf(codeGen.ctx());
                SWC_ASSERT(copySize > 0 && copySize <= std::numeric_limits<uint32_t>::max());
                const MicroReg copiedValueReg = materializeAddressValueCopy(codeGen, exprPayload->reg, static_cast<uint32_t>(copySize));
                ABICall::materializeValueToReturnRegs(builder, callConvKind, copiedValueReg, false, normalizedRet);
            }
            else
            {
                ABICall::materializeValueToReturnRegs(builder, callConvKind, exprPayload->reg, isAddressed, normalizedRet);
            }
        }

        emitLocalStackFrameEpilogue(codeGen, callConvKind);
        builder.emitRet();
        return Result::Continue;
    }
}

Result AstFunctionDecl::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::SkipChildren;

    const SymbolFunction&                  symbolFunc    = codeGen.function();
    const CallConvKind                     callConvKind  = symbolFunc.callConvKind();
    const CallConv&                        callConv      = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);

    if (normalizedRet.isIndirect)
    {
        // Capture hidden return pointer before any parameter materialization can clobber input registers.
        SWC_ASSERT(!callConv.intArgRegs.empty());
        const CodeGenNodePayload& payload = codeGen.setPayloadAddress(codeGen.curNodeRef());
        codeGen.builder().emitLoadRegReg(payload.reg, callConv.intArgRegs[0], MicroOpBits::B64);
    }

    SmallVector<CodeGenHelpers::FunctionParameterInfo> paramInfos;
    collectFunctionParameterInfos(paramInfos, codeGen, symbolFunc);
    buildLocalStackLayout(codeGen);
    materializeRegisterParameters(codeGen, symbolFunc, paramInfos);
    materializeStackParameters(codeGen, symbolFunc, paramInfos);
    emitLocalStackFramePrologue(codeGen, callConvKind);

    return Result::Continue;
}

Result AstFunctionDecl::codeGenPostNode(CodeGen& codeGen) const
{
    if (!hasFlag(AstFunctionFlagsE::Short))
        return Result::Continue;
    SWC_ASSERT(nodeBodyRef.isValid());
    return emitFunctionReturn(codeGen, codeGen.function(), nodeBodyRef);
}

Result AstReturnStmt::codeGenPostNode(CodeGen& codeGen) const
{
    return emitFunctionReturn(codeGen, codeGen.function(), nodeExprRef);
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroBuilder&                          builder        = codeGen.builder();
    const SemaNodeView                     calleeView     = codeGen.viewZero(nodeExprRef);
    const SemaNodeView                     currentView    = codeGen.curViewTypeSymbol();
    SymbolFunction&                        calledFunction = currentView.sym()->cast<SymbolFunction>();
    const CallConvKind                     callConvKind   = calledFunction.callConvKind();
    const CallConv&                        callConv       = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet  = ABITypeNormalize::normalize(codeGen.ctx(), callConv, currentView.typeRef(), ABITypeNormalize::Usage::Return);

    SmallVector<ResolvedCallArgument> args;
    SmallVector<ABICall::PreparedArg> preparedArgs;
    codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), args);
    uint32_t transientStackSize = 0;
    buildPreparedABIArguments(codeGen, calledFunction, args, preparedArgs, transientStackSize);

    // prepareArgs handles register placement, stack slots, and hidden indirect return arg.
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs, normalizedRet);
    CodeGenNodePayload&         nodePayload  = codeGen.setPayload(codeGen.curNodeRef(), currentView.typeRef());
    emitFunctionCall(codeGen, calledFunction, calleeView.nodeRef(), preparedCall);
    if (transientStackSize)
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(transientStackSize, 64), MicroOp::Add, MicroOpBits::B64);

    ABICall::materializeReturnToReg(builder, nodePayload.reg, callConvKind, normalizedRet);
    setPayloadStorageKind(nodePayload, normalizedRet.isIndirect);

    return Result::Continue;
}

SWC_END_NAMESPACE();
