#pragma once
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrStorage.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroInstrBuilder;
class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;

enum class MicroPassKind : uint8_t
{
    RegAlloc,
    PersistentRegs,
    Encode,
};

enum class MicroPassPrintFlagsE : uint32_t
{
    Zero                  = 0,
    BeforeRegAlloc        = 1 << 0,
    AfterRegAlloc         = 1 << 1,
    BeforePersistentRegs  = 1 << 2,
    AfterPersistentRegs   = 1 << 3,
    BeforeEncode          = 1 << 4,
    AfterEncode           = 1 << 5,
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
    virtual ~MicroPass()                        = default;
    virtual MicroPassKind kind() const          = 0;
    virtual void run(MicroPassContext& context) = 0;
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
