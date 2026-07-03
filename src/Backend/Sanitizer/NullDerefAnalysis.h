#pragma once
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Sanitizer/SanitizerState.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;
struct MicroInstr;
struct MicroInstrDef;
struct MicroInstrOperand;
enum class MicroCond : uint8_t;

// Path-sensitive "must-be-null" data-flow analysis for null-pointer dereferences.
//
// A monotone forward analysis over the control-flow graph: each program point holds
// the state that is true on *all* paths reaching it (join = keep only values every
// predecessor agrees on; disagreement widens to Unknown). This is cheap (linear, no
// path explosion) and cannot report a false positive — a slot is only "null" if it is
// provably null on every path. At a null-test branch each edge narrows the tested
// pointer/slot (so `if p != null { p.x }` is safe and `if p == null { p.x }` is
// flagged) and infeasible edges are pruned. Branches it cannot model drop all
// provable-null values, staying sound.
//
// It reports only on the converged states — reporting during the fixpoint would flag a
// transient pre-join state that a later merge widens back to Unknown.
class NullDerefAnalysis
{
public:
    explicit NullDerefAnalysis(MicroPassContext& context);

    // Runs the analysis over the current function. Returns true if at least one provable
    // null dereference was reported.
    bool run();

private:
    // Register / slot access.
    SanitizerValue                 getReg(const SanitizerState& state, MicroReg reg) const;
    static const SanitizerRegInfo* findReg(const SanitizerState& state, MicroReg reg);
    static void                    setReg(SanitizerState& state, MicroReg reg, const SanitizerRegInfo& info);
    static void                    setRegValue(SanitizerState& state, MicroReg reg, const SanitizerValue& value);
    bool                           resolveStackSlot(const SanitizerState& state, MicroReg base, uint64_t offset, int64_t& outSlot) const;

    // Join + propagation.
    void        propagate(const SanitizerState& edge, uint32_t index, std::vector<uint32_t>& worklist);
    static bool joinInto(SanitizerState& into, const SanitizerState& from);

    // Instruction effects.
    void        applyValueEffects(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const;
    static void invalidateDefs(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops);
    static bool condIsZeroTest(MicroCond cond, bool& outTrueIfZero);

    // Conditional branch handling: guard narrowing + feasibility pruning.
    void        propagateConditionalBranch(const SanitizerState& state, const MicroInstrOperand* ops, const MicroControlFlowGraph::EdgeList& succs, std::vector<uint32_t>& worklist);
    static bool resolveGuardSlot(const SanitizerRegInfo& subject, int64_t& outSlot, bool& outSlotNullIfSubjectZero);
    void        queueRefined(const SanitizerState& state, uint32_t index, int64_t slot, bool slotIsNull, std::vector<uint32_t>& worklist);
    static void dropNulls(SanitizerState& state);
    static bool isModelledSingleEdge(const MicroInstrDef& def, const MicroControlFlowGraph::EdgeList& succs);

    // Dereference check + reporting.
    void checkDereference(const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops);
    void reportNullDeref(const MicroInstr& inst);

    static constexpr uint32_t K_MAX_INSTRUCTIONS = 20000;
    static constexpr uint64_t K_ITERATION_CAP    = 400000;

    MicroPassContext&            context_;
    MicroReg                     stackBaseReg_;
    const MicroControlFlowGraph* cfg_      = nullptr;
    bool                         reported_ = false;
    std::vector<SanitizerState>  inState_;
    std::vector<char>            reached_;
    std::vector<char>            inWorklist_;
    std::unordered_set<uint64_t> reportedLocations_;
};

SWC_END_NAMESPACE();
