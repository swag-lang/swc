#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SymbolFunction* recoverFunctionExprSymbolFromDependencies(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        const AstNode&               node = codeGen.node(nodeRef);
        SmallVector<SymbolFunction*> deps;
        codeGen.function().appendCallDependencies(deps);
        for (SymbolFunction* dep : deps)
        {
            if (!dep || dep->declNodeRef().isInvalid())
                continue;
            if (dep->srcViewRef() != node.srcViewRef())
                continue;
            if (dep->tokRef() != node.tokRef())
                continue;
            return dep;
        }

        return nullptr;
    }

    bool shouldSpillParametersForDebugInfo(const CodeGen& codeGen)
    {
        return codeGen.compiler().buildCfg().backend.debugInfo;
    }

    uint32_t checkedTypeSizeInBytes(CodeGen& codeGen, const TypeInfo& typeInfo)
    {
        const uint64_t rawSize = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(rawSize > 0 && rawSize <= std::numeric_limits<uint32_t>::max());
        return static_cast<uint32_t>(rawSize);
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

    SymbolFunction& functionExprSymbol(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (Symbol* sym = codeGen.sema().viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym())
            return sym->cast<SymbolFunction>();

        if (Symbol* sym = codeGen.viewSymbol(nodeRef).sym())
            return sym->cast<SymbolFunction>();

        if (auto* dep = recoverFunctionExprSymbolFromDependencies(codeGen, nodeRef))
            return *dep;

        const TypeRef typeRef = codeGen.viewType(nodeRef).typeRef();
        SWC_ASSERT(typeRef.isValid());
        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        SWC_ASSERT(typeInfo.isFunction());
        return typeInfo.payloadSymFunction();
    }

    bool functionUsesGvtdIntrinsic(const CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return false;

        const AstNode& node = codeGen.node(nodeRef);
        if (node.is(AstNodeId::IntrinsicCallExpr) && codeGen.token(node.codeRef()).id == TokenId::IntrinsicGvtd)
            return true;

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, codeGen.ast());
        for (const AstNodeRef childRef : children)
        {
            if (functionUsesGvtdIntrinsic(codeGen, childRef))
                return true;
        }

        return false;
    }

    bool tryBuildGvtdEntry(CodeGen& codeGen, TypeRef typeRef, SymbolFunction*& outOpDrop, uint32_t& outSizeOf, uint32_t& outCount)
    {
        outOpDrop = nullptr;
        outSizeOf = 0;
        outCount  = 0;
        if (!typeRef.isValid())
            return false;

        const TypeInfo& originalType = codeGen.typeMgr().get(typeRef);
        const TypeRef   rawTypeRef   = originalType.unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (rawTypeRef.isValid() && rawTypeRef != typeRef)
            typeRef = rawTypeRef;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (typeInfo.isArray())
        {
            uint64_t multiplier = 1;
            for (const uint64_t dim : typeInfo.payloadArrayDims())
                multiplier *= dim;
            if (!multiplier)
                return false;

            SymbolFunction* elemOpDrop = nullptr;
            uint32_t        elemSizeOf = 0;
            uint32_t        elemCount  = 0;
            if (!tryBuildGvtdEntry(codeGen, typeInfo.payloadArrayElemTypeRef(), elemOpDrop, elemSizeOf, elemCount))
                return false;

            const uint64_t totalCount = multiplier * elemCount;
            SWC_ASSERT(totalCount > 0);
            SWC_ASSERT(totalCount <= std::numeric_limits<uint32_t>::max());

            outOpDrop = elemOpDrop;
            outSizeOf = elemSizeOf;
            outCount  = static_cast<uint32_t>(totalCount);
            return true;
        }

        if (!typeInfo.isStruct())
            return false;

        const SymbolFunction* opDrop = typeInfo.payloadSymStruct().opDrop();
        if (!opDrop)
            return false;

        const uint64_t sizeOf = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOf > 0 && sizeOf <= std::numeric_limits<uint32_t>::max());

        outOpDrop = const_cast<SymbolFunction*>(opDrop);
        outSizeOf = static_cast<uint32_t>(sizeOf);
        outCount  = 1;
        return true;
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
                auto* symVar = const_cast<SymbolVariable*>(symbol->safeCast<SymbolVariable>());
                SWC_ASSERT(symVar != nullptr);
                if (!symVar->hasGlobalStorage())
                    continue;

                const DataSegmentKind storageKind = symVar->globalStorageKind();
                if (storageKind != DataSegmentKind::GlobalZero && storageKind != DataSegmentKind::GlobalInit)
                    continue;

                SymbolFunction* opDrop = nullptr;
                uint32_t        sizeOf = 0;
                uint32_t        count  = 0;
                if (!tryBuildGvtdEntry(codeGen, symVar->typeRef(), opDrop, sizeOf, count))
                    continue;

                outEntries.push_back({
                    .variable = symVar,
                    .opDrop   = opDrop,
                    .sizeOf   = sizeOf,
                    .count    = count,
                });
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

        const auto* functionDecl = codeGen.node(functionDeclRef).safeCast<AstFunctionDecl>();
        if (!functionDecl || !functionDecl->nodeBodyRef.isValid())
            return;
        if (!functionUsesGvtdIntrinsic(codeGen, functionDecl->nodeBodyRef))
            return;

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

    void appendDebugParameterSlots(CodeGen& codeGen, uint64_t& frameSize)
    {
        if (!shouldSpillParametersForDebugInfo(codeGen))
            return;

        const std::vector<SymbolVariable*>& params = codeGen.function().parameters();
        for (SymbolVariable* symVar : params)
        {
            SWC_ASSERT(symVar != nullptr);

            const TypeRef typeRef = symVar->typeRef();
            SWC_ASSERT(typeRef.isValid());

            const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
            const uint64_t  rawSize  = typeInfo.sizeOf(codeGen.ctx());
            if (!rawSize)
                continue;

            const CallConv&                        callConv        = CallConv::get(codeGen.function().callConvKind());
            const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, typeRef, ABITypeNormalize::Usage::Argument);
            uint32_t                               slotSize        = checkedTypeSizeInBytes(codeGen, typeInfo);
            uint32_t                               slotAlignment   = typeInfo.alignOf(codeGen.ctx());
            if (!slotAlignment)
                slotAlignment = 1;

            if (!normalizedParam.isIndirect && normalizedParam.numBits)
                slotSize = std::max<uint32_t>(slotSize, normalizedParam.numBits / 8);

            frameSize = Math::alignUpU64(frameSize, slotAlignment);
            SWC_ASSERT(frameSize <= std::numeric_limits<uint32_t>::max());
            symVar->setDebugStackSlotOffset(static_cast<uint32_t>(frameSize));
            symVar->setDebugStackSlotSize(slotSize);
            frameSize += slotSize;
        }
    }

    void buildLocalStackLayout(CodeGen& codeGen)
    {
        const std::vector<SymbolVariable*>& localSymbols = codeGen.function().localVariables();
        const CallConv&                     callConv     = CallConv::get(codeGen.function().callConvKind());
        uint64_t                            frameSize    = 0;
        for (SymbolVariable* symVar : localSymbols)
        {
            SWC_ASSERT(symVar != nullptr);
            const TypeRef typeRef = symVar->typeRef();
            SWC_ASSERT(typeRef.isValid());

            const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
            const auto      size     = static_cast<uint32_t>(typeInfo.sizeOf(codeGen.ctx()));
            if (!size)
                continue;

            const uint32_t symOffset = symVar->offset();
            symVar->setCodeGenLocalSize(size);
            symVar->addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
            frameSize = std::max<uint64_t>(frameSize, symOffset + size);
        }

        appendDebugParameterSlots(codeGen, frameSize);
        configureGvtdScratchLayout(codeGen, frameSize);
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

        const MicroReg frameBaseReg = callConv.preferredLocalStackBaseReg();
        SWC_ASSERT(frameBaseReg.isValid());
        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);
        codeGen.setLocalStackBaseReg(frameBaseReg);
        codeGen.function().setDebugStackFrameSize(frameSize);
        codeGen.function().setDebugStackBaseReg(frameBaseReg);
    }

    void emitLocalStackFrameEpilogue(CodeGen& codeGen, CallConvKind callConvKind)
    {
        if (!codeGen.hasLocalStackFrame())
            return;

        const CallConv& callConv = CallConv::get(callConvKind);
        codeGen.builder().emitOpBinaryRegImm(callConv.stackPointer, ApInt(codeGen.localStackFrameSize(), 64), MicroOp::Add, MicroOpBits::B64);
    }

    void spillParametersToDebugSlots(CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        if (!shouldSpillParametersForDebugInfo(codeGen))
            return;
        if (!codeGen.hasLocalStackFrame())
            return;

        MicroBuilder&                       builder = codeGen.builder();
        const MicroReg                      baseReg = CallConv::get(symbolFunc.callConvKind()).stackPointer;
        const std::vector<SymbolVariable*>& params  = symbolFunc.parameters();
        for (const SymbolVariable* symVar : params)
        {
            SWC_ASSERT(symVar != nullptr);
            if (!symVar->debugStackSlotSize())
                continue;

            const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(*symVar);
            if (!symbolPayload)
                continue;

            const TypeInfo& typeInfo = codeGen.typeMgr().get(symVar->typeRef());
            const uint64_t  rawSize  = typeInfo.sizeOf(codeGen.ctx());
            if (!rawSize)
                continue;

            const uint32_t copySize = checkedTypeSizeInBytes(codeGen, typeInfo);
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

    MicroReg inlineResultAddressReg(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        SWC_ASSERT(symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());
        return codeGen.offsetAddressReg(codeGen.localStackBaseReg(), symVar.offset());
    }

    Result emitInlineResultStore(CodeGen& codeGen, const SemaInlinePayload& inlinePayload, AstNodeRef exprRef)
    {
        SWC_ASSERT(inlinePayload.resultVar != nullptr);
        SWC_ASSERT(exprRef.isValid());

        const TypeInfo& returnType = codeGen.typeMgr().get(inlinePayload.returnTypeRef);
        const uint32_t  copySize   = checkedTypeSizeInBytes(codeGen, returnType);

        const SymbolVariable& resultVar  = *inlinePayload.resultVar;
        const MicroReg        resultAddr = inlineResultAddressReg(codeGen, resultVar);

        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        if (exprPayload.isAddress())
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, resultAddr, exprPayload.reg, copySize);
            return Result::Continue;
        }

        const MicroOpBits storeBits = microOpBitsFromChunkSize(copySize);
        SWC_ASSERT(storeBits != MicroOpBits::Zero);
        codeGen.builder().emitLoadMemReg(resultAddr, 0, exprPayload.reg, storeBits);
        return Result::Continue;
    }

    Result emitInlineReturn(CodeGen& codeGen, const SemaInlinePayload& inlinePayload, AstNodeRef exprRef, MicroLabelRef doneLabel)
    {
        if (inlinePayload.returnTypeRef != codeGen.typeMgr().typeVoid())
        {
            SWC_ASSERT(exprRef.isValid());
            SWC_RESULT(emitInlineResultStore(codeGen, inlinePayload, exprRef));
        }

        SWC_ASSERT(doneLabel.isValid());
        codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
        return Result::Continue;
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
        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* symVar = params[i];
            SWC_ASSERT(symVar != nullptr);
            outParamInfos[i] = CodeGenFunctionHelpers::functionParameterInfo(codeGen, symbolFunc, *symVar, hasIndirectReturnArg);
        }
    }

    void materializeRegisterParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
    {
        const CallConv&                     callConv = CallConv::get(symbolFunc.callConvKind());
        const std::vector<SymbolVariable*>& params   = symbolFunc.parameters();
        MicroBuilder&                       builder  = codeGen.builder();
        SWC_ASSERT(paramInfos.size() == params.size());

        SmallVector<uint32_t> registerParamIndices;
        registerParamIndices.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* symVar = params[i];
            SWC_ASSERT(symVar != nullptr);
            const CodeGenFunctionHelpers::FunctionParameterInfo paramInfo = paramInfos[i];
            if (!paramInfo.isRegisterArg)
                continue;

            registerParamIndices.push_back(static_cast<uint32_t>(i));
        }

        for (size_t i = 0; i < registerParamIndices.size(); ++i)
        {
            const uint32_t        paramIndex = registerParamIndices[i];
            const SymbolVariable* symVar     = params[paramIndex];
            SWC_ASSERT(symVar != nullptr);
            const CodeGenFunctionHelpers::FunctionParameterInfo paramInfo = paramInfos[paramIndex];

            CodeGenNodePayload symbolPayload;
            symbolPayload.reg     = paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            symbolPayload.typeRef = symVar->typeRef();

            SmallVector<MicroReg> futureSourceRegs;
            futureSourceRegs.reserve(registerParamIndices.size() - i - 1);
            for (size_t j = i + 1; j < registerParamIndices.size(); ++j)
            {
                const uint32_t                                      laterParamIndex = registerParamIndices[j];
                const CodeGenFunctionHelpers::FunctionParameterInfo laterParamInfo  = paramInfos[laterParamIndex];
                futureSourceRegs.push_back(parameterSourcePhysReg(callConv, laterParamInfo));
            }

            builder.addVirtualRegForbiddenPhysRegs(symbolPayload.reg, futureSourceRegs);
            CodeGenFunctionHelpers::emitLoadFunctionParameterToReg(codeGen, symbolFunc, paramInfo, symbolPayload.reg);
            symbolPayload.setValueOrAddress(paramInfo.isIndirect);

            codeGen.setVariablePayload(*symVar, symbolPayload);
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
            const ScopedDebugNoStep noStep(builder, true);
            emitLocalStackFrameEpilogue(codeGen, callConvKind);
            builder.emitRet();
            return Result::Continue;
        }

        SWC_ASSERT(exprRef.isValid());

        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        if (normalizedRet.isIndirect)
        {
            // Hidden first argument points to caller-provided return storage.
            const MicroReg outputStorageReg = codeGen.currentFunctionIndirectReturnReg();
            SWC_ASSERT(outputStorageReg.isValid());
            if (exprPayload.isAddress())
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload.reg, normalizedRet.indirectSize);
            }
            else
            {
                const uint32_t copySize = normalizedRet.indirectSize;
                auto           copyBits = MicroOpBits::Zero;
                if (copySize == 1 || copySize == 2 || copySize == 4 || copySize == 8)
                    copyBits = microOpBitsFromChunkSize(copySize);
                if (copyBits != MicroOpBits::Zero)
                    builder.emitLoadMemReg(outputStorageReg, 0, exprPayload.reg, copyBits);
                else
                    CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload.reg, copySize);
            }

            builder.emitLoadRegReg(callConv.intReturn, outputStorageReg, MicroOpBits::B64);
        }
        else
        {
            // Direct returns are normalized to ABI return registers (int/float lane).
            const bool      isAddressed    = exprPayload.isAddress();
            const TypeInfo& returnTypeInfo = codeGen.ctx().typeMgr().get(returnTypeRef);
            SWC_ASSERT(!shouldMaterializeAddressBackedValue(codeGen, returnTypeInfo, normalizedRet));
            ABICall::materializeValueToReturnRegs(builder, callConvKind, exprPayload.reg, isAddressed, normalizedRet);
        }

        {
            const ScopedDebugNoStep noStep(builder, true);
            emitLocalStackFrameEpilogue(codeGen, callConvKind);
            builder.emitRet();
        }
        return Result::Continue;
    }

    bool isActiveFunctionRoot(CodeGen& codeGen, AstNodeRef declRef)
    {
        const AstNodeRef currentDeclRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
        const AstNodeRef activeDeclRef  = codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef();
        return currentDeclRef == declRef && activeDeclRef == declRef;
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
        if (normalizedRet.isIndirect)
        {
            SWC_ASSERT(!callConv.intArgRegs.empty());
            const ScopedDebugNoStep noStep(codeGen.builder(), true);
            const MicroReg          outputStorageReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegReg(outputStorageReg, callConv.intArgRegs[0], MicroOpBits::B64);
            codeGen.setCurrentFunctionIndirectReturnReg(outputStorageReg);
        }

        SmallVector<CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos;
        collectFunctionParameterInfos(paramInfos, codeGen, symbolFunc);
        buildLocalStackLayout(codeGen);
        {
            const ScopedDebugNoStep noStep(codeGen.builder(), true);
            materializeRegisterParameters(codeGen, symbolFunc, paramInfos);
            materializeStackParameters(codeGen, symbolFunc, paramInfos);
            emitLocalStackFramePrologue(codeGen, callConvKind);
            spillParametersToDebugSlots(codeGen, symbolFunc);
        }

        return Result::Continue;
    }

    Result codeGenFunctionLikePostNode(CodeGen& codeGen, AstNodeRef declRef, AstNodeRef bodyRef, bool hasExpressionBody)
    {
        declRef = codeGen.viewZero(declRef).nodeRef();
        if (!isActiveFunctionRoot(codeGen, declRef))
            return Result::Continue;

        const SymbolFunction&                  symbolFunc    = codeGen.function();
        const CallConvKind                     callConvKind  = symbolFunc.callConvKind();
        const CallConv&                        callConv      = CallConv::get(callConvKind);
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);

        if (hasExpressionBody)
        {
            SWC_ASSERT(bodyRef.isValid());
            return emitFunctionReturn(codeGen, symbolFunc, bodyRef);
        }

        if (normalizedRet.isVoid)
            return emitFunctionReturn(codeGen, symbolFunc, AstNodeRef::invalid());

        return Result::Continue;
    }
}

