#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenReferenceHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ForeachLoopRuntimeState
    {
        uint64_t base  = 0;
        uint64_t count = 0;
        uint64_t index = 0;
    };

    struct ForeachStmtCodeGenPayload
    {
        MicroLabelRef         loopLabel        = MicroLabelRef::invalid();
        MicroLabelRef         whereFalseLabel  = MicroLabelRef::invalid();
        MicroLabelRef         continueLabel    = MicroLabelRef::invalid();
        MicroLabelRef         doneLabel        = MicroLabelRef::invalid();
        MicroReg              baseReg          = MicroReg::invalid();
        MicroReg              countReg         = MicroReg::invalid();
        MicroReg              indexReg         = MicroReg::invalid();
        uint32_t              aliasSymbolCount = 0;
        const SymbolVariable* stateSym         = nullptr;
        const SymbolVariable* sourceSpillSym   = nullptr;
        uint64_t              elementSize      = 0;
        uint64_t              valueSize        = 0;
        bool                  reverse          = false;
        bool                  enumValues       = false;
    };

    ForeachStmtCodeGenPayload* foreachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<ForeachStmtCodeGenPayload>(nodeRef);
    }

    ForeachStmtCodeGenPayload& setForeachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const ForeachStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseForeachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        ForeachStmtCodeGenPayload* payload = foreachStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    bool foreachUsesCustomVisit(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        const auto* payload = codeGen.sema().semaPayload<LoopSemaPayload>(nodeRef);
        return payload && payload->usesCustomVisit;
    }

    std::span<const Symbol* const> foreachSymbols(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        SemaNodeView symbolsView = codeGen.viewSymbolList(nodeRef);
        if (symbolsView.symList().size() >= 2)
            return {symbolsView.symList().data(), symbolsView.symList().size()};

        const AstNodeRef resolvedRef = codeGen.resolvedNodeRef(nodeRef);
        if (resolvedRef.isValid() && resolvedRef != nodeRef)
        {
            symbolsView = codeGen.viewSymbolList(resolvedRef);
            if (symbolsView.symList().size() >= 2)
                return {symbolsView.symList().data(), symbolsView.symList().size()};
        }

        if (const auto* payload = codeGen.sema().semaPayload<LoopSemaPayload>(nodeRef);
            payload && payload->localSymbols.size() >= 2)
            return {payload->localSymbols.data(), payload->localSymbols.size()};

        if (resolvedRef.isValid() && resolvedRef != nodeRef)
        {
            if (const auto* payload = codeGen.sema().semaPayload<LoopSemaPayload>(resolvedRef);
                payload && payload->localSymbols.size() >= 2)
                return {payload->localSymbols.data(), payload->localSymbols.size()};
        }

        return {};
    }

    MicroReg materializeForeachInternalStackAddress(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        SWC_ASSERT(symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());
        return codeGen.offsetAddressReg(codeGen.localStackBaseReg(), symVar.offset());
    }

    MicroReg materializeForeachSourceAddress(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState, const CodeGenNodePayload& sourcePayload, const TypeInfo& sourceType)
    {
        if (sourcePayload.isAddress())
            return sourcePayload.reg;

        const uint64_t sizeOfValue = sourceType.sizeOf(codeGen.ctx());
        if (sizeOfValue != 1 && sizeOfValue != 2 && sizeOfValue != 4 && sizeOfValue != 8)
            return sourcePayload.reg;

        SWC_ASSERT(loopState.sourceSpillSym != nullptr);

        // Foreach needs a stable base pointer across iterations, so spill small by-value sources into the
        // hidden storage symbol reserved for the loop state.
        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg spillAddrReg = materializeForeachInternalStackAddress(codeGen, *(loopState.sourceSpillSym));
        builder.emitLoadMemReg(spillAddrReg, 0, sourcePayload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfValue)));
        return spillAddrReg;
    }

    CodeGenNodePayload resolveForeachVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.isClosureCapture())
            return CodeGenFunctionHelpers::resolveClosureCapturePayload(codeGen, symVar);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar))
                return *symbolPayload;
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        {
            if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar))
                return *symbolPayload;
            return codeGen.resolveLocalStackPayload(symVar);
        }

        if (symVar.hasGlobalStorage())
        {
            CodeGenNodePayload symbolPayload;
            symbolPayload.typeRef = symVar.typeRef();
            symbolPayload.setIsAddress();
            symbolPayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(symbolPayload.reg, symVar.globalStorageKind(), symVar.offset());
            codeGen.setVariablePayload(symVar, symbolPayload);
            return symbolPayload;
        }

        if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            return codeGen.resolveLocalStackPayload(symVar);

        // Foreach aliases are not guaranteed to be part of function-local-variable reset,
        // so always refresh their payload instead of reusing any cached symbol payload.
        CodeGenNodePayload regPayload;
        regPayload.typeRef = symVar.typeRef();
        regPayload.setIsValue();
        regPayload.reg = codeGen.nextVirtualRegisterForType(symVar.typeRef());
        codeGen.setVariablePayload(symVar, regPayload);
        return regPayload;
    }

    using CodeGenFunctionHelpers::resolveStoredVariablePayload;

    CodeGenNodePayload foreachExprPayload(CodeGen& codeGen, AstNodeRef exprRef)
    {
        if (const auto* payload = codeGen.safePayload(exprRef))
        {
            if (payload->reg.isValid())
                return *payload;
        }

        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (storedView.sym() && storedView.sym()->isVariable())
        {
            const auto& symVar = storedView.sym()->cast<SymbolVariable>();
            if (symVar.isClosureCapture() ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) ||
                symVar.hasGlobalStorage() ||
                codeGen.variablePayload(symVar) ||
                (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
                return resolveStoredVariablePayload(codeGen, symVar);
        }

        return codeGen.payload(exprRef);
    }

    SemaNodeView foreachExprView(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Type);
        if (storedView.type() != nullptr)
            return storedView;
        return codeGen.viewType(exprRef);
    }

    const SymbolEnum* enumSymbolFromTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return nullptr;

        const TypeInfo& type             = codeGen.typeMgr().get(typeRef);
        TypeRef         unwrappedTypeRef = type.unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (!unwrappedTypeRef.isValid())
            unwrappedTypeRef = typeRef;

        const TypeInfo& unwrappedType = codeGen.typeMgr().get(unwrappedTypeRef);
        if (!unwrappedType.isEnum())
            return nullptr;

        return &unwrappedType.payloadSymEnum();
    }

    const SymbolEnum* foreachExprEnumSymbol(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SemaNodeView storedTypeView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Type);
        if (const SymbolEnum* symEnum = enumSymbolFromTypeRef(codeGen, storedTypeView.typeRef()))
            return symEnum;

        const SemaNodeView typeView = codeGen.viewType(exprRef);
        if (const SymbolEnum* symEnum = enumSymbolFromTypeRef(codeGen, typeView.typeRef()))
            return symEnum;

        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (storedView.sym() && storedView.sym()->isEnum())
            return &storedView.sym()->cast<SymbolEnum>();
        if (storedView.sym() && storedView.sym()->isAlias())
        {
            const auto& symAlias = storedView.sym()->cast<SymbolAlias>();
            if (symAlias.aliasedSymbol() && symAlias.aliasedSymbol()->isEnum())
                return &symAlias.aliasedSymbol()->cast<SymbolEnum>();
            if (const SymbolEnum* symEnum = enumSymbolFromTypeRef(codeGen, symAlias.underlyingTypeRef()))
                return symEnum;
        }

        const SemaNodeView symbolView = codeGen.viewSymbol(exprRef);
        if (symbolView.sym() && symbolView.sym()->isEnum())
            return &symbolView.sym()->cast<SymbolEnum>();
        if (symbolView.sym() && symbolView.sym()->isAlias())
        {
            const auto& symAlias = symbolView.sym()->cast<SymbolAlias>();
            if (symAlias.aliasedSymbol() && symAlias.aliasedSymbol()->isEnum())
                return &symAlias.aliasedSymbol()->cast<SymbolEnum>();
            return enumSymbolFromTypeRef(codeGen, symAlias.underlyingTypeRef());
        }

        return nullptr;
    }

    MicroReg emitForeachElementAddress(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        SWC_ASSERT(loopState.baseReg.isValid());
        SWC_ASSERT(loopState.indexReg.isValid());
        SWC_ASSERT(loopState.elementSize > 0);

        const MicroReg elementAddressReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadAddressAmcRegMem(elementAddressReg, MicroOpBits::B64, loopState.baseReg, loopState.indexReg, loopState.elementSize, 0, MicroOpBits::B64);
        return elementAddressReg;
    }

    MicroReg emitForeachValueAddress(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        const MicroReg elementAddressReg = emitForeachElementAddress(codeGen, loopState);
        if (!loopState.enumValues)
            return elementAddressReg;

        const MicroReg valueAddressReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(valueAddressReg, elementAddressReg, offsetof(Runtime::TypeValue, value), MicroOpBits::B64);
        return valueAddressReg;
    }

    MicroReg emitForeachStateAddressReg(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        SWC_ASSERT(loopState.stateSym != nullptr);
        return materializeForeachInternalStackAddress(codeGen, *(loopState.stateSym));
    }

    void emitForeachStoreLoopState(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        SWC_ASSERT(loopState.baseReg.isValid());
        SWC_ASSERT(loopState.countReg.isValid());
        SWC_ASSERT(loopState.indexReg.isValid());

        // Persist progress in the hidden state slot because loop callbacks and `continue` paths can
        // allocate fresh virtual registers before the next iteration.
        MicroBuilder&  builder         = codeGen.builder();
        const MicroReg stateAddressReg = emitForeachStateAddressReg(codeGen, loopState);
        builder.emitLoadMemReg(stateAddressReg, offsetof(ForeachLoopRuntimeState, base), loopState.baseReg, MicroOpBits::B64);
        builder.emitLoadMemReg(stateAddressReg, offsetof(ForeachLoopRuntimeState, count), loopState.countReg, MicroOpBits::B64);
        builder.emitLoadMemReg(stateAddressReg, offsetof(ForeachLoopRuntimeState, index), loopState.indexReg, MicroOpBits::B64);
    }

    void emitForeachLoadLoopState(CodeGen& codeGen, ForeachStmtCodeGenPayload& loopState)
    {
        MicroBuilder&  builder         = codeGen.builder();
        const MicroReg stateAddressReg = emitForeachStateAddressReg(codeGen, loopState);

        loopState.baseReg  = codeGen.nextVirtualIntRegister();
        loopState.countReg = codeGen.nextVirtualIntRegister();
        loopState.indexReg = codeGen.nextVirtualIntRegister();

        builder.emitLoadRegMem(loopState.baseReg, stateAddressReg, offsetof(ForeachLoopRuntimeState, base), MicroOpBits::B64);
        builder.emitLoadRegMem(loopState.countReg, stateAddressReg, offsetof(ForeachLoopRuntimeState, count), MicroOpBits::B64);
        builder.emitLoadRegMem(loopState.indexReg, stateAddressReg, offsetof(ForeachLoopRuntimeState, index), MicroOpBits::B64);
    }

    void registerForeachAliasImplicitDrops(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        const auto   symbols    = foreachSymbols(codeGen, codeGen.curNodeRef());
        const size_t aliasCount = std::min<size_t>(loopState.aliasSymbolCount, symbols.size());
        for (size_t i = 0; i < aliasCount; ++i)
            codeGen.registerImplicitDrop(symbols[i]->cast<SymbolVariable>());
    }

    Result emitForeachAliasDrops(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        const auto   symbols    = foreachSymbols(codeGen, codeGen.curNodeRef());
        const size_t aliasCount = std::min<size_t>(loopState.aliasSymbolCount, symbols.size());
        for (size_t i = 0; i < aliasCount; ++i)
        {
            const SymbolVariable& symVar = symbols[i]->cast<SymbolVariable>();
            if (!codeGen.hasLifecycle(symVar.typeRef(), CodeGen::LifecycleKind::Drop))
                continue;

            const CodeGenNodePayload valuePayload = resolveForeachVariablePayload(codeGen, symVar);
            if (!valuePayload.isAddress())
                continue;

            SWC_RESULT(codeGen.emitLifecycle(symVar.typeRef(), CodeGen::LifecycleKind::Drop, valuePayload.reg));
        }

        return Result::Continue;
    }

    Result emitForeachBindSymbols(CodeGen& codeGen, const AstForeachStmt& node, const ForeachStmtCodeGenPayload& loopState)
    {
        const auto   symbols    = foreachSymbols(codeGen, codeGen.curNodeRef());
        const size_t aliasCount = std::min<size_t>(loopState.aliasSymbolCount, symbols.size());
        if (!aliasCount)
            return Result::Continue;

        const MicroReg elementAddressReg = emitForeachValueAddress(codeGen, loopState);
        MicroBuilder&  builder           = codeGen.builder();

        const SymbolVariable&    valueSym     = symbols[0]->cast<SymbolVariable>();
        const CodeGenNodePayload valuePayload = resolveForeachVariablePayload(codeGen, valueSym);
        if (node.hasFlag(AstForeachStmtFlagsE::ByAddress))
        {
            if (valuePayload.isAddress())
                builder.emitLoadMemReg(valuePayload.reg, 0, elementAddressReg, MicroOpBits::B64);
            else
                builder.emitLoadRegReg(valuePayload.reg, elementAddressReg, MicroOpBits::B64);
        }
        else
        {
            SWC_ASSERT(loopState.valueSize <= std::numeric_limits<uint32_t>::max());
            if (valuePayload.isAddress())
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, valuePayload.reg, elementAddressReg, static_cast<uint32_t>(loopState.valueSize));
            }
            else
            {
                SWC_ASSERT(loopState.valueSize == 1 || loopState.valueSize == 2 || loopState.valueSize == 4 || loopState.valueSize == 8);
                builder.emitLoadRegMem(valuePayload.reg, elementAddressReg, 0, microOpBitsFromChunkSize(static_cast<uint32_t>(loopState.valueSize)));
            }

            // Foreach materializes a fresh by-value alias from the source element, so addressable
            // loop storage needs the same post-copy fixups as any other copied local.
            if (valuePayload.isAddress() && codeGen.hasLifecycle(valueSym.typeRef(), CodeGen::LifecycleKind::PostCopy))
                SWC_RESULT(codeGen.emitLifecycle(valueSym.typeRef(), CodeGen::LifecycleKind::PostCopy, valuePayload.reg));
        }

        if (aliasCount < 2)
            return Result::Continue;

        const SymbolVariable&    indexSym     = symbols[1]->cast<SymbolVariable>();
        const CodeGenNodePayload indexPayload = resolveForeachVariablePayload(codeGen, indexSym);
        if (indexPayload.isAddress())
            builder.emitLoadMemReg(indexPayload.reg, 0, loopState.indexReg, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(indexPayload.reg, loopState.indexReg, MicroOpBits::B64);
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

    Result emitForeachInit(CodeGen& codeGen, const AstForeachStmt& node, ForeachStmtCodeGenPayload& loopState)
    {
        const AstNodeRef exprRef = node.nodeExprRef;
        MicroBuilder&    builder = codeGen.builder();

        loopState.baseReg    = MicroReg::invalid();
        loopState.countReg   = codeGen.nextVirtualIntRegister();
        loopState.indexReg   = codeGen.nextVirtualIntRegister();
        loopState.enumValues = false;

        if (const SymbolEnum* symEnum = foreachExprEnumSymbol(codeGen, exprRef))
        {
            MicroReg typeInfoReg = MicroReg::invalid();
            SWC_RESULT(CodeGenConstantHelpers::loadTypeInfoConstantReg(typeInfoReg, codeGen, symEnum->typeRef()));

            loopState.enumValues  = true;
            loopState.elementSize = sizeof(Runtime::TypeValue);
            loopState.valueSize   = codeGen.typeMgr().get(symEnum->typeRef()).sizeOf(codeGen.ctx());
            SWC_ASSERT(loopState.elementSize > 0);
            SWC_ASSERT(loopState.valueSize > 0);

            loopState.baseReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(loopState.baseReg, typeInfoReg, offsetof(Runtime::TypeInfoEnum, values.ptr), MicroOpBits::B64);
            builder.emitLoadRegMem(loopState.countReg, typeInfoReg, offsetof(Runtime::TypeInfoEnum, values.count), MicroOpBits::B64);
        }
        else
        {
            const SemaNodeView exprView    = foreachExprView(codeGen, exprRef);
            CodeGenNodePayload exprPayload = foreachExprPayload(codeGen, exprRef);
            TypeRef            exprTypeRef = exprPayload.effectiveTypeRef(exprView.typeRef());
            CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, exprPayload, exprTypeRef);
            const TypeRef   unwrappedExprTypeRef = SemaHelpers::unwrapAliasRefType(codeGen.ctx(), exprTypeRef);
            const TypeInfo& exprType             = codeGen.typeMgr().get(unwrappedExprTypeRef);

            if (exprType.isArray())
            {
                const TypeInfo& elementType = codeGen.typeMgr().get(exprType.payloadArrayElemTypeRef());
                loopState.elementSize       = elementType.sizeOf(codeGen.ctx());
                loopState.valueSize         = loopState.elementSize;
                SWC_ASSERT(loopState.elementSize > 0);

                const uint64_t totalSize  = exprType.sizeOf(codeGen.ctx());
                const uint64_t totalCount = totalSize / loopState.elementSize;
                loopState.baseReg         = materializeForeachSourceAddress(codeGen, loopState, exprPayload, exprType);
                builder.emitLoadRegImm(loopState.countReg, ApInt(totalCount, 64), MicroOpBits::B64);
            }
            else
            {
                TypeRef  valueTypeRef = TypeRef::invalid();
                uint64_t countOffset  = offsetof(Runtime::Slice<std::byte>, count);
                if (exprType.isCString())
                {
                    valueTypeRef          = codeGen.typeMgr().typeU8();
                    loopState.elementSize = 1;
                    loopState.valueSize   = 1;
                    loopState.baseReg     = emitLoadCStringReg(codeGen, exprPayload);
                    emitCStringCountReg(codeGen, loopState.countReg, loopState.baseReg);
                }
                else if (exprType.isSlice())
                    valueTypeRef = exprType.payloadTypeRef();
                else if (exprType.isString())
                {
                    valueTypeRef = codeGen.typeMgr().typeU8();
                    countOffset  = offsetof(Runtime::String, length);
                }
                else if (exprType.isVariadic())
                    valueTypeRef = codeGen.typeMgr().typeAny();
                else if (exprType.isTypedVariadic())
                    valueTypeRef = exprType.payloadTypeRef();
                else
                    SWC_UNREACHABLE();

                if (!exprType.isCString())
                {
                    const TypeInfo& valueType = codeGen.typeMgr().get(valueTypeRef);
                    loopState.elementSize     = valueType.sizeOf(codeGen.ctx());
                    loopState.valueSize       = loopState.elementSize;

                    const MicroReg sourceAddressReg = materializeForeachSourceAddress(codeGen, loopState, exprPayload, exprType);
                    loopState.baseReg               = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegMem(loopState.baseReg, sourceAddressReg, offsetof(Runtime::Slice<std::byte>, ptr), MicroOpBits::B64);
                    builder.emitLoadRegMem(loopState.countReg, sourceAddressReg, countOffset, MicroOpBits::B64);
                }
            }
        }

        if (loopState.reverse)
            builder.emitLoadRegReg(loopState.indexReg, loopState.countReg, MicroOpBits::B64);
        else
            builder.emitLoadRegImm(loopState.indexReg, ApInt(0, 64), MicroOpBits::B64);

        emitForeachStoreLoopState(codeGen, loopState);
        return Result::Continue;
    }
}

