#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA instruction combiner on virtual registers.
//
// Architecture
// ------------
// Each combine rule is a self-contained function (one per file, see
// Pass.InstructionCombine.*.cpp) that receives a Context and an anchor
// instruction, decides whether it applies, and emits typed Actions
// describing the rewrite. Patterns are registered against the opcode(s)
// they anchor on, so the scan loop does one table lookup per instruction
// rather than a cascading if/else.
//
// SSA queries run on the un-mutated IR throughout the scan; actions are
// applied as a batch once every pattern has had a chance. The pass manager
// invalidates the shared SSA state afterwards and the next optimization
// iteration rebuilds it.

SWC_BEGIN_NAMESPACE();

namespace
{
    using namespace InstructionCombine;

    PatternRegistry buildRegistry()
    {
        PatternRegistry r;
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryOpBinaryRegImm);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryOpBinaryRegReg);
        r.add(MicroInstrOpcode::LoadRegMem, tryMemoryFoldTriple);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldMemoryAddressing);
        r.add(MicroInstrOpcode::LoadMemReg, tryFoldMemoryAddressing);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryNarrowExtend);
        r.add(MicroInstrOpcode::LoadSignedExtRegReg, tryNarrowExtend);
        return r;
    }

    const PatternRegistry& registry()
    {
        static const PatternRegistry r = buildRegistry();
        return r;
    }

    void runPerInstructionPatterns(Context& ctx)
    {
        const PatternRegistry& reg   = registry();
        const auto             view  = ctx.storage->view();
        const auto             endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it)
        {
            for (const PatternFn fn : reg.patternsFor(it->op))
            {
                if (fn(ctx, it.current, *it))
                    break;
            }
        }
    }
}

Result MicroInstructionCombinePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/InstCombine");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroSsaState        localSsa;
    const MicroSsaState* ssa = MicroSsaState::ensureFor(context, localSsa);

    Context ctx;
    ctx.storage  = context.instructions;
    ctx.operands = context.operands;
    ctx.ssa      = ssa;

    runPerInstructionPatterns(ctx);

    // Whole-IR scans with per-position state don't fit the anchor-per-instruction
    // dispatch. They emit into the same action queue so claim tracking works
    // uniformly with per-instruction patterns.
    runStoreToLoadForwarding(ctx);

    if (ctx.actions.empty())
        return Result::Continue;

    for (const Action& action : ctx.actions)
        applyAction(ctx, action);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
