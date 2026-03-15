#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
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

    struct LoopStmtCodeGenPayload
    {
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
    };

    struct ForCStyleStmtCodeGenPayload
    {
        MicroLabelRef loopLabel     = MicroLabelRef::invalid();
        MicroLabelRef bodyLabel     = MicroLabelRef::invalid();
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
    };

    struct ForeachStmtCodeGenPayload
    {
        MicroLabelRef   loopLabel        = MicroLabelRef::invalid();
        MicroLabelRef   continueLabel    = MicroLabelRef::invalid();
        MicroLabelRef   doneLabel        = MicroLabelRef::invalid();
        MicroReg        baseReg          = MicroReg::invalid();
        MicroReg        countReg         = MicroReg::invalid();
        MicroReg        indexReg         = MicroReg::invalid();
        uint32_t        aliasSymbolCount = 0;
        SymbolVariable* stateSym         = nullptr;
        SymbolVariable* sourceSpillSym   = nullptr;
        uint64_t        elementSize      = 0;
        bool            reverse          = false;
    };

    struct ForStmtCodeGenPayload
    {
        MicroLabelRef   loopLabel       = MicroLabelRef::invalid();
        MicroLabelRef   continueLabel   = MicroLabelRef::invalid();
        MicroLabelRef   doneLabel       = MicroLabelRef::invalid();
        MicroReg        indexReg        = MicroReg::invalid();
        MicroReg        boundReg        = MicroReg::invalid();
        SymbolVariable* indexSym        = nullptr;
        TypeRef         indexTypeRef    = TypeRef::invalid();
        bool            reverse         = false;
        bool            inclusive       = false;
        bool            unsignedCmp     = false;
        bool            hasContinueJump = false;
    };

    LoopStmtCodeGenPayload* loopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<LoopStmtCodeGenPayload>(nodeRef);
    }

    LoopStmtCodeGenPayload& setLoopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const LoopStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseLoopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        LoopStmtCodeGenPayload* payload = loopStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    ForCStyleStmtCodeGenPayload* forCStyleStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<ForCStyleStmtCodeGenPayload>(nodeRef);
    }

    ForCStyleStmtCodeGenPayload& setForCStyleStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const ForCStyleStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseForCStyleStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        ForCStyleStmtCodeGenPayload* payload = forCStyleStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

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

    ForStmtCodeGenPayload* forStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<ForStmtCodeGenPayload>(nodeRef);
    }

    ForStmtCodeGenPayload& setForStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const ForStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseForStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        ForStmtCodeGenPayload* payload = forStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    void emitConditionFalseJump(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, MicroLabelRef falseLabel)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits condBits = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        const MicroReg    condReg  = codeGen.nextVirtualIntRegister();

        MicroBuilder& builder = codeGen.builder();
        if (payload.isAddress())
            builder.emitLoadRegMem(condReg, payload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, payload.reg, condBits);

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, falseLabel);
    }

    MicroCond loopLessCond(bool unsignedCompare)
    {
        return unsignedCompare ? MicroCond::Below : MicroCond::Less;
    }

    MicroCond loopLessEqualCond(bool unsignedCompare)
    {
        return unsignedCompare ? MicroCond::BelowOrEqual : MicroCond::LessOrEqual;
    }

    MicroCond loopGreaterCond(bool unsignedCompare)
    {
        return unsignedCompare ? MicroCond::Above : MicroCond::Greater;
    }

    MicroCond loopGreaterEqualCond(bool unsignedCompare)
    {
        return unsignedCompare ? MicroCond::AboveOrEqual : MicroCond::GreaterOrEqual;
    }

    MicroReg materializeLoopValueReg(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits opBits   = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        const MicroReg    outReg   = codeGen.nextVirtualIntRegister();

        if (payload.isAddress())
            codeGen.builder().emitLoadRegMem(outReg, payload.reg, 0, opBits);
        else
            codeGen.builder().emitLoadRegReg(outReg, payload.reg, opBits);

        return outReg;
    }

    MicroReg materializeLoopZeroReg(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits opBits   = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        const MicroReg    outReg   = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegImm(outReg, ApInt(0, 64), opBits);
        return outReg;
    }

    void emitLoopVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar, MicroReg valueReg)
    {
        CodeGenNodePayload symbolPayload;
        symbolPayload.typeRef = symVar.typeRef();
        symbolPayload.setIsValue();
        symbolPayload.reg = valueReg;
        codeGen.setVariablePayload(symVar, symbolPayload);
    }

    bool currentInstructionIsTerminator(const CodeGen& codeGen)
    {
        const MicroInstrRef lastRef = codeGen.builder().instructions().findPreviousInstructionRef(MicroInstrRef::invalid());
        if (lastRef.isInvalid())
            return false;

        const MicroInstr* lastInst = codeGen.builder().instructions().ptr(lastRef);
        if (!lastInst || lastInst->op == MicroInstrOpcode::Label)
            return false;

        return MicroInstrInfo::isTerminatorInstruction(*lastInst);
    }

    CodeGenNodePayload resolveForeachVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar);

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

        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg spillAddrReg = materializeForeachInternalStackAddress(codeGen, *(loopState.sourceSpillSym));
        builder.emitLoadMemReg(spillAddrReg, 0, sourcePayload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfValue)));
        return spillAddrReg;
    }

    CodeGenNodePayload resolveForeachVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
                return *symbolPayload;
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        {
            if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
                return *symbolPayload;
            return codeGen.resolveLocalStackPayload(symVar);
        }

        // Foreach aliases are not guaranteed to be part of function local-variable reset,
        // so always refresh their payload instead of reusing any cached symbol payload.
        CodeGenNodePayload regPayload;
        regPayload.typeRef = symVar.typeRef();
        regPayload.setIsValue();
        regPayload.reg = codeGen.nextVirtualRegisterForType(symVar.typeRef());
        codeGen.setVariablePayload(symVar, regPayload);
        return regPayload;
    }

    CodeGenNodePayload resolveForeachStoredVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
            return *symbolPayload;

        if (symVar.hasGlobalStorage())
        {
            CodeGenNodePayload globalPayload;
            globalPayload.typeRef = symVar.typeRef();
            globalPayload.setIsAddress();
            globalPayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(globalPayload.reg, symVar.globalStorageKind(), symVar.offset());
            return globalPayload;
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return codeGen.resolveLocalStackPayload(symVar);

        if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            return codeGen.resolveLocalStackPayload(symVar);

        SWC_UNREACHABLE();
    }

    CodeGenNodePayload foreachExprPayload(CodeGen& codeGen, AstNodeRef exprRef)
    {
        if (const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(exprRef))
        {
            if (payload->reg.isValid())
                return *payload;
        }

        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (storedView.sym() && storedView.sym()->isVariable())
        {
            const auto& symVar = storedView.sym()->cast<SymbolVariable>();
            if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) ||
                symVar.hasGlobalStorage() ||
                CodeGen::variablePayload(symVar) ||
                (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
                return resolveForeachStoredVariablePayload(codeGen, symVar);
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

    void emitForInit(CodeGen& codeGen, const AstForStmt& node, ForStmtCodeGenPayload& loopState)
    {
        const AstNodeRef   exprRef   = codeGen.resolvedNodeRef(node.nodeExprRef);
        const SemaNodeView exprView  = codeGen.viewType(exprRef);
        const TypeInfo&    indexType = *(exprView.type());
        const MicroOpBits  opBits    = CodeGenTypeHelpers::conditionBits(indexType, codeGen.ctx());
        MicroBuilder&      builder   = codeGen.builder();

        loopState.indexTypeRef = exprView.typeRef();
        loopState.unsignedCmp  = indexType.isIntUnsigned();
        loopState.indexReg     = codeGen.nextVirtualIntRegister();

        MicroReg lowerReg = MicroReg::invalid();
        MicroReg upperReg = MicroReg::invalid();
        if (codeGen.node(exprRef).is(AstNodeId::RangeExpr))
        {
            const AstRangeExpr& rangeExpr = codeGen.node(exprRef).cast<AstRangeExpr>();
            loopState.inclusive           = rangeExpr.hasFlag(AstRangeExprFlagsE::Inclusive);

            if (rangeExpr.nodeExprDownRef.isValid())
            {
                const AstNodeRef downRef = codeGen.resolvedNodeRef(rangeExpr.nodeExprDownRef);
                lowerReg                 = materializeLoopValueReg(codeGen, codeGen.payload(downRef), loopState.indexTypeRef);
            }
            else
            {
                lowerReg = materializeLoopZeroReg(codeGen, loopState.indexTypeRef);
            }

            const AstNodeRef upRef = codeGen.resolvedNodeRef(rangeExpr.nodeExprUpRef);
            upperReg               = materializeLoopValueReg(codeGen, codeGen.payload(upRef), loopState.indexTypeRef);
        }
        else
        {
            lowerReg = materializeLoopZeroReg(codeGen, loopState.indexTypeRef);
            upperReg = materializeLoopValueReg(codeGen, codeGen.payload(exprRef), loopState.indexTypeRef);
        }

        if (loopState.reverse)
        {
            loopState.boundReg = lowerReg;
            builder.emitCmpRegReg(upperReg, lowerReg, opBits);
            if (loopState.inclusive)
            {
                builder.emitJumpToLabel(loopLessCond(loopState.unsignedCmp), MicroOpBits::B32, loopState.doneLabel);
                builder.emitLoadRegReg(loopState.indexReg, upperReg, opBits);
            }
            else
            {
                builder.emitJumpToLabel(loopLessEqualCond(loopState.unsignedCmp), MicroOpBits::B32, loopState.doneLabel);
                builder.emitLoadRegReg(loopState.indexReg, upperReg, opBits);
                builder.emitOpBinaryRegImm(loopState.indexReg, ApInt(1, 64), MicroOp::Subtract, opBits);
            }
        }
        else
        {
            loopState.boundReg = upperReg;
            builder.emitLoadRegReg(loopState.indexReg, lowerReg, opBits);
            builder.emitCmpRegReg(loopState.indexReg, upperReg, opBits);
            builder.emitJumpToLabel(loopState.inclusive ? loopGreaterCond(loopState.unsignedCmp) : loopGreaterEqualCond(loopState.unsignedCmp),
                                    MicroOpBits::B32,
                                    loopState.doneLabel);
        }

        if (loopState.indexSym != nullptr)
            emitLoopVariablePayload(codeGen, *loopState.indexSym, loopState.indexReg);
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

    void emitForeachBindSymbols(CodeGen& codeGen, const AstForeachStmt& node, const ForeachStmtCodeGenPayload& loopState)
    {
        const SemaNodeView symbolsView = codeGen.viewSymbolList(codeGen.curNodeRef());
        const auto         symbols     = symbolsView.symList();
        const size_t       aliasCount  = std::min<size_t>(loopState.aliasSymbolCount, symbols.size());
        if (!aliasCount)
            return;

        const MicroReg elementAddressReg = emitForeachElementAddress(codeGen, loopState);
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
            SWC_ASSERT(loopState.elementSize <= std::numeric_limits<uint32_t>::max());
            if (valuePayload.isAddress())
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, valuePayload.reg, elementAddressReg, static_cast<uint32_t>(loopState.elementSize));
            }
            else
            {
                SWC_ASSERT(loopState.elementSize == 1 || loopState.elementSize == 2 || loopState.elementSize == 4 || loopState.elementSize == 8);
                builder.emitLoadRegMem(valuePayload.reg, elementAddressReg, 0, microOpBitsFromChunkSize(static_cast<uint32_t>(loopState.elementSize)));
            }
        }

        if (aliasCount < 2)
            return;

        const SymbolVariable&    indexSym     = symbols[1]->cast<SymbolVariable>();
        const CodeGenNodePayload indexPayload = resolveForeachVariablePayload(codeGen, indexSym);
        if (indexPayload.isAddress())
            builder.emitLoadMemReg(indexPayload.reg, 0, loopState.indexReg, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(indexPayload.reg, loopState.indexReg, MicroOpBits::B64);
    }

    void emitForeachInit(CodeGen& codeGen, const AstForeachStmt& node, ForeachStmtCodeGenPayload& loopState)
    {
        const AstNodeRef         exprRef     = node.nodeExprRef;
        const SemaNodeView       exprView    = foreachExprView(codeGen, exprRef);
        const CodeGenNodePayload exprPayload = foreachExprPayload(codeGen, exprRef);
        const TypeInfo&          exprType    = *(exprView.type());
        MicroBuilder&            builder     = codeGen.builder();

        loopState.baseReg  = MicroReg::invalid();
        loopState.countReg = codeGen.nextVirtualIntRegister();
        loopState.indexReg = codeGen.nextVirtualIntRegister();

        if (exprType.isArray())
        {
            const TypeInfo& elementType = codeGen.typeMgr().get(exprType.payloadArrayElemTypeRef());
            loopState.elementSize       = elementType.sizeOf(codeGen.ctx());
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
            if (exprType.isSlice())
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

            const TypeInfo& valueType = codeGen.typeMgr().get(valueTypeRef);
            loopState.elementSize     = valueType.sizeOf(codeGen.ctx());

            const MicroReg sourceAddressReg = materializeForeachSourceAddress(codeGen, loopState, exprPayload, exprType);
            loopState.baseReg               = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(loopState.baseReg, sourceAddressReg, offsetof(Runtime::Slice<std::byte>, ptr), MicroOpBits::B64);
            builder.emitLoadRegMem(loopState.countReg, sourceAddressReg, countOffset, MicroOpBits::B64);
        }

        if (loopState.reverse)
            builder.emitLoadRegReg(loopState.indexReg, loopState.countReg, MicroOpBits::B64);
        else
            builder.emitLoadRegImm(loopState.indexReg, ApInt(0, 64), MicroOpBits::B64);

        emitForeachStoreLoopState(codeGen, loopState);
    }
}

