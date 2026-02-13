#pragma once
#include "Backend/MachineCode/CallConv.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
struct MicroInstr;
struct MicroInstrOperand;
template<typename T>
class PagedStoreTyped;

struct MicroPassContext
{
    Encoder*                            encoder      = nullptr;
    PagedStoreTyped<MicroInstr>*        instructions = nullptr;
    PagedStoreTyped<MicroInstrOperand>* operands     = nullptr;
    CallConvKind                        callConvKind = CallConvKind::Host;
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
