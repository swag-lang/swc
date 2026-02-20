#pragma once
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroBuilder;
class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;

enum class MicroPassKind : uint8_t
{
    // Simplify labels/jumps and remove unreachable regions in the micro CFG.
    ControlFlowSimplification,
    // Combine adjacent arithmetic/logical immediate operations on the same register.
    InstructionCombine,
    // Replace expensive arithmetic patterns with cheaper equivalent forms.
    StrengthReduction,
    // Replace register uses by already-known equivalent sources.
    CopyPropagation,
    // Track/register known constants and rewrite dependent instructions.
    ConstantPropagation,
    // Remove side-effect-free instructions whose results are not used.
    DeadCodeElimination,
    // Fold conditional branches when compare inputs are compile-time constants.
    BranchFolding,
    // Forward nearby stores into following loads when safe.
    LoadStoreForwarding,
    // Map virtual registers to concrete machine registers and insert spill code.
    RegisterAllocation,
    // Save/restore ABI persistent registers used by the function body.
    PrologEpilog,
    // Rewrite micro instructions so every instruction is encoder-conformant.
    Legalize,
    // Last-minute cleanup after register allocation and legalization.
    Peephole,
    // Encode legalized instructions to machine code and patch jumps/relocations.
    Emit,
};

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
    uint32_t optimizationIterationLimit = 0;
};

class MicroPass
{
public:
    virtual ~MicroPass()                                      = default;
    virtual MicroPassKind kind() const                        = 0;
    virtual bool          run(MicroPassContext& context) = 0;
};

class MicroPassManager
{
public:
    // Legacy API: append to mandatory pipeline stage.
    void add(MicroPass& pass);
    void addMandatory(MicroPass& pass);
    void addPreOptimization(MicroPass& pass);
    void addPostOptimization(MicroPass& pass);
    void addFinal(MicroPass& pass);
    void run(MicroPassContext& context) const;

private:
    std::vector<MicroPass*> preOptimizationPasses_;
    std::vector<MicroPass*> mandatoryPasses_;
    std::vector<MicroPass*> postOptimizationPasses_;
    std::vector<MicroPass*> finalPasses_;
};

SWC_END_NAMESPACE();