Result AstForeachStmt::codeGenPreNode(CodeGen& codeGen) const
{
    if (foreachUsesCustomVisit(codeGen, codeGen.curNodeRef()))
    {
        const AstNodeRef resolvedRef = codeGen.resolvedNodeRef(codeGen.curNodeRef());
        if (resolvedRef.isValid() && resolvedRef != codeGen.curNodeRef())
            SWC_RESULT(codeGen.emitNodeNow(resolvedRef));
        return Result::SkipChildren;
    }

    ForeachStmtCodeGenPayload loopState;
    const auto                symbols = foreachSymbols(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(symbols.size() >= 2);
    if (symbols.size() >= 2)
    {
        const size_t stateIndex    = symbols.size() - 2;
        const size_t spillIndex    = symbols.size() - 1;
        loopState.aliasSymbolCount = static_cast<uint32_t>(std::min<size_t>(2, stateIndex));
        loopState.stateSym         = &symbols[stateIndex]->cast<SymbolVariable>();
        loopState.sourceSpillSym   = &symbols[spillIndex]->cast<SymbolVariable>();
    }

    MicroBuilder& builder     = codeGen.builder();
    loopState.loopLabel       = builder.createLabel();
    loopState.whereFalseLabel = builder.createLabel();
    loopState.continueLabel   = builder.createLabel();
    loopState.doneLabel       = builder.createLabel();
    loopState.reverse         = modifierFlags.has(AstModifierFlagsE::Reverse);
    setForeachStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForeachStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);
    if (childRef != whereRef && !(childRef == bodyRef && whereRef.isInvalid()))
        return Result::Continue;

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->continueLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    frame.setCurrentLoopIndex(loopState->indexReg, codeGen.typeMgr().typeU64());
    codeGen.pushFrame(frame);
    codeGen.pushDeferScope(AstNodeRef::invalid(), codeGen.curNodeRef());
    registerForeachAliasImplicitDrops(codeGen, *loopState);
    return Result::Continue;
}