Result AstForCStyleStmt::codeGenPreNode(CodeGen& codeGen)
{
    ForCStyleStmtCodeGenPayload loopState;
    loopState.loopLabel     = codeGen.builder().createLabel();
    loopState.bodyLabel     = codeGen.builder().createLabel();
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    setForCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForCStyleStmtCodeGenPayload* loopState = forCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef     = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef postStmtRef = codeGen.resolvedNodeRef(nodePostStmtRef);
    const AstNodeRef bodyRef     = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        codeGen.builder().placeLabel(loopState->loopLabel);
        return Result::Continue;
    }

    if (childRef == postStmtRef)
    {
        codeGen.builder().placeLabel(loopState->continueLabel);

        CodeGenFrame frame = codeGen.frame();
        frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
        frame.setCurrentLoopContinueLabel(loopState->loopLabel);
        frame.setCurrentLoopBreakLabel(loopState->doneLabel);
        codeGen.pushFrame(frame);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        codeGen.builder().placeLabel(loopState->bodyLabel);

        CodeGenFrame frame = codeGen.frame();
        frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
        frame.setCurrentLoopContinueLabel(postStmtRef.isValid() ? loopState->continueLabel : loopState->loopLabel);
        frame.setCurrentLoopBreakLabel(loopState->doneLabel);
        codeGen.pushFrame(frame);
    }

    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForCStyleStmtCodeGenPayload* loopState = forCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef     = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef postStmtRef = codeGen.resolvedNodeRef(nodePostStmtRef);
    const AstNodeRef bodyRef     = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        emitConditionFalseJump(codeGen, exprPayload, exprView.typeRef(), loopState->doneLabel);
        if (postStmtRef.isValid())
        {
            const ScopedDebugNoStep noStep(codeGen.builder(), true);
            codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->bodyLabel);
        }
        return Result::Continue;
    }

    if (childRef == postStmtRef)
    {
        {
            const ScopedDebugNoStep noStep(codeGen.builder(), true);
            codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        }
        codeGen.popFrame();
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        const ScopedDebugNoStep noStep(codeGen.builder(), true);
        codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, postStmtRef.isValid() ? loopState->continueLabel : loopState->loopLabel);
        codeGen.popFrame();
    }

    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPostNode(CodeGen& codeGen)
{
    const ForCStyleStmtCodeGenPayload* loopState = forCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->doneLabel);
    eraseForCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstForStmt::codeGenPreNode(CodeGen& codeGen) const
{
    ForStmtCodeGenPayload loopState;
    loopState.loopLabel     = codeGen.builder().createLabel();
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    loopState.reverse       = modifierFlags.has(AstModifierFlagsE::Reverse);

    if (tokNameRef.isValid())
    {
        const SemaNodeView symbolView = codeGen.curViewSymbol();
        if (symbolView.sym() != nullptr)
            loopState.indexSym = &symbolView.sym()->cast<SymbolVariable>();
    }

    setForStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForStmtCodeGenPayload* loopState = forStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);
    if (childRef != whereRef && !(childRef == bodyRef && whereRef.isInvalid()))
        return Result::Continue;

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->continueLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    frame.setCurrentLoopIndex(loopState->indexReg, loopState->indexTypeRef);
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstForStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    ForStmtCodeGenPayload* loopState = forStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef  = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        emitForInit(codeGen, *this, *loopState);
        codeGen.builder().placeLabel(loopState->loopLabel);
        return Result::Continue;
    }

    if (childRef == whereRef)
    {
        const CodeGenNodePayload& wherePayload = codeGen.payload(whereRef);
        const SemaNodeView        whereView    = codeGen.viewType(whereRef);
        emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), loopState->continueLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        if (currentInstructionIsTerminator(codeGen) && !loopState->hasContinueJump)
        {
            codeGen.popFrame();
            return Result::Continue;
        }

        const TypeInfo&   indexType = codeGen.typeMgr().get(loopState->indexTypeRef);
        const MicroOpBits opBits    = CodeGenTypeHelpers::conditionBits(indexType, codeGen.ctx());
        MicroBuilder&     builder   = codeGen.builder();
        builder.setCurrentDebugSourceCodeRef(codeGen.node(codeGen.curNodeRef()).codeRef());
        builder.setCurrentDebugNoStep(false);

        builder.placeLabel(loopState->continueLabel);
        if (loopState->reverse)
        {
            builder.emitCmpRegReg(loopState->indexReg, loopState->boundReg, opBits);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, loopState->doneLabel);
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Subtract, opBits);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        }
        else
        {
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, opBits);
            builder.emitCmpRegReg(loopState->indexReg, loopState->boundReg, opBits);
            builder.emitJumpToLabel(loopState->inclusive ? loopLessEqualCond(loopState->unsignedCmp) : loopLessCond(loopState->unsignedCmp),
                                    MicroOpBits::B32,
                                    loopState->loopLabel);
        }

        codeGen.popFrame();
        return Result::Continue;
    }

    return Result::Continue;
}

