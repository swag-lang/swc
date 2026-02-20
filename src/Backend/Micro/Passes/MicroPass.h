#pragma once
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroPrinter.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroBuilder;
class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;

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
    virtual ~MicroPass()                                 = default;
    virtual std::string_view name() const                = 0;
    virtual MicroRegPrintMode printModeBefore() const    { return MicroRegPrintMode::Concrete; }
    virtual MicroRegPrintMode printModeAfter() const     { return MicroRegPrintMode::Concrete; }
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
