#pragma once
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrStorage.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
struct MicroInstr;
struct MicroInstrOperand;

struct MicroPassContext
{
    MicroPassContext() = default;

    Encoder*             encoder                = nullptr;
    MicroInstrStorage*   instructions           = nullptr;
    MicroOperandStorage* operands               = nullptr;
    CallConvKind         callConvKind           = CallConvKind::Host;
    bool                 preservePersistentRegs = false;
};

class MicroPass
{
public:
    virtual ~MicroPass()                        = default;
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
