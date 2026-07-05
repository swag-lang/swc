#pragma once
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Sanitizer/SanitizerState.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;
struct MicroInstr;
struct MicroInstrDef;
struct MicroInstrOperand;
enum class MicroCond : uint8_t;
enum class DiagnosticId;
class SanitizerCheck;
class Symbol;
class TaskContext;

// The sanitizer engine: a path-sensitive "must-be-zero" abstract-interpretation
// data-flow over the Micro control-flow graph, shared by all checks.
//
// A monotone forward analysis: each program point holds the state that is true on
// *every* path reaching it (join = keep only what all predecessors agree on;
// disagreement widens to Unknown). This is cheap (linear, no path explosion) and
// cannot produce a false positive — a value is only "zero" if it is provably zero on
// every path. At a zero-test branch each edge narrows the tested slot (so
// `if x != 0 { ... }` and `if p != null { ... }` are handled) and infeasible edges are
// pruned; branches it cannot model drop all provable-zero values, staying sound.
//
// `run` computes the fixpoint, then applies each check to every reachable instruction
// against its converged incoming state — reporting during the fixpoint would flag a
// transient pre-join state that a later merge widens back to Unknown.
class Sanitizer
{
public:
    explicit Sanitizer(MicroPassContext& context);

    // Runs the data-flow, then every check. Returns true if any check reported.
    bool run(std::span<SanitizerCheck* const> checks);

    // Queries usable by checks against a converged state.
    SanitizerValue          getReg(const SanitizerState& state, MicroReg reg) const;
    bool                    resolveStackSlot(const SanitizerState& state, MicroReg base, uint64_t offset, int64_t& outSlot) const;
    TaskContext&            ctx() const;
    const MicroPassContext& passContext() const { return context_; }

    // The function called by the current instruction, when the check is invoked on a
    // call instruction (resolved from the builder's relocations). Null otherwise.
    const Symbol* currentCallTarget() const { return currentCallTarget_; }

    // Reports a diagnostic at an instruction's source location (deduplicated). Marks the
    // run as having found something so the pass can abort codegen.
    void report(const MicroInstr& inst, DiagnosticId id);

private:
    // Register / slot access.
    static const SanitizerRegInfo* findReg(const SanitizerState& state, MicroReg reg);
    static void                    setReg(SanitizerState& state, MicroReg reg, const SanitizerRegInfo& info);
    static void                    setRegValue(SanitizerState& state, MicroReg reg, const SanitizerValue& value);

    // Join + propagation.
    void        propagate(const SanitizerState& edge, uint32_t index, std::vector<uint32_t>& worklist);
    static bool joinInto(SanitizerState& into, const SanitizerState& from);

    // Instruction effects (the transfer function).
    void        applyValueEffects(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const;
    static void invalidateDefs(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops);
    static bool condIsZeroTest(MicroCond cond, bool& outTrueIfZero);

    // Conditional branch handling: guard narrowing + feasibility pruning.
    void        propagateConditionalBranch(const SanitizerState& state, const MicroInstrOperand* ops, const MicroControlFlowGraph::EdgeList& succs, std::vector<uint32_t>& worklist);
    static bool resolveGuardSlot(const SanitizerRegInfo& subject, int64_t& outSlot, bool& outSlotZeroIfSubjectZero);
    void        queueRefined(const SanitizerState& state, uint32_t index, int64_t slot, bool slotIsZero, std::vector<uint32_t>& worklist);
    static void dropZeros(SanitizerState& state);
    static bool isModelledSingleEdge(const MicroInstrDef& def, const MicroControlFlowGraph::EdgeList& succs);

    static constexpr uint32_t K_MAX_INSTRUCTIONS = 20000;
    static constexpr uint64_t K_ITERATION_CAP    = 400000;

    MicroPassContext&            context_;
    MicroReg                     stackBaseReg_;
    const MicroControlFlowGraph* cfg_               = nullptr;
    const Symbol*                currentCallTarget_ = nullptr;
    bool                         reported_          = false;
    std::vector<SanitizerState>  inState_;
    std::vector<char>            reached_;
    std::vector<char>            inWorklist_;
    std::unordered_set<uint64_t> reportedLocations_;
};

SWC_END_NAMESPACE();
