#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Assert.h"

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
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryFoldRedundantMaskBeforeShift);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryDropFloatOrderedGuard);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryOpBinaryRegReg);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldConstBinaryRhs);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryCommuteConstantLhs);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFuseInPlaceUpdate);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryFuseInPlaceUpdate);
        r.add(MicroInstrOpcode::OpBinaryRegMem, tryFuseInPlaceUpdate);
        r.add(MicroInstrOpcode::LoadRegMem, tryMemoryFoldTriple);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldLoadIntoRegOp);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldMemoryAddressing);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldAmcLoadIntoSignExtend);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldAmcLoadIntoZeroExtend);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldAmcLoadIntoCompare);
        r.add(MicroInstrOpcode::LoadZeroExtAmcRegMem, tryFoldZeroExtAmcLoadIntoCompare);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldConstIndexAmc);
        r.add(MicroInstrOpcode::LoadSignedExtAmcRegMem, tryFoldConstIndexAmc);
        r.add(MicroInstrOpcode::LoadZeroExtAmcRegMem, tryFoldConstIndexAmc);
        r.add(MicroInstrOpcode::LoadAddrAmcRegMem, tryFoldConstIndexAmc);
        r.add(MicroInstrOpcode::LoadAmcMemReg, tryFoldConstIndexAmc);
        r.add(MicroInstrOpcode::LoadAmcMemImm, tryFoldConstIndexAmc);
        r.add(MicroInstrOpcode::CmpAmcImm, tryFoldConstIndexAmc);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldLeaConstIntoAmcIndex);
        r.add(MicroInstrOpcode::LoadSignedExtAmcRegMem, tryFoldLeaConstIntoAmcIndex);
        r.add(MicroInstrOpcode::LoadZeroExtAmcRegMem, tryFoldLeaConstIntoAmcIndex);
        r.add(MicroInstrOpcode::LoadAddrAmcRegMem, tryFoldLeaConstIntoAmcIndex);
        r.add(MicroInstrOpcode::LoadAmcMemReg, tryFoldLeaConstIntoAmcIndex);
        r.add(MicroInstrOpcode::LoadAmcMemImm, tryFoldLeaConstIntoAmcIndex);
        r.add(MicroInstrOpcode::CmpAmcImm, tryFoldLeaConstIntoAmcIndex);
        r.add(MicroInstrOpcode::LoadMemReg, tryFoldConstStore);
        r.add(MicroInstrOpcode::LoadMemReg, tryFoldMemoryAddressing);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldGlobalAddressIntoAccess);
        r.add(MicroInstrOpcode::LoadMemReg, tryFoldGlobalAddressIntoAccess);
        r.add(MicroInstrOpcode::CmpRegReg, tryFoldConstCompare);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldConstCopy);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryNarrowExtend);
        r.add(MicroInstrOpcode::LoadSignedExtRegReg, tryNarrowExtend);
        return r;
    }

    const PatternRegistry& registry()
    {
        static const PatternRegistry R = buildRegistry();
        return R;
    }

    void runPerInstructionPatterns(Context& ctx)
    {
        // An instruction that carries a relocation is opaque to the combiner:
        // rewriting it to another opcode would leave the relocation pointing
        // at an encoding whose displacement the emitter no longer binds, and
        // the patch would then overwrite the first bytes of the function.
        // Skipping the anchor here handles rules rewriting their own anchor;
        // claimAll's relocated check handles rules that consume neighboring
        // instructions (a fused load-op-store must not swallow a RIP access).
        const PatternRegistry& reg   = registry();
        const auto             view  = ctx.storage->view();
        const auto             endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it)
        {
            if (!ctx.relocated.empty() && ctx.isRelocated(it.current))
                continue;
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
    ctx.builder  = context.builder;
    if (ctx.builder)
    {
        ctx.relocated.reserve(ctx.builder->codeRelocations().size());
        for (const MicroRelocation& reloc : ctx.builder->codeRelocations())
        {
            if (reloc.instructionRef.isValid())
                ctx.relocated.insert(reloc.instructionRef.get());
        }
    }

    runPerInstructionPatterns(ctx);

    // Whole-IR scans with per-position state don't fit the anchor-per-instruction
    // dispatch. They emit into the same action queue so claim tracking works
    // uniformly with per-instruction patterns.
    runStoreToLoadForwarding(ctx);

    if (ctx.actions.empty())
        return Result::Continue;

    for (const Action& action : ctx.actions)
        MicroPeephole::applyAction(ctx, action);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
