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
};

class MicroPass
{
public:
    virtual ~MicroPass()                                 = default;
    virtual MicroPassKind kind() const                   = 0;
    virtual void          run(MicroPassContext& context) = 0;
};

class MicroPassManager
{
public:
    // Passes execute in insertion order. Later passes consume the transformed IR.
    void add(MicroPass& pass);
    void run(MicroPassContext& context) const;

private:
    std::vector<MicroPass*> passes_;
};

SWC_END_NAMESPACE();

