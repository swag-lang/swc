#pragma once

SWC_BEGIN_NAMESPACE();

class Encoder;
struct MicroInstr;
struct MicroInstrOperand;
template<typename T>
class TypedStore;

struct MicroPassContext
{
    Encoder*                       encoder      = nullptr;
    TypedStore<MicroInstr>*        instructions = nullptr;
    TypedStore<MicroInstrOperand>* operands     = nullptr;
};

class MicroPass
{
public:
    virtual ~MicroPass()                                    = default;
    virtual const char* name() const                        = 0;
    virtual void        run(MicroPassContext& context)      = 0;
};

class MicroPassManager
{
public:
    void add(MicroPass& pass);
    void run(MicroPassContext& context);

private:
    std::vector<MicroPass*> passes_;
};

SWC_END_NAMESPACE();
