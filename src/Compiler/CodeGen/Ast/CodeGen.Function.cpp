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

SWC_BEGIN_NAMESPACE();

namespace
{
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

    void materializeRegisterParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        const CallConv&                     callConv = CallConv::get(symbolFunc.callConvKind());
        const std::vector<SymbolVariable*>& params   = symbolFunc.parameters();
        MicroBuilder&                       builder  = codeGen.builder();

        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* const symVar = params[i];
            if (!symVar)
                continue;

            const CodeGenHelpers::FunctionParameterInfo paramInfo = CodeGenHelpers::functionParameterInfo(codeGen, symbolFunc, *symVar);
            if (!paramInfo.isRegisterArg)
                continue;

            CodeGenNodePayload symbolPayload;
            symbolPayload.reg     = paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            symbolPayload.typeRef = symVar->typeRef();

            SmallVector<MicroReg> futureSourceRegs;
            for (size_t j = i + 1; j < params.size(); ++j)
            {
                const SymbolVariable* const laterSymVar = params[j];
                if (!laterSymVar)
                    continue;

                const CodeGenHelpers::FunctionParameterInfo laterParamInfo = CodeGenHelpers::functionParameterInfo(codeGen, symbolFunc, *laterSymVar);
                if (!laterParamInfo.isRegisterArg)
                    continue;

                futureSourceRegs.push_back(parameterSourcePhysReg(callConv, laterParamInfo));
            }

            builder.addVirtualRegForbiddenPhysRegs(symbolPayload.reg, futureSourceRegs);
            CodeGenHelpers::emitLoadFunctionParameterToReg(codeGen, symbolFunc, paramInfo, symbolPayload.reg);
            setPayloadStorageKind(symbolPayload, paramInfo.isIndirect);

