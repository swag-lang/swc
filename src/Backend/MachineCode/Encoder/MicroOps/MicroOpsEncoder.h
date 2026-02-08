#pragma once
#include "Backend/MachineCode/Encoder/MicroOps/MicroInstruction.h"

SWC_BEGIN_NAMESPACE();

class MicroOpsEncoder final
{
public:
    MicroInstruction& addInstruction(MicroOp op, CpuEmitFlags emitFlags = EMIT_ZERO);
    void              encode(CpuEncoder& encoder) const;

    void                                 clear() { instructions_.clear(); }
    void                                 reserve(size_t count) { instructions_.reserve(count); }
    std::vector<MicroInstruction>&       instructions() { return instructions_; }
    const std::vector<MicroInstruction>& instructions() const { return instructions_; }

private:
    std::vector<MicroInstruction> instructions_;
};

SWC_END_NAMESPACE();