Result AstFunctionDecl::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    return codeGenFunctionLikePreBody(codeGen, codeGen.curNodeRef(), childRef, nodeBodyRef);
}

Result AstFunctionDecl::codeGenPostNode(CodeGen& codeGen) const
{
    return codeGenFunctionLikePostNode(codeGen, codeGen.curNodeRef(), nodeBodyRef, hasFlag(AstFunctionFlagsE::Short));
}

Result AstFunctionExpr::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    return codeGenFunctionLikePreBody(codeGen, codeGen.curNodeRef(), childRef, nodeBodyRef);
}

Result AstFunctionExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const AstNodeRef declRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
    if (!isActiveFunctionRoot(codeGen, declRef))
    {
        auto&                     symFunc = functionExprSymbol(codeGen, declRef);
        const SemaNodeView        view    = codeGen.curViewType();
        const CodeGenNodePayload& payload = codeGen.setPayloadValue(declRef, view.typeRef());
        codeGen.builder().emitLoadRegPtrReloc(payload.reg, 0, ConstantRef::invalid(), &symFunc);
        return Result::Continue;
    }

    const bool hasExpressionBody = nodeBodyRef.isValid() && codeGen.node(nodeBodyRef).isNot(AstNodeId::EmbeddedBlock);
    return codeGenFunctionLikePostNode(codeGen, declRef, nodeBodyRef, hasExpressionBody);
}

Result AstReturnStmt::codeGenPostNode(CodeGen& codeGen) const
{
    if (codeGen.frame().hasCurrentInlineContext())
    {
        const CodeGenFrame::InlineContext& inlineCtx = codeGen.frame().currentInlineContext();
        SWC_ASSERT(inlineCtx.payload != nullptr);
        return emitInlineReturn(codeGen, *inlineCtx.payload, nodeExprRef, inlineCtx.doneLabel);
    }

    return emitFunctionReturn(codeGen, codeGen.function(), nodeExprRef);
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, nodeExprRef);
}

SWC_END_NAMESPACE();
