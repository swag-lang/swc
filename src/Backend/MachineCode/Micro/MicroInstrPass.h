#pragma once
#include <vector>

SWC_BEGIN_NAMESPACE();

class Encoder;

class MicroInstrPass
{
public:
    virtual ~MicroInstrPass() = default;
    virtual const char* name() const = 0;
    virtual void        run(Encoder* encoder) = 0;
};

class MicroInstrPassManager
{
public:
    void add(MicroInstrPass& pass);
    void run(Encoder* encoder);

private:
    std::vector<MicroInstrPass*> passes_;
};

SWC_END_NAMESPACE();