            codeGen.setVariablePayload(*symVar, symbolPayload);
        }
    }

    uint64_t alignUpU64(uint64_t value, uint32_t align)
    {
        SWC_ASSERT(align != 0);
        if (align == 0)
            return value;
        const uint64_t alignValue = align;
        return ((value + alignValue - 1) / alignValue) * alignValue;
    }

    void storeTypedVariadicElement(CodeGen& codeGen, MicroReg dstAddressReg, const CodeGenNodePayload& srcPayload, uint32_t elemSize)
    {
        MicroBuilder& builder = codeGen.builder();
        if (srcPayload.isAddress())
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
            totalStorageSize = alignUpU64(totalStorageSize, elemAlign);
            totalStorageSize += elemSize;
        }
        constexpr uint64_t sliceAlign     = alignof(Runtime::Slice<std::byte>);
        const uint64_t     sliceOffset    = alignUpU64(totalStorageSize, static_cast<uint32_t>(sliceAlign));
        const uint64_t     totalFrameSize = sliceOffset + sizeof(Runtime::Slice<std::byte>);
        SWC_ASSERT(totalFrameSize <= std::numeric_limits<uint32_t>::max());

        outTransientStackSize = static_cast<uint32_t>(totalFrameSize);
        if (outTransientStackSize)
            builder.emitOpBinaryRegImm(callConv.stackPointer, outTransientStackSize, MicroOp::Subtract, MicroOpBits::B64);

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
            offset                       = alignUpU64(offset, elemAlign);
            MicroReg dstAddressReg = frameBaseReg;
            if (offset)
            {
                dstAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(dstAddressReg, frameBaseReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(dstAddressReg, offset, MicroOp::Add, MicroOpBits::B64);
            }
            storeTypedVariadicElement(codeGen, dstAddressReg, *argPayload, elemSize);
            offset += elemSize;
        }

        MicroReg sliceAddrReg = frameBaseReg;
        if (sliceOffset)
        {
            sliceAddrReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(sliceAddrReg, frameBaseReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(sliceAddrReg, sliceOffset, MicroOp::Add, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, ptr), frameBaseReg, MicroOpBits::B64);
        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, variadicCount, MicroOpBits::B64);
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
                spillStorageSize = alignUpU64(spillStorageSize, info.valueAlign);
                info.spillOffset = spillStorageSize;
                spillStorageSize += info.valueSize;
            }

            variadicInfos.push_back(info);
        }

        const uint64_t     variadicCount = variadicInfos.size();
        constexpr uint64_t anyAlign      = alignof(Runtime::Any);
        const uint64_t     anyOffset     = alignUpU64(spillStorageSize, static_cast<uint32_t>(anyAlign));
        const uint64_t     anyStorage    = variadicCount * sizeof(Runtime::Any);

        constexpr uint64_t sliceAlign     = alignof(Runtime::Slice<std::byte>);
        const uint64_t     sliceOffset    = alignUpU64(anyOffset + anyStorage, static_cast<uint32_t>(sliceAlign));
        const uint64_t     totalFrameSize = sliceOffset + sizeof(Runtime::Slice<std::byte>);
        SWC_ASSERT(totalFrameSize <= std::numeric_limits<uint32_t>::max());

        outTransientStackSize = static_cast<uint32_t>(totalFrameSize);
        if (outTransientStackSize)
            builder.emitOpBinaryRegImm(callConv.stackPointer, outTransientStackSize, MicroOp::Subtract, MicroOpBits::B64);

        const MicroReg frameBaseReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);

        MicroReg anyBaseReg = frameBaseReg;
        if (anyOffset)
        {
            anyBaseReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(anyBaseReg, frameBaseReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(anyBaseReg, anyOffset, MicroOp::Add, MicroOpBits::B64);
        }

        for (uint64_t i = 0; i < variadicCount; ++i)
        {
            const UntypedVariadicArgInfo& info = variadicInfos[i];

            MicroReg anyEntryReg = anyBaseReg;
            if (i)
            {
                anyEntryReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(anyEntryReg, anyBaseReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(anyEntryReg, i * sizeof(Runtime::Any), MicroOp::Add, MicroOpBits::B64);
            }

            MicroReg valuePtrReg = MicroReg::invalid();
            if (info.needsSpill)
            {
                valuePtrReg = frameBaseReg;
                if (info.spillOffset)
                {
                    valuePtrReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(valuePtrReg, frameBaseReg, MicroOpBits::B64);
                    builder.emitOpBinaryRegImm(valuePtrReg, info.spillOffset, MicroOp::Add, MicroOpBits::B64);
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
            builder.emitOpBinaryRegImm(sliceAddrReg, sliceOffset, MicroOp::Add, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, ptr), anyBaseReg, MicroOpBits::B64);
        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, variadicCount, MicroOpBits::B64);
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
            if (lastParam)
            {
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
            if (i < params.size() && params[i])
                normalizedTypeRef = params[i]->typeRef();

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
                const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
                preparedArg.isFloat                                  = normalizedArg.isFloat;
                preparedArg.numBits                                  = normalizedArg.numBits;
                preparedArg.isAddressed                              = argPayload->isAddress() && !normalizedArg.isIndirect;
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
                if (i < numParams && params[i])
                    normalizedTypeRef = params[i]->typeRef();

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
                    const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
                    preparedArg.isFloat                                  = normalizedArg.isFloat;
                    preparedArg.numBits                                  = normalizedArg.numBits;
                    preparedArg.isAddressed                              = argPayload->isAddress() && !normalizedArg.isIndirect;
                }

                preparedArg.kind = abiPreparedArgKind(arg.passKind);
                outArgs.push_back(preparedArg);
            }

            return;
        }

        ABICall::PreparedArg                        variadicPreparedArg;
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
            ABICall::materializeValueToReturnRegs(builder, callConvKind, exprPayload->reg, isAddressed, normalizedRet);
        }

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
    materializeRegisterParameters(codeGen, symbolFunc);

    if (normalizedRet.isIndirect)
    {
        // Cache hidden return pointer in the function payload for return statements.
        SWC_ASSERT(!callConv.intArgRegs.empty());
        const CodeGenNodePayload& payload = codeGen.setPayloadAddress(codeGen.curNodeRef());
        codeGen.builder().emitLoadRegReg(payload.reg, callConv.intArgRegs[0], MicroOpBits::B64);
    }

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
        builder.emitOpBinaryRegImm(callConv.stackPointer, transientStackSize, MicroOp::Add, MicroOpBits::B64);

    ABICall::materializeReturnToReg(builder, nodePayload.reg, callConvKind, normalizedRet);
    setPayloadStorageKind(nodePayload, normalizedRet.isIndirect);

    return Result::Continue;
}

SWC_END_NAMESPACE();
