#pragma once
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroPrinter.h"
#include "Backend/Micro/MicroStorage.h"
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

struct MicroPassContext
{
    MicroPassContext() = default;

    // Selected call convention drives register classes, stack alignment, and saved regs.
    Encoder*              encoder                = nullptr;
    TaskContext*          taskContext            = nullptr;
    MicroBuilder*         builder                = nullptr;
    MicroStorage*         instructions           = nullptr;
    MicroOperandStorage*  operands               = nullptr;
    std::span<const Utf8> passPrintOptions       = {};
    CallConvKind          callConvKind           = CallConvKind::Host;
    bool                  preservePersistentRegs = false;
    // Optional fixed-point iteration cap for optimization loops (0 = use level default).
    uint32_t optimizationIterationLimit  = 0;
    size_t   printInstrCountBeforeAll    = 0;
    bool     hasPrintInstrCountBeforeAll = false;
#if SWC_HAS_STATS
    size_t optimizationInstrRemoved = 0;
    size_t optimizationInstrAdded   = 0;
#endif
    bool passChanged = false;
};

class MicroPass
{
public:
    virtual ~MicroPass()                   = default;
    virtual std::string_view  name() const = 0;
    virtual MicroRegPrintMode printModeBefore() const { return MicroRegPrintMode::Concrete; }
    virtual MicroRegPrintMode printModeAfter() const { return MicroRegPrintMode::Concrete; }
    virtual Result            run(MicroPassContext& context) = 0;
};

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
