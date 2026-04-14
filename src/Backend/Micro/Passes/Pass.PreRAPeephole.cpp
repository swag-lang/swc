#include "pch.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA peephole optimization on virtual registers.
//
// This pass is intentionally tiny and local:
// - no SSA queries;
// - no liveness reasoning;
// - only looks at an anchor instruction and its exact next instruction.
//
// It complements the heavier SSA-based InstructionCombine pass by handling
// the most obvious adjacent producer/consumer pairs early in the pipeline.

SWC_BEGIN_NAMESPACE();

namespace
{
    using namespace PreRaPeephole;

    PatternRegistry buildRegistry()
    {
        PatternRegistry r;
        r.add(MicroInstrOpcode::LoadRegImm, tryForwardLoadRegImm);
        r.add(MicroInstrOpcode::LoadRegReg, tryForwardCopy);
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

Result MicroPreRAPeepholePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/PreRAPeephole");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    Context ctx;
    ctx.storage  = context.instructions;
    ctx.operands = context.operands;

    runPerInstructionPatterns(ctx);

    if (ctx.actions.empty())
        return Result::Continue;

    for (const Action& action : ctx.actions)
        applyAction(ctx, action);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
