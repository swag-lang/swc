#pragma once
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroBuilder;
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

struct MicroPassContext
{
    MicroPassContext() = default;

    Encoder*              encoder                = nullptr;
    TaskContext*          taskContext            = nullptr;
    MicroBuilder*    builder                = nullptr;
    MicroStorage*    instructions           = nullptr;
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
    void add(MicroPass& pass);
    void run(MicroPassContext& context) const;

private:
    std::vector<MicroPass*> passes_;
};

SWC_END_NAMESPACE();
