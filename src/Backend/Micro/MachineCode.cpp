#include "pch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/MicroBranchFoldingPass.h"
#include "Backend/Micro/Passes/MicroConstantPropagationPass.h"
#include "Backend/Micro/Passes/MicroControlFlowSimplificationPass.h"
#include "Backend/Micro/Passes/MicroCopyPropagationPass.h"
#include "Backend/Micro/Passes/MicroDeadCodeEliminationPass.h"
#include "Backend/Micro/Passes/MicroEmitPass.h"
#include "Backend/Micro/Passes/MicroInstructionCombinePass.h"
#include "Backend/Micro/Passes/MicroLegalizePass.h"
#include "Backend/Micro/Passes/MicroLoadStoreForwardingPass.h"
#include "Backend/Micro/Passes/MicroPeepholePass.h"
#include "Backend/Micro/Passes/MicroPrologEpilogPass.h"
#include "Backend/Micro/Passes/MicroRegisterAllocationPass.h"
#include "Backend/Micro/Passes/MicroStrengthReductionPass.h"
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

    void registerMandatoryPasses(MicroPassManager& passManager, MicroRegisterAllocationPass& regAllocPass, MicroPrologEpilogPass& prologEpilogPass, MicroLegalizePass& legalizePass, MicroEmitPass& emitPass)
    {
        passManager.addMandatory(regAllocPass);
        passManager.addMandatory(prologEpilogPass);
        passManager.addMandatory(legalizePass);
        passManager.addFinal(emitPass);
    }

    void registerOptimizationPassesO0(MicroPassManager&, const MicroOptimizationPasses&)
    {
    }

    void registerOptimizationPassesO1(MicroPassManager& passManager, const MicroOptimizationPasses& passes)
    {
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.strengthReductionPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.instructionCombinePass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.copyPropagationPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.constantPropagationPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.branchFoldingPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.cfgSimplifyPass));
        passManager.addPostOptimization(*SWC_CHECK_NOT_NULL(passes.peepholePass));
    }

    void registerOptimizationPassesO2(MicroPassManager& passManager, const MicroOptimizationPasses& passes)
    {
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.strengthReductionPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.instructionCombinePass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.copyPropagationPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.constantPropagationPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.loadStoreForwardPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.branchFoldingPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.cfgSimplifyPass));
        passManager.addPostOptimization(*SWC_CHECK_NOT_NULL(passes.peepholePass));
        passManager.addPostOptimization(*SWC_CHECK_NOT_NULL(passes.cfgSimplifyPass));
    }

    void registerOptimizationPassesO3(MicroPassManager& passManager, const MicroOptimizationPasses& passes)
    {
        registerOptimizationPassesO2(passManager, passes);
    }

    void registerOptimizationPassesOs(MicroPassManager& passManager, const MicroOptimizationPasses& passes)
    {
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.instructionCombinePass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.copyPropagationPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.constantPropagationPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.branchFoldingPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.cfgSimplifyPass));
        passManager.addPostOptimization(*SWC_CHECK_NOT_NULL(passes.peepholePass));
    }

    void registerOptimizationPassesOz(MicroPassManager& passManager, const MicroOptimizationPasses& passes)
    {
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.copyPropagationPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.constantPropagationPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.branchFoldingPass));
        passManager.addPreOptimization(*SWC_CHECK_NOT_NULL(passes.cfgSimplifyPass));
        passManager.addPostOptimization(*SWC_CHECK_NOT_NULL(passes.peepholePass));
    }

    void registerOptimizationPasses(MicroPassManager& passManager, Runtime::BuildCfgBackendOptim optimizeLevel, const MicroOptimizationPasses& passes)
    {
        switch (optimizeLevel)
        {
            case Runtime::BuildCfgBackendOptim::O0:
                registerOptimizationPassesO0(passManager, passes);
                return;
            case Runtime::BuildCfgBackendOptim::O1:
                registerOptimizationPassesO1(passManager, passes);
                return;
            case Runtime::BuildCfgBackendOptim::O2:
                registerOptimizationPassesO2(passManager, passes);
                return;
            case Runtime::BuildCfgBackendOptim::O3:
                registerOptimizationPassesO3(passManager, passes);
                return;
            case Runtime::BuildCfgBackendOptim::Os:
                registerOptimizationPassesOs(passManager, passes);
                return;
            case Runtime::BuildCfgBackendOptim::Oz:
                registerOptimizationPassesOz(passManager, passes);
                return;
            default:
                SWC_UNREACHABLE();
        }
    }
}

void MachineCode::emit(TaskContext& ctx, MicroBuilder& builder)
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
    registerOptimizationPasses(passManager, builder.backendBuildCfg().optimizeLevel, optimizationPasses);
    registerMandatoryPasses(passManager, regAllocPass, prologEpilogPass, legalizePass, emitPass);

#if SWC_HAS_STATS
    const size_t numMicroInstrNoOptim    = builder.instructions().count();
    const size_t numMicroOperandsNoOptim = builder.operands().count();
    const size_t memMicroStorageNoOptim  = builder.instructions().allocatedBytes() + builder.operands().allocatedBytes();
#endif
    builder.runPasses(passManager, &encoder, passContext);

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
}

SWC_END_NAMESPACE();
