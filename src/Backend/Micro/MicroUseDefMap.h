#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

class MicroOperandStorage;
struct MicroPassContext;

// Cached use-def analysis shared across pre-RA optimization passes.
//
// Built once per pass iteration by scanning the instruction stream. Each pass
// can query reaching definitions and uses without rescanning. When a pass
// mutates the IR, it must call invalidate() so the next pass rebuilds.
//
// This map operates on the flat instruction list (no CFG edges). At a control
// flow barrier (label, branch, call, ret), reaching definitions are conservatively
// cleared. This is safe but imprecise — a future CFG-aware version can refine it.
class MicroUseDefMap
{
public:
    // Per-instruction cached data.
    struct InstrInfo
    {
        MicroInstrRef    instRef = MicroInstrRef::invalid();
        MicroInstrUseDef useDef;
    };

    // A reaching definition: the instruction that last defined a register.
    struct ReachingDef
    {
        MicroInstrRef instRef = MicroInstrRef::invalid();
        MicroInstr*   inst    = nullptr;

        bool valid() const { return inst != nullptr; }
    };

    void build(MicroStorage& storage, MicroOperandStorage& operands, const Encoder* encoder);
    static const MicroUseDefMap* ensureFor(const MicroPassContext& context, MicroUseDefMap& localMap);
    void invalidate();
    bool isValid() const { return valid_; }

    // Query the reaching definition for a register at a given instruction.
    // Returns the instruction that last defined 'reg' before 'beforeInstRef'.
    ReachingDef reachingDef(MicroReg reg, MicroInstrRef beforeInstRef) const;

    // Query cached use-def for a specific instruction.
    const MicroInstrUseDef* instrUseDef(MicroInstrRef instRef) const;

    // Query whether a register is used after a given instruction within the same
    // local flow region (up to the next barrier). Useful for dead-def checks.
    bool isRegUsedAfter(MicroReg reg, MicroInstrRef afterInstRef) const;

private:
    struct RegDefEntry
    {
        MicroReg      reg;
        MicroInstrRef instRef = MicroInstrRef::invalid();
    };

    // Per-instruction index (keyed by MicroInstrRef slot index).
    std::vector<InstrInfo> instrInfos_;
    // Order of instructions (for sequential queries).
    std::vector<MicroInstrRef> instrOrder_;
    // Per-instruction: index into instrOrder_.
    std::vector<uint32_t> instrOrderIndex_;
    // Last reaching definition per register at each instruction.
    // Stored as: instrOrder index -> vector of {reg, defining instRef}.
    std::vector<std::vector<RegDefEntry>> reachingDefs_;

    MicroStorage*        storage_  = nullptr;
    MicroOperandStorage* operands_ = nullptr;
    bool                 valid_    = false;
};

SWC_END_NAMESPACE();
