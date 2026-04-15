#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"
#include "Support/Memory/MemoryProfile.h"

// Post-RA peephole optimization on physical registers.
//
// Architecture
// ------------
// Mirrors instruction-combine on purpose:
// - rules are small self-contained functions;
// - rules are registered by anchor opcode;
// - scans batch Actions and apply them after the walk finishes.
//
// This keeps the pass cheap today while making it easy to add more post-RA
// cleanup rules later without growing one large if/else cascade.

SWC_BEGIN_NAMESPACE();

namespace
{
    using namespace PostRaPeephole;

    PatternRegistry buildRegistry()
    {
        PatternRegistry r;
        r.add(MicroInstrOpcode::Nop, tryEraseTrivial);
        r.add(MicroInstrOpcode::LoadRegReg, tryEraseTrivial);
        r.add(MicroInstrOpcode::JumpCond, tryEraseTrivial);
        r.add(MicroInstrOpcode::CmpRegReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpRegImm, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpMemReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpMemImm, tryEraseDeadCompare);
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

Result MicroPostRaPeepholePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/PostRAPeephole");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    Context ctx;
    ctx.storage  = context.instructions;
    ctx.operands = context.operands;
    ctx.encoder  = context.encoder;

    runPerInstructionPatterns(ctx);

    if (ctx.actions.empty())
        return Result::Continue;

    for (const Action& action : ctx.actions)
        applyAction(ctx, action);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