Result AstForStmt::codeGenPostNode(CodeGen& codeGen)
{
    const ForStmtCodeGenPayload* loopState = forStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->doneLabel);
    eraseForStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstForeachStmt::codeGenPreNode(CodeGen& codeGen) const
{
    ForeachStmtCodeGenPayload loopState;
    const SemaNodeView        symbolsView = codeGen.viewSymbolList(codeGen.curNodeRef());
    const auto                symbols     = symbolsView.symList();
    SWC_ASSERT(symbols.size() >= 2);
    if (symbols.size() >= 2)
    {
        const size_t stateIndex    = symbols.size() - 2;
        const size_t spillIndex    = symbols.size() - 1;
        loopState.aliasSymbolCount = static_cast<uint32_t>(std::min<size_t>(2, stateIndex));
        loopState.stateSym         = &symbols[stateIndex]->cast<SymbolVariable>();
        loopState.sourceSpillSym   = &symbols[spillIndex]->cast<SymbolVariable>();
    }

    loopState.loopLabel     = codeGen.builder().createLabel();
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    loopState.reverse       = modifierFlags.has(AstModifierFlagsE::Reverse);
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
    return Result::Continue;
}

Result AstForeachStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef  = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        emitForeachInit(codeGen, *this, *loopState);
        codeGen.builder().placeLabel(loopState->loopLabel);
        emitForeachLoadLoopState(codeGen, *loopState);
        codeGen.builder().emitCmpRegImm(loopState->countReg, ApInt(0, 64), MicroOpBits::B64);
        codeGen.builder().emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, loopState->doneLabel);
        if (loopState->reverse)
        {
            codeGen.builder().emitLoadRegReg(loopState->indexReg, loopState->countReg, MicroOpBits::B64);
            codeGen.builder().emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        }
        emitForeachBindSymbols(codeGen, *this, *loopState);
        return Result::Continue;
    }

    if (childRef == whereRef)
    {
        const CodeGenNodePayload& wherePayload = codeGen.payload(whereRef);
        const SemaNodeView        whereView    = codeGen.viewType(whereRef);
        emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), loopState->continueLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        codeGen.builder().setCurrentDebugSourceCodeRef(codeGen.node(codeGen.curNodeRef()).codeRef());
        codeGen.builder().setCurrentDebugNoStep(false);
        codeGen.builder().placeLabel(loopState->continueLabel);
        emitForeachLoadLoopState(codeGen, *loopState);
        if (!loopState->reverse)
            codeGen.builder().emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        codeGen.builder().emitOpBinaryRegImm(loopState->countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        emitForeachStoreLoopState(codeGen, *loopState);
        codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        codeGen.popFrame();
        return Result::Continue;
    }

    return Result::Continue;
}