Result AstForeachStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef  = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);

    MicroBuilder& builder = codeGen.builder();

    if (childRef == exprRef)
    {
        SWC_RESULT(emitForeachInit(codeGen, *this, *loopState));
        builder.placeLabel(loopState->loopLabel);
        // The loop head always reloads the persisted state because the previous iteration may have crossed
        // callbacks that invalidated the current virtual register assignments.
        emitForeachLoadLoopState(codeGen, *loopState);
        builder.emitCmpRegImm(loopState->countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, loopState->doneLabel);
        if (loopState->reverse)
        {
            builder.emitLoadRegReg(loopState->indexReg, loopState->countReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        }
        SWC_RESULT(emitForeachBindSymbols(codeGen, *this, *loopState));
        return Result::Continue;
    }

    if (childRef == whereRef)
    {
        const CodeGenNodePayload& wherePayload = codeGen.payload(whereRef);
        const SemaNodeView        whereView    = codeGen.viewType(whereRef);
        CodeGenCompareHelpers::emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), loopState->whereFalseLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        SWC_RESULT(codeGen.popDeferScope());

        if (whereRef.isInvalid() && codeGen.currentInstructionBlocksFallthrough() && !codeGen.frame().currentLoopHasContinueJump())
        {
            codeGen.popFrame();
            return Result::Continue;
        }

        builder.setCurrentDebugSourceCodeRef(codeGen.node(codeGen.curNodeRef()).debugCodeRef());
        builder.setCurrentDebugNoStep(false);
        if (whereRef.isValid())
        {
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->continueLabel);
            builder.placeLabel(loopState->whereFalseLabel);
            SWC_RESULT(emitForeachAliasDrops(codeGen, *loopState));
        }
        builder.placeLabel(loopState->continueLabel);
        emitForeachLoadLoopState(codeGen, *loopState);
        if (!loopState->reverse)
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(loopState->countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        emitForeachStoreLoopState(codeGen, *loopState);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        codeGen.popFrame();
        return Result::Continue;
    }

    return Result::Continue;
}

Result AstForeachStmt::codeGenPostNode(CodeGen& codeGen)
{
    if (foreachUsesCustomVisit(codeGen, codeGen.curNodeRef()))
    {
        const AstNodeRef resolvedRef = codeGen.resolvedNodeRef(codeGen.curNodeRef());
        if (resolvedRef.isValid() && resolvedRef != codeGen.curNodeRef())
            return Result::Continue;

        const auto* payload = codeGen.sema().semaPayload<LoopSemaPayload>(codeGen.curNodeRef());
        SWC_ASSERT(payload && payload->visitFn);
        codeGen.sema().setSymbol(codeGen.curNodeRef(), payload->visitFn);
        return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
    }

    const ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->doneLabel);
    eraseForeachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
