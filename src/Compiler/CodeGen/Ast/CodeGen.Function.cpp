#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool tryBuildGvtdEntry(const CodeGen& codeGen, TypeRef typeRef, const SymbolFunction*& outOpDrop, uint32_t& outSizeOf, uint32_t& outCount)
    {
        return codeGen.tryBuildLifecycleAction(typeRef, CodeGen::LifecycleKind::Drop, outOpDrop, outSizeOf, outCount);
    }

    void collectGvtdEntriesRec(CodeGen& codeGen, const SymbolMap& symbolMap, SmallVector<CodeGenGvtdEntry>& outEntries)
    {
        std::vector<const Symbol*> symbols;
        symbolMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            SWC_ASSERT(symbol != nullptr);

            if (symbol->isVariable())
            {
                const auto* symVar = symbol->safeCast<SymbolVariable>();
                SWC_ASSERT(symVar != nullptr);
                if (!symVar->hasGlobalStorage())
                    continue;

                const DataSegmentKind storageKind = symVar->globalStorageKind();
                if (storageKind != DataSegmentKind::GlobalZero && storageKind != DataSegmentKind::GlobalInit)
                    continue;

                const SymbolFunction* opDrop = nullptr;
                uint32_t              sizeOf = 0;
                uint32_t              count  = 0;
                if (!tryBuildGvtdEntry(codeGen, symVar->typeRef(), opDrop, sizeOf, count))
                    continue;

                outEntries.push_back({.variable = symVar, .opDrop = opDrop, .sizeOf = sizeOf, .count = count});
                continue;
            }

            if (symbol->isModule() || symbol->isNamespace())
                collectGvtdEntriesRec(codeGen, *symbol->asSymMap(), outEntries);
        }
    }

    void configureGvtdScratchLayout(CodeGen& codeGen, uint64_t& frameSize)
    {
        codeGen.clearGvtdScratchLayout();

        const AstNodeRef functionDeclRef = codeGen.function().declNodeRef();
        if (!functionDeclRef.isValid())
            return;

        if (!codeGen.function().usesGvtd())
            return;

        // `@gvtd` returns a slice built in the current frame, so reserve scratch space once in the local
        // stack layout and keep the referenced drop helpers alive as dependencies.
        SmallVector<CodeGenGvtdEntry> entries;
        if (const SymbolModule* rootModule = codeGen.compiler().symModule())
            collectGvtdEntriesRec(codeGen, *rootModule, entries);

        for (const auto& entry : entries)
            codeGen.function().addCallDependency(entry.opDrop);

        constexpr uint32_t sliceSize      = sizeof(Runtime::Slice<Runtime::Gvtd>);
        constexpr uint32_t sliceAlignment = alignof(Runtime::Slice<Runtime::Gvtd>);
        constexpr uint32_t entrySize      = sizeof(Runtime::Gvtd);
        constexpr uint32_t entryAlignment = alignof(Runtime::Gvtd);
        constexpr uint32_t scratchAlign   = std::max(sliceAlignment, entryAlignment);
        constexpr uint32_t entriesOffset  = Math::alignUpU32(sliceSize, entryAlignment);
        const uint64_t     scratchBase    = Math::alignUpU64(frameSize, scratchAlign);
        const uint64_t     scratchSize    = entriesOffset + entries.size() * entrySize;
        const uint64_t     scratchEnd     = scratchBase + scratchSize;
        SWC_ASSERT(scratchSize > 0);
        SWC_ASSERT(scratchSize <= std::numeric_limits<uint32_t>::max());
        SWC_ASSERT(scratchEnd <= std::numeric_limits<uint32_t>::max());

        frameSize = scratchEnd;
        codeGen.setGvtdScratchLayout(static_cast<uint32_t>(scratchBase), static_cast<uint32_t>(scratchSize), entries.span());
    }

    bool tryGetSizedTypeLayout(uint32_t& outSize, uint32_t& outAlignment, CodeGen& codeGen, const TypeInfo& typeInfo)
    {
        const uint64_t rawSize = typeInfo.sizeOf(codeGen.ctx());
        if (!rawSize)
            return false;

        SWC_ASSERT(rawSize <= std::numeric_limits<uint32_t>::max());
        outSize      = static_cast<uint32_t>(rawSize);
        outAlignment = typeInfo.alignOf(codeGen.ctx());
        if (!outAlignment)
            outAlignment = 1;
        return true;
    }

    void assignLocalStackSlot(SymbolVariable& symVar, uint64_t& frameSize, uint32_t size, uint32_t alignment)
    {
        SWC_ASSERT(size != 0);
        SWC_ASSERT(alignment != 0);
        frameSize = Math::alignUpU64(frameSize, alignment);
        SWC_ASSERT(frameSize <= std::numeric_limits<uint32_t>::max());
        symVar.setOffset(static_cast<uint32_t>(frameSize));
        symVar.setCodeGenLocalSize(size);
        symVar.addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
        frameSize += size;
    }

    void appendDebugParameterSlots(CodeGen& codeGen, uint64_t& frameSize)
    {
        if (!codeGen.isDebugInfoEnabled())
            return;

        // Debug info wants a stable stack home even for parameters that arrive only in registers.
        const std::vector<SymbolVariable*>& params = codeGen.function().parameters();
        for (SymbolVariable* symVar : params)
        {
            SWC_ASSERT(symVar != nullptr);

            const TypeRef typeRef = symVar->typeRef();
            SWC_ASSERT(typeRef.isValid());

            const TypeInfo& typeInfo      = codeGen.typeMgr().get(typeRef);
            uint32_t        slotSize      = 0;
            uint32_t        slotAlignment = 0;
            if (!tryGetSizedTypeLayout(slotSize, slotAlignment, codeGen, typeInfo))
                continue;

            const CallConv&                        callConv        = CallConv::get(codeGen.function().callConvKind());
            const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, typeRef, ABITypeNormalize::Usage::Argument);

            if (!normalizedParam.isIndirect && normalizedParam.numBits)
                slotSize = std::max<uint32_t>(slotSize, normalizedParam.numBits / 8);

            frameSize = Math::alignUpU64(frameSize, slotAlignment);
            SWC_ASSERT(frameSize <= std::numeric_limits<uint32_t>::max());
            symVar->setDebugStackSlotOffset(static_cast<uint32_t>(frameSize));
            symVar->setDebugStackSlotSize(slotSize);
            frameSize += slotSize;
        }
    }

    void emitCurrentFunctionIndirectReturnStoragePrologue(CodeGen& codeGen, const CallConv& callConv)
    {
        if (!codeGen.hasCurrentFunctionIndirectReturnStackOffset())
            return;

        SWC_ASSERT(codeGen.localStackBaseReg().isValid());
        SWC_ASSERT(!callConv.intArgRegs.empty());
        codeGen.builder().emitLoadMemReg(codeGen.localStackBaseReg(), codeGen.currentFunctionIndirectReturnStackOffset(), callConv.intArgRegs[0], MicroOpBits::B64);
    }

    void buildLocalStackLayout(CodeGen& codeGen)
    {
        const std::vector<SymbolVariable*>& localSymbols = codeGen.function().localVariables();
        const std::vector<SymbolVariable*>& params       = codeGen.function().parameters();
        const CallConv&                     callConv     = CallConv::get(codeGen.function().callConvKind());
        uint64_t                            frameSize    = 0;
        codeGen.clearCurrentFunctionIndirectReturnStackOffset();
        for (SymbolVariable* symVar : localSymbols)
        {
            SWC_ASSERT(symVar != nullptr);
            const TypeRef typeRef = symVar->typeRef();
            SWC_ASSERT(typeRef.isValid());

            if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, *symVar))
            {
                symVar->setOffset(0);
                symVar->setCodeGenLocalSize(0);
                continue;
            }

            const TypeInfo& typeInfo  = codeGen.typeMgr().get(typeRef);
            uint32_t        size      = 0;
            uint32_t        alignment = 0;
            if (!tryGetSizedTypeLayout(size, alignment, codeGen, typeInfo))
            {
                symVar->setOffset(0);
                symVar->setCodeGenLocalSize(0);
                continue;
            }

            // Recompute local offsets from the finalized runtime sizes. Sema-time offsets can become stale
            // when expression-backed locals (notably closures) expand to larger runtime payloads later on.
            assignLocalStackSlot(*symVar, frameSize, size, alignment);
        }

        for (SymbolVariable* symVar : params)
        {
            SWC_ASSERT(symVar != nullptr);
            if (!symVar->hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage))
                continue;
            if (CodeGenFunctionHelpers::canUseIncomingIndirectParameterAsAddressableParameter(codeGen, codeGen.function(), *symVar))
                continue;

            const TypeRef typeRef = symVar->typeRef();
            SWC_ASSERT(typeRef.isValid());

            const TypeInfo& typeInfo  = codeGen.typeMgr().get(typeRef);
            uint32_t        size      = 0;
            uint32_t        alignment = 0;
            if (!tryGetSizedTypeLayout(size, alignment, codeGen, typeInfo))
                continue;

            assignLocalStackSlot(*symVar, frameSize, size, alignment);
        }

        appendDebugParameterSlots(codeGen, frameSize);
        configureGvtdScratchLayout(codeGen, frameSize);
        if (CodeGenFunctionHelpers::functionUsesIndirectReturnStorage(codeGen, codeGen.function()))
        {
            constexpr uint32_t hiddenReturnStorageSize      = sizeof(uint64_t);
            constexpr uint32_t hiddenReturnStorageAlignment = alignof(uint64_t);
            frameSize                                       = Math::alignUpU64(frameSize, hiddenReturnStorageAlignment);
            SWC_ASSERT(frameSize <= std::numeric_limits<uint32_t>::max());
            codeGen.setCurrentFunctionIndirectReturnStackOffset(static_cast<uint32_t>(frameSize));
            frameSize += hiddenReturnStorageSize;
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

        // Materialize the local stack base into a virtual register. RegAlloc will assign
        // it a physical register — we constrain it to a persistent (callee-saved) register
        // by forbidding all transient (caller-saved) registers, so it survives calls.
        const MicroReg        frameBaseReg = codeGen.nextVirtualIntRegister();
        SmallVector<MicroReg> forbiddenRegs;
        for (const MicroReg reg : callConv.intTransientRegs)
            forbiddenRegs.push_back(reg);
        forbiddenRegs.push_back(callConv.stackPointer);
        if (callConv.framePointer.isValid())
            forbiddenRegs.push_back(callConv.framePointer);
        builder.addVirtualRegForbiddenPhysRegs(frameBaseReg, forbiddenRegs.span());

        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(frameSize, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);
        codeGen.setLocalStackBaseReg(frameBaseReg);
        codeGen.function().setDebugStackFrameSize(frameSize);
        codeGen.function().setDebugStackBaseReg(frameBaseReg);
    }

    void spillParametersToDebugSlots(CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        if (!codeGen.isDebugInfoEnabled())
            return;
        if (!codeGen.hasLocalStackFrame())
            return;
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());

        // Once parameter payloads are materialized, mirror them into the synthetic debug slots so the
        // debugger can recover them from a single stack location. Use the local-frame base instead of
        // raw SP so later spill-frame insertion does not slide these stores into the allocator spill area.
        MicroBuilder&                       builder = codeGen.builder();
        const MicroReg                      baseReg = codeGen.localStackBaseReg();
        const std::vector<SymbolVariable*>& params  = symbolFunc.parameters();
        for (const SymbolVariable* symVar : params)
        {
            SWC_ASSERT(symVar != nullptr);
            if (!symVar->debugStackSlotSize())
                continue;

            const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(*symVar);
            if (!symbolPayload)
                continue;

            const TypeInfo& typeInfo        = codeGen.typeMgr().get(symVar->typeRef());
            uint32_t        copySize        = 0;
            uint32_t        unusedAlignment = 0;
            if (!tryGetSizedTypeLayout(copySize, unusedAlignment, codeGen, typeInfo))
                continue;

            if (symbolPayload->isAddress())
            {
                MicroReg slotAddrReg = baseReg;
                if (symVar->debugStackSlotOffset())
                {
                    slotAddrReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(slotAddrReg, baseReg, MicroOpBits::B64);
                    builder.emitOpBinaryRegImm(slotAddrReg, ApInt(symVar->debugStackSlotOffset(), 64), MicroOp::Add, MicroOpBits::B64);
                }

                CodeGenMemoryHelpers::emitMemCopy(codeGen, slotAddrReg, symbolPayload->reg, copySize);
                continue;
            }

            const MicroOpBits storeBits = microOpBitsFromChunkSize(copySize);
            if (storeBits == MicroOpBits::Zero)
                continue;
            builder.emitLoadMemReg(baseReg, symVar->debugStackSlotOffset(), symbolPayload->reg, storeBits);
        }
    }

    MicroReg parameterSourcePhysReg(const CallConv& callConv, const CodeGenFunctionHelpers::FunctionParameterInfo& paramInfo)
    {
        if (paramInfo.isFloat)
        {
            SWC_ASSERT(paramInfo.slotIndex < callConv.floatArgRegs.size());
            return callConv.floatArgRegs[paramInfo.slotIndex];
        }

        SWC_ASSERT(paramInfo.slotIndex < callConv.intArgRegs.size());
        return callConv.intArgRegs[paramInfo.slotIndex];
    }

    void collectFunctionParameterInfos(SmallVector<CodeGenFunctionHelpers::FunctionParameterInfo>& outParamInfos, CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        const std::vector<SymbolVariable*>& params = symbolFunc.parameters();
        outParamInfos.clear();
        if (params.empty())
            return;

        outParamInfos.resize(params.size());

        const CallConv&                        callConv             = CallConv::get(symbolFunc.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet        = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);
        const bool                             hasIndirectReturnArg = normalizedRet.isIndirect;
        const bool                             hasClosureContextArg = symbolFunc.isClosure();
        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* symVar = params[i];
            SWC_ASSERT(symVar != nullptr);
            outParamInfos[i] = CodeGenFunctionHelpers::functionParameterInfo(codeGen, symbolFunc, *symVar, hasIndirectReturnArg, hasClosureContextArg);
        }
    }

    void collectRegisterParameterIndices(SmallVector<uint32_t>& outIndices, const std::vector<SymbolVariable*>& params, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
    {
        SWC_ASSERT(paramInfos.size() == params.size());
        outIndices.clear();
        outIndices.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
        {
            SWC_ASSERT(params[i] != nullptr);
            if (paramInfos[i].isRegisterArg)
                outIndices.push_back(static_cast<uint32_t>(i));
        }
    }

    void materializeRegisterParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
    {
        const CallConv&                     callConv = CallConv::get(symbolFunc.callConvKind());
        const std::vector<SymbolVariable*>& params   = symbolFunc.parameters();
        MicroBuilder&                       builder  = codeGen.builder();
        SWC_ASSERT(paramInfos.size() == params.size());

        struct RegisterParameterPayload
        {
            const SymbolVariable*                         symVar      = nullptr;
            CodeGenNodePayload                            payload     = {};
            CodeGenFunctionHelpers::FunctionParameterInfo paramInfo   = {};
            bool                                          needsRebind = false;
        };

        SmallVector<uint32_t> registerParamIndices;
        collectRegisterParameterIndices(registerParamIndices, params, paramInfos);
        SmallVector<RegisterParameterPayload> registerPayloads;
        registerPayloads.reserve(registerParamIndices.size());

        for (size_t i = 0; i < registerParamIndices.size(); ++i)
        {
            const uint32_t paramIndex = registerParamIndices[i];
            const auto*    symVar     = params[paramIndex];
            SWC_ASSERT(symVar != nullptr);
            const auto paramInfo = paramInfos[paramIndex];

            SmallVector<MicroReg> futureSourceRegs;
            futureSourceRegs.reserve(registerParamIndices.size() - i - 1);
            for (size_t j = i + 1; j < registerParamIndices.size(); ++j)
            {
                const uint32_t                                      laterParamIndex = registerParamIndices[j];
                const CodeGenFunctionHelpers::FunctionParameterInfo laterParamInfo  = paramInfos[laterParamIndex];
                if (laterParamInfo.isFloat != paramInfo.isFloat)
                    continue;

                futureSourceRegs.push_back(parameterSourcePhysReg(callConv, laterParamInfo));
            }

            CodeGenNodePayload symbolPayload;
            symbolPayload.reg     = paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            symbolPayload.typeRef = symVar->typeRef();
            builder.addVirtualRegForbiddenPhysRegs(symbolPayload.reg, futureSourceRegs.span());
            if (!futureSourceRegs.empty())
                builder.preserveVirtualCopy(symbolPayload.reg);
            CodeGenFunctionHelpers::emitLoadFunctionParameterToReg(codeGen, symbolFunc, paramInfo, symbolPayload.reg);
            symbolPayload.setValueOrAddress(paramInfo.isIndirect);
            codeGen.setVariablePayload(*symVar, symbolPayload);

            RegisterParameterPayload registerPayload;
            registerPayload.symVar      = symVar;
            registerPayload.payload     = symbolPayload;
            registerPayload.paramInfo   = paramInfo;
            registerPayload.needsRebind = !futureSourceRegs.empty();
            registerPayloads.push_back(registerPayload);
        }

        for (const auto& registerPayload : registerPayloads)
        {
            if (!registerPayload.needsRebind)
                continue;

            CodeGenNodePayload reboundPayload = registerPayload.payload;
            reboundPayload.reg                = registerPayload.paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(reboundPayload.reg, registerPayload.payload.reg, registerPayload.paramInfo.opBits);
            codeGen.setVariablePayload(*registerPayload.symVar, reboundPayload);
        }
    }

    void materializeStackParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
    {
        const std::vector<SymbolVariable*>& params = symbolFunc.parameters();
        SWC_ASSERT(paramInfos.size() == params.size());

        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* symVar = params[i];
            SWC_ASSERT(symVar != nullptr);
            const CodeGenFunctionHelpers::FunctionParameterInfo paramInfo = paramInfos[i];
            if (paramInfo.isRegisterArg)
                continue;

            CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, *symVar, paramInfo);
        }
    }

    void spillAddressableParametersToLocalSlots(CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        if (!codeGen.localStackBaseReg().isValid())
            return;

        MicroBuilder&                       builder = codeGen.builder();
        const std::vector<SymbolVariable*>& params  = symbolFunc.parameters();
        for (const SymbolVariable* symVar : params)
        {
            SWC_ASSERT(symVar != nullptr);
            if (!symVar->hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage))
                continue;
            if (!symVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
                continue;

            const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(*symVar);
            if (!symbolPayload)
                continue;

            const TypeInfo& typeInfo = codeGen.typeMgr().get(symVar->typeRef());
            const uint32_t  copySize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
            const MicroReg  localReg = codeGen.offsetAddressReg(codeGen.localStackBaseReg(), symVar->offset());

            if (symbolPayload->isAddress())
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, localReg, symbolPayload->reg, copySize);
            }
            else
            {
                const MicroOpBits storeBits = microOpBitsFromChunkSize(copySize);
                SWC_ASSERT(storeBits != MicroOpBits::Zero);
                builder.emitLoadMemReg(localReg, 0, symbolPayload->reg, storeBits);
            }

            CodeGenNodePayload localPayload;
            localPayload.typeRef = symVar->typeRef();
            localPayload.setIsAddress();
            localPayload.reg = localReg;
            codeGen.setVariablePayload(*symVar, localPayload);
        }
    }

    bool isActiveFunctionRoot(CodeGen& codeGen, AstNodeRef declRef)
    {
        const AstNodeRef currentDeclRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
        const AstNodeRef activeDeclRef  = codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef();
        return currentDeclRef == declRef && activeDeclRef == declRef;
    }

    void clearThrowableFunctionPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (CodeGenNodePayload* payload = codeGen.safePayload(nodeRef))
            payload->clearThrowableFunctionTarget();
    }

    Result codeGenFunctionLikePreBody(CodeGen& codeGen, AstNodeRef declRef, AstNodeRef childRef, AstNodeRef bodyRef)
    {
        declRef = codeGen.viewZero(declRef).nodeRef();
        if (!isActiveFunctionRoot(codeGen, declRef))
            return Result::SkipChildren;

        const AstNodeRef resolvedChildRef = codeGen.viewZero(childRef).nodeRef();
        const AstNodeRef resolvedBodyRef  = codeGen.viewZero(bodyRef).nodeRef();
        if (resolvedChildRef != resolvedBodyRef)
            return Result::SkipChildren;

        const SymbolFunction&                  symbolFunc    = codeGen.function();
        const CallConvKind                     callConvKind  = symbolFunc.callConvKind();
        const CallConv&                        callConv      = CallConv::get(callConvKind);
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);

        codeGen.setCurrentFunctionIndirectReturnReg(MicroReg::invalid());
        codeGen.setCurrentFunctionClosureContextReg(MicroReg::invalid());
        clearThrowableFunctionPayload(codeGen, declRef);

        SmallVector<CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos;
        collectFunctionParameterInfos(paramInfos, codeGen, symbolFunc);
        buildLocalStackLayout(codeGen);
        {
            MicroBuilder&           builder = codeGen.builder();
            const ScopedDebugNoStep noStep(builder, true);
            emitLocalStackFramePrologue(codeGen, callConvKind);
            emitCurrentFunctionIndirectReturnStoragePrologue(codeGen, callConv);
        }

        if (symbolFunc.isClosure())
        {
            const uint32_t closureContextSlot = normalizedRet.isIndirect ? 1u : 0u;
            SWC_ASSERT(closureContextSlot < callConv.intArgRegs.size());

            MicroBuilder&           builder = codeGen.builder();
            const ScopedDebugNoStep noStep(builder, true);
            const MicroReg          closureContextReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(closureContextReg, callConv.intArgRegs[closureContextSlot], MicroOpBits::B64);
            codeGen.setCurrentFunctionClosureContextReg(closureContextReg);
        }

        {
            MicroBuilder&           builder = codeGen.builder();
            const ScopedDebugNoStep noStep(builder, true);
            materializeRegisterParameters(codeGen, symbolFunc, paramInfos);
            materializeStackParameters(codeGen, symbolFunc, paramInfos);
            spillAddressableParametersToLocalSlots(codeGen, symbolFunc);
            spillParametersToDebugSlots(codeGen, symbolFunc);
        }

        codeGen.pushDeferScope(declRef);
        codeGen.registerImplicitParameterDrops();

        return Result::Continue;
    }
}

Result AstFunctionDecl::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    return codeGenFunctionLikePreBody(codeGen, codeGen.curNodeRef(), childRef, nodeBodyRef);
}

Result AstFunctionExpr::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    return codeGenFunctionLikePreBody(codeGen, codeGen.curNodeRef(), childRef, nodeBodyRef);
}

Result AstClosureExpr::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef declRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
    if (!isActiveFunctionRoot(codeGen, declRef))
    {
        const AstNodeRef resolvedChildRef = codeGen.viewZero(childRef).nodeRef();
        if (resolvedChildRef.isValid() && codeGen.node(resolvedChildRef).is(AstNodeId::ClosureArgument))
            return Result::Continue;
    }

    return codeGenFunctionLikePreBody(codeGen, codeGen.curNodeRef(), childRef, nodeBodyRef);
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, nodeExprRef);
}

Result AstAliasCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, nodeExprRef);
}

SWC_END_NAMESPACE();