Result AstForeachStmt::codeGenPostNode(CodeGen& codeGen)
{
    const ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->doneLabel);
    eraseForeachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstWhileStmt::codeGenPreNode(CodeGen& codeGen)
{
    LoopStmtCodeGenPayload loopState;
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    setLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstWhileStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef bodyRef = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        codeGen.builder().placeLabel(loopState->continueLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        CodeGenFrame frame = codeGen.frame();
        frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
        frame.setCurrentLoopContinueLabel(loopState->continueLabel);
        frame.setCurrentLoopBreakLabel(loopState->doneLabel);
        codeGen.pushFrame(frame);
    }

    return Result::Continue;
}

Result AstWhileStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef bodyRef = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        emitConditionFalseJump(codeGen, exprPayload, exprView.typeRef(), loopState->doneLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        const ScopedDebugNoStep noStep(codeGen.builder(), true);
        codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->continueLabel);
        codeGen.popFrame();
    }

    return Result::Continue;
}

Result AstWhileStmt::codeGenPostNode(CodeGen& codeGen)
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->doneLabel);
    eraseLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPreNode(CodeGen& codeGen)
{
    LoopStmtCodeGenPayload loopState;
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    setLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->continueLabel);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->continueLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const ScopedDebugNoStep noStep(codeGen.builder(), true);
    codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->continueLabel);
    codeGen.popFrame();
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPostNode(CodeGen& codeGen)
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->doneLabel);
    eraseLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstContinueStmt::codeGenPostNode(CodeGen& codeGen)
{
    if (codeGen.frame().currentBreakableKind() != CodeGenFrame::BreakContextKind::Loop)
        return Result::Continue;

    const AstNodeRef loopRef = codeGen.frame().currentBreakContext().nodeRef;
    if (loopRef.isValid())
    {
        const AstNode& loopNode = codeGen.node(loopRef);
        if (loopNode.is(AstNodeId::ForStmt))
        {
            ForStmtCodeGenPayload* loopState = forStmtCodeGenPayload(codeGen, loopRef);
            SWC_ASSERT(loopState != nullptr);
            loopState->hasContinueJump = true;
        }
    }

    const MicroLabelRef continueLabel = codeGen.frame().currentLoopContinueLabel();
    if (continueLabel == MicroLabelRef::invalid())
        return Result::Continue;

    codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, continueLabel);
    return Result::Continue;
}

SWC_END_NAMESPACE();
