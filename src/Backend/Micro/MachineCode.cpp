#include "pch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/Pass.BranchFolding.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"
#include "Backend/Micro/Passes/Pass.ControlFlowSimplification.h"
#include "Backend/Micro/Passes/Pass.CopyPropagation.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/Passes/Pass.Emit.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/Passes/Pass.Legalize.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"
#include "Backend/Micro/Passes/Pass.PrologEpilog.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void registerMandatoryPasses(MicroPassManager& passManager, MicroRegisterAllocationPass& regAllocPass, MicroLegalizePass& legalizePass)
    {
        passManager.addMandatory(regAllocPass);
        passManager.addMandatory(legalizePass);
        passManager.addMandatory(regAllocPass);
    }

    void registerLateOptimizationFinalPasses(MicroPassManager&                   passManager,
                                             const Runtime::BuildCfgBackend&     backendCfg,
                                             MicroControlFlowSimplificationPass& cfgSimplifyPass,
                                             MicroConstantPropagationPass&       constantPropagationPass,
                                             MicroDeadCodeEliminationPass&       deadCodePass,
                                             MicroBranchFoldingPass&             branchFoldingPass,
                                             MicroLoadStoreForwardingPass&       loadStoreForwardPass,
                                             MicroPeepholePass&                  peepholePass)
    {
        if (!backendCfg.optimize)
            return;

        passManager.addFinal(constantPropagationPass);
        passManager.addFinal(loadStoreForwardPass);
        passManager.addFinal(branchFoldingPass);
        passManager.addFinal(cfgSimplifyPass);
        passManager.addFinal(deadCodePass);
        passManager.addFinal(peepholePass);
        passManager.addFinal(constantPropagationPass);
        passManager.addFinal(branchFoldingPass);
        passManager.addFinal(cfgSimplifyPass);
    }

    void registerFinalPasses(MicroPassManager&                   passManager,
                             const Runtime::BuildCfgBackend&     backendCfg,
                             MicroControlFlowSimplificationPass& cfgSimplifyPass,
                             MicroConstantPropagationPass&       constantPropagationPass,
                             MicroDeadCodeEliminationPass&       deadCodePass,
                             MicroBranchFoldingPass&             branchFoldingPass,
                             MicroLoadStoreForwardingPass&       loadStoreForwardPass,
                             MicroPeepholePass&                  peepholePass,
                             MicroPrologEpilogPass&              prologEpilogPass,
                             MicroRegisterAllocationPass&        regAllocPass,
                             MicroLegalizePass&                  legalizePass,
                             MicroEmitPass&                      emitPass)
    {
        registerLateOptimizationFinalPasses(passManager, backendCfg, cfgSimplifyPass, constantPropagationPass, deadCodePass, branchFoldingPass, loadStoreForwardPass, peepholePass);

        passManager.addFinal(prologEpilogPass);
        passManager.addFinal(legalizePass);
        if (backendCfg.optimize)
        {
            passManager.addFinal(constantPropagationPass);
            passManager.addFinal(loadStoreForwardPass);
            passManager.addFinal(branchFoldingPass);
            passManager.addFinal(cfgSimplifyPass);
            passManager.addFinal(peepholePass);
            passManager.addFinal(deadCodePass);
            passManager.addFinal(constantPropagationPass);
            passManager.addFinal(branchFoldingPass);
            passManager.addFinal(cfgSimplifyPass);
        }
        passManager.addFinal(regAllocPass);
        if (backendCfg.optimize)
        {
            passManager.addFinal(constantPropagationPass);
            passManager.addFinal(loadStoreForwardPass);
            passManager.addFinal(peepholePass);
            passManager.addFinal(deadCodePass);
            passManager.addFinal(constantPropagationPass);
            passManager.addFinal(branchFoldingPass);
            passManager.addFinal(cfgSimplifyPass);
        }
        passManager.addFinal(emitPass);
    }

    void registerOptimizationPasses(MicroPassManager&                   passManager,
                                    const Runtime::BuildCfgBackend&     backendCfg,
                                    MicroControlFlowSimplificationPass& cfgSimplifyPass,
                                    MicroInstructionCombinePass&        instructionCombinePass,
                                    MicroStrengthReductionPass&         strengthReductionPass,
                                    MicroCopyPropagationPass&           copyPropagationPass,
                                    MicroConstantPropagationPass&       constantPropagationPass,
                                    MicroDeadCodeEliminationPass&       deadCodePass,
                                    MicroBranchFoldingPass&             branchFoldingPass,
                                    MicroLoadStoreForwardingPass&       loadStoreForwardPass,
                                    MicroPeepholePass&                  peepholePass)
    {
        if (!backendCfg.optimize)
            return;

        passManager.addPreOptimization(strengthReductionPass);
        passManager.addPreOptimization(instructionCombinePass);
        passManager.addPreOptimization(copyPropagationPass);
        passManager.addPreOptimization(constantPropagationPass);
        passManager.addPreOptimization(loadStoreForwardPass);
        passManager.addPreOptimization(branchFoldingPass);
        passManager.addPreOptimization(cfgSimplifyPass);
        passManager.addPostOptimization(branchFoldingPass);
        passManager.addPostOptimization(cfgSimplifyPass);
        passManager.addPostOptimization(constantPropagationPass);
        passManager.addPostOptimization(deadCodePass);
        passManager.addPostOptimization(peepholePass);
        passManager.addPostOptimization(cfgSimplifyPass);
    }
}

