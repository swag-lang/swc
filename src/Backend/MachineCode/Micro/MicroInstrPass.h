#pragma once

SWC_BEGIN_NAMESPACE();

class Encoder;
struct MicroInstr;
struct MicroInstrOperand;
template<typename T>
class TypedStore;

struct MicroInstrPassContext
{
    Encoder*                       encoder      = nullptr;
    TypedStore<MicroInstr>*        instructions = nullptr;
    TypedStore<MicroInstrOperand>* operands     = nullptr;
};

class MicroInstrPass
{
public:
    virtual ~MicroInstrPass()                               = default;
    virtual const char* name() const                        = 0;
    virtual void        run(MicroInstrPassContext& context) = 0;
};

class MicroInstrPassManager
{
public:
    void add(MicroInstrPass& pass);
    void run(MicroInstrPassContext& context);

private:
    std::vector<MicroInstrPass*> passes_;
};

SWC_END_NAMESPACE();
