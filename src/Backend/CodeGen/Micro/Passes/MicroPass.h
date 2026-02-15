#pragma once
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroInstrStorage.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroInstrBuilder;
class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;

enum class MicroPassKind : uint8_t
{
    RegisterAllocation,
    PrologEpilog,
    Legalize,
    Emit,
};

enum class MicroPassPrintFlagsE : uint32_t
{
    Zero                 = 0,
    BeforeRegisterAllocation       = 1 << 0,
    AfterRegisterAllocation        = 1 << 1,
    BeforePrologEpilog = 1 << 2,
    AfterPrologEpilog  = 1 << 3,
    BeforeLegalize       = 1 << 4,
    AfterLegalize        = 1 << 5,
    BeforeEmit         = 1 << 6,
    AfterEmit          = 1 << 7,
};
using MicroPassPrintFlags = EnumFlags<MicroPassPrintFlagsE>;

struct MicroPassContext
{
    MicroPassContext() = default;

    Encoder*             encoder                = nullptr;
    TaskContext*         taskContext            = nullptr;
    MicroInstrBuilder*   builder                = nullptr;
    MicroInstrStorage*   instructions           = nullptr;
    MicroOperandStorage* operands               = nullptr;
    MicroPassPrintFlags  passPrintFlags         = MicroPassPrintFlagsE::Zero;
    CallConvKind         callConvKind           = CallConvKind::Host;
    bool                 preservePersistentRegs = false;
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
    void add(MicroPass& pass);
    void run(MicroPassContext& context) const;

private:
    std::vector<MicroPass*> passes_;
};

SWC_END_NAMESPACE();
