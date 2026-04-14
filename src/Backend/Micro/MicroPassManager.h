#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroBuilder;
class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;

// Structural passes
class MicroStackAdjustNormalizePass;
class MicroLegalizePass;
class MicroRegisterAllocationPass;
class MicroPrologEpilogPass;
class MicroPrologEpilogSanitizePass;
class MicroEmitPass;

// Pre-RA optimization passes (operate on virtual registers)
class MicroConstantFoldingPass;
class MicroCopyEliminationPass;
class MicroInstructionCombinePass;
class MicroStrengthReductionPass;
class MicroDeadCodeEliminationPass;
class MicroBranchSimplifyPass;

// Post-RA optimization passes (operate on physical registers)
class MicroPostRAPeepholePass;
class MicroPostRADeadCodeElimPass;

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
    void addStartPass(MicroPass& pass) { startPasses_.push_back(&pass); }
    void addPreRALoopPass(MicroPass& pass) { preRALoopPasses_.push_back(&pass); }
    void addRALoopPass(MicroPass& pass) { raLoopPasses_.push_back(&pass); }
    void addPostRASetupPass(MicroPass& pass) { postRASetupPasses_.push_back(&pass); }
    void addPostRAOptimPass(MicroPass& pass) { postRAOptimPasses_.push_back(&pass); }
    void addFinalPass(MicroPass& pass) { finalPasses_.push_back(&pass); }

    // Back-compat shim: addLoopPass routes to the RA loop (legalize+regalloc).
    void addLoopPass(MicroPass& pass) { raLoopPasses_.push_back(&pass); }

    Result run(MicroPassContext& context) const;

private:
    std::vector<MicroPass*> startPasses_;
    std::vector<MicroPass*> preRALoopPasses_;
    std::vector<MicroPass*> raLoopPasses_;
    std::vector<MicroPass*> postRASetupPasses_;
    std::vector<MicroPass*> postRAOptimPasses_;
    std::vector<MicroPass*> finalPasses_;

    // Structural passes
    std::unique_ptr<MicroStackAdjustNormalizePass> stackAdjustNormalizePass_;
    std::unique_ptr<MicroLegalizePass>             legalizePass_;
    std::unique_ptr<MicroRegisterAllocationPass>   regAllocPass_;
    std::unique_ptr<MicroPrologEpilogPass>         prologEpilogPass_;
    std::unique_ptr<MicroPrologEpilogSanitizePass> prologEpilogSanitizePass_;
    std::unique_ptr<MicroEmitPass>                 emitPass_;

    // Pre-RA optimization passes
    std::unique_ptr<MicroConstantFoldingPass>     constantFoldingPass_;
    std::unique_ptr<MicroCopyEliminationPass>     copyEliminationPass_;
    std::unique_ptr<MicroInstructionCombinePass>  instructionCombinePass_;
    std::unique_ptr<MicroStrengthReductionPass>   strengthReductionPass_;
    std::unique_ptr<MicroDeadCodeEliminationPass> deadCodeEliminationPass_;
    std::unique_ptr<MicroBranchSimplifyPass>      branchSimplifyPass_;

    // Post-RA optimization passes
    std::unique_ptr<MicroPostRAPeepholePass>     postRAPeepholePass_;
    std::unique_ptr<MicroPostRADeadCodeElimPass> postRADeadCodeElimPass_;
};

SWC_END_NAMESPACE();