bool MachineCode::resolveSourceCodeRefAtOffset(SourceCodeRef& outSourceCodeRef, const uint32_t codeOffset) const
{
    const DebugSourceRange* bestBefore = nullptr;
    for (const DebugSourceRange& range : debugSourceRanges)
    {
        if (!range.sourceCodeRef.isValid())
            continue;

        if (codeOffset >= range.codeStartOffset && codeOffset < range.codeEndOffset)
        {
            outSourceCodeRef = range.sourceCodeRef;
            return true;
        }

        if (range.codeStartOffset > codeOffset)
            continue;

        if (!bestBefore || bestBefore->codeStartOffset < range.codeStartOffset)
            bestBefore = &range;
    }

    if (bestBefore)
    {
        outSourceCodeRef = bestBefore->sourceCodeRef;
        return true;
    }

    outSourceCodeRef = SourceCodeRef::invalid();
    return false;
}

Result MachineCode::emit(TaskContext& ctx, MicroBuilder& builder)
{
    MicroControlFlowSimplificationPass cfgSimplifyPass;
    MicroInstructionCombinePass        instructionCombinePass;
    MicroStrengthReductionPass         strengthReductionPass;
    MicroCopyPropagationPass           copyPropagationPass;
    MicroConstantPropagationPass       constantPropagationPass;
    MicroDeadCodeEliminationPass       deadCodePass;
    MicroBranchFoldingPass             branchFoldingPass;
    MicroLoadStoreForwardingPass       loadStoreForwardPass;
    MicroPeepholePass                  peepholePass;
    MicroRegisterAllocationPass        regAllocPass;
    MicroPrologEpilogPass              prologEpilogPass;
    MicroLegalizePass                  legalizePass;
    MicroEmitPass                      emitPass;

    MicroPassContext passContext;
    passContext.callConvKind           = CallConvKind::Host;
    passContext.preservePersistentRegs = true;

#ifdef _M_X64
    X64Encoder encoder(ctx);
    encoder.setBackendBuildCfg(builder.backendBuildCfg());
    encoder.clearDebugSourceRanges();
#endif

    MicroPassManager passManager;
    registerOptimizationPasses(passManager,
                               builder.backendBuildCfg(),
                               cfgSimplifyPass,
                               instructionCombinePass,
                               strengthReductionPass,
                               copyPropagationPass,
                               constantPropagationPass,
                               deadCodePass,
                               branchFoldingPass,
                               loadStoreForwardPass,
                               peepholePass);
    registerMandatoryPasses(passManager, regAllocPass, legalizePass);
    registerFinalPasses(passManager,
                        builder.backendBuildCfg(),
                        cfgSimplifyPass,
                        constantPropagationPass,
                        deadCodePass,
                        branchFoldingPass,
                        loadStoreForwardPass,
                        peepholePass,
                        prologEpilogPass,
                        regAllocPass,
                        legalizePass,
                        emitPass);

#if SWC_HAS_STATS
    const size_t numMicroInstrNoOptim    = builder.instructions().count();
    const size_t numMicroOperandsNoOptim = builder.operands().count();
    const size_t memMicroStorageNoOptim  = builder.instructions().allocatedBytes() + builder.operands().allocatedBytes();
#endif
    SWC_RESULT_VERIFY(builder.runPasses(passManager, &encoder, passContext));

#if SWC_HAS_STATS
    const size_t numMicroInstrFinal    = builder.instructions().count();
    const size_t numMicroOperandsFinal = builder.operands().count();
    const size_t memMicroStorageFinal  = builder.instructions().allocatedBytes() + builder.operands().allocatedBytes();
    Stats::get().numMicroInstrNoOptim.fetch_add(numMicroInstrNoOptim, std::memory_order_relaxed);
    Stats::get().numMicroInstrFinal.fetch_add(numMicroInstrFinal, std::memory_order_relaxed);
    Stats::get().numMicroOperandsNoOptim.fetch_add(numMicroOperandsNoOptim, std::memory_order_relaxed);
    Stats::get().numMicroOperandsFinal.fetch_add(numMicroOperandsFinal, std::memory_order_relaxed);
    Stats::get().numMicroInstrOptimRemoved.fetch_add(passContext.optimizationInstrRemoved, std::memory_order_relaxed);
    Stats::get().numMicroInstrOptimAdded.fetch_add(passContext.optimizationInstrAdded, std::memory_order_relaxed);
    Stats::get().memMicroStorageNoOptim.fetch_add(memMicroStorageNoOptim, std::memory_order_relaxed);
    Stats::get().memMicroStorageFinal.fetch_add(memMicroStorageFinal, std::memory_order_relaxed);
#endif

    const auto codeSize = encoder.size();
    SWC_FORCE_ASSERT(codeSize != 0);

    bytes.resize(codeSize);
    encoder.copyTo(bytes);
    codeRelocations   = builder.codeRelocations();
    debugSourceRanges = encoder.debugSourceRanges();
    return Result::Continue;
}

SWC_END_NAMESPACE();
