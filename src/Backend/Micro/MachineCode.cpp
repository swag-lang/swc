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
    struct MicroOptimizationPasses
    {
        MicroControlFlowSimplificationPass* cfgSimplifyPass         = nullptr;
        MicroInstructionCombinePass*        instructionCombinePass  = nullptr;
        MicroStrengthReductionPass*         strengthReductionPass   = nullptr;
        MicroCopyPropagationPass*           copyPropagationPass     = nullptr;
        MicroConstantPropagationPass*       constantPropagationPass = nullptr;
        MicroDeadCodeEliminationPass*       deadCodePass            = nullptr;
        MicroBranchFoldingPass*             branchFoldingPass       = nullptr;
        MicroLoadStoreForwardingPass*       loadStoreForwardPass    = nullptr;
        MicroPeepholePass*                  peepholePass            = nullptr;
    };

    void registerMandatoryPasses(MicroPassManager& passManager, MicroRegisterAllocationPass& regAllocPass, MicroLegalizePass& legalizePass)
    {
        passManager.addMandatory(regAllocPass);
        passManager.addMandatory(legalizePass);
    }

    void registerFinalPasses(MicroPassManager& passManager, const Runtime::BuildCfgBackend& backendCfg, MicroPrologEpilogPass& prologEpilogPass, MicroLegalizePass& legalizePass, MicroPeepholePass& peepholePass, MicroDeadCodeEliminationPass& deadCodePass, MicroEmitPass& emitPass)
    {
        passManager.addFinal(prologEpilogPass);
        passManager.addFinal(legalizePass);
        if (backendCfg.optimize)
        {
            passManager.addFinal(peepholePass);
            passManager.addFinal(deadCodePass);
        }
        passManager.addFinal(emitPass);
    }

    void registerOptimizationPassesOff(MicroPassManager&, const MicroOptimizationPasses&)
    {
    }

    void registerOptimizationPassesOn(MicroPassManager& passManager, const MicroOptimizationPasses& passes)
    {
        passManager.addPreOptimization(*SWC_NOT_NULL(passes.strengthReductionPass));
        passManager.addPreOptimization(*SWC_NOT_NULL(passes.instructionCombinePass));
        passManager.addPreOptimization(*SWC_NOT_NULL(passes.copyPropagationPass));
        passManager.addPreOptimization(*SWC_NOT_NULL(passes.constantPropagationPass));
        passManager.addPreOptimization(*SWC_NOT_NULL(passes.loadStoreForwardPass));
        passManager.addPreOptimization(*SWC_NOT_NULL(passes.branchFoldingPass));
        passManager.addPreOptimization(*SWC_NOT_NULL(passes.cfgSimplifyPass));
        passManager.addPostOptimization(*SWC_NOT_NULL(passes.branchFoldingPass));
        passManager.addPostOptimization(*SWC_NOT_NULL(passes.cfgSimplifyPass));
        passManager.addPostOptimization(*SWC_NOT_NULL(passes.constantPropagationPass));
        passManager.addPostOptimization(*SWC_NOT_NULL(passes.deadCodePass));
        passManager.addPostOptimization(*SWC_NOT_NULL(passes.peepholePass));
        passManager.addPostOptimization(*SWC_NOT_NULL(passes.cfgSimplifyPass));
    }

    void registerOptimizationPasses(MicroPassManager& passManager, const Runtime::BuildCfgBackend& backendCfg, const MicroOptimizationPasses& passes)
    {
        if (!backendCfg.optimize)
            registerOptimizationPassesOff(passManager, passes);
        else
            registerOptimizationPassesOn(passManager, passes);
    }
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
#endif

    MicroOptimizationPasses optimizationPasses;
    optimizationPasses.cfgSimplifyPass         = &cfgSimplifyPass;
    optimizationPasses.instructionCombinePass  = &instructionCombinePass;
    optimizationPasses.strengthReductionPass   = &strengthReductionPass;
    optimizationPasses.copyPropagationPass     = &copyPropagationPass;
    optimizationPasses.constantPropagationPass = &constantPropagationPass;
    optimizationPasses.deadCodePass            = &deadCodePass;
    optimizationPasses.branchFoldingPass       = &branchFoldingPass;
    optimizationPasses.loadStoreForwardPass    = &loadStoreForwardPass;
    optimizationPasses.peepholePass            = &peepholePass;

    MicroPassManager passManager;
    registerOptimizationPasses(passManager, builder.backendBuildCfg(), optimizationPasses);
    registerMandatoryPasses(passManager, regAllocPass, legalizePass);
    registerFinalPasses(passManager, builder.backendBuildCfg(), prologEpilogPass, legalizePass, peepholePass, deadCodePass, emitPass);

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
    codeRelocations = builder.codeRelocations();
    return Result::Continue;
}

SWC_END_NAMESPACE();
