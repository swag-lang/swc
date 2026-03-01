#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroBuilder;
class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;
class MicroControlFlowSimplificationPass;
class MicroInstructionCombinePass;
class MicroStrengthReductionPass;
class MicroCopyPropagationPass;
class MicroConstantPropagationPass;
class MicroDeadCodeEliminationPass;
class MicroBranchFoldingPass;
class MicroLoadStoreForwardingPass;
class MicroPeepholePass;
class MicroRegisterAllocationPass;
class MicroPrologEpilogPass;
class MicroLegalizePass;
class MicroEmitPass;

class MicroPassManager
{
public:
    MicroPassManager();
    ~MicroPassManager();

    MicroPassManager(const MicroPassManager&)            = delete;
    MicroPassManager& operator=(const MicroPassManager&) = delete;
    MicroPassManager(MicroPassManager&&) noexcept;
    MicroPassManager& operator=(MicroPassManager&&) noexcept;

    void clear();
    void configureDefaultPipeline(bool optimize);

    // Legacy API: append to mandatory pipeline stage.
    void   add(MicroPass& pass);
    void   addMandatory(MicroPass& pass);
    void   addPreOptimization(MicroPass& pass);
    void   addPostOptimization(MicroPass& pass);
    void   addFinal(MicroPass& pass);
    Result run(MicroPassContext& context) const;

private:
    std::vector<MicroPass*>                             preOptimizationPasses_;
    std::vector<MicroPass*>                             mandatoryPasses_;
    std::vector<MicroPass*>                             postOptimizationPasses_;
    std::vector<MicroPass*>                             finalPasses_;
    std::unique_ptr<MicroControlFlowSimplificationPass> cfgSimplifyPass_;
    std::unique_ptr<MicroInstructionCombinePass>        instructionCombinePass_;
    std::unique_ptr<MicroStrengthReductionPass>         strengthReductionPass_;
    std::unique_ptr<MicroCopyPropagationPass>           copyPropagationPass_;
    std::unique_ptr<MicroConstantPropagationPass>       constantPropagationPass_;
    std::unique_ptr<MicroDeadCodeEliminationPass>       deadCodePass_;
    std::unique_ptr<MicroBranchFoldingPass>             branchFoldingPass_;
    std::unique_ptr<MicroLoadStoreForwardingPass>       loadStoreForwardPass_;
    std::unique_ptr<MicroPeepholePass>                  peepholePass_;
    std::unique_ptr<MicroRegisterAllocationPass>        regAllocPass_;
    std::unique_ptr<MicroPrologEpilogPass>              prologEpilogPass_;
    std::unique_ptr<MicroLegalizePass>                  legalizePass_;
    std::unique_ptr<MicroEmitPass>                      emitPass_;
};

SWC_END_NAMESPACE();
