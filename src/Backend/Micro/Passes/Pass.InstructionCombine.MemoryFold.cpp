#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/MicroReg.h"

// Load / modify / store triple folding.
//
//     LoadRegMem   vt, [b+o]
//     OpBinaryRegImm/OpBinaryRegReg vt, ...
//     LoadMemReg   [b+o], vt
//   ->
//     OpBinaryMemImm / OpBinaryMemReg [b+o], ...

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_FOLD_WINDOW = 16;

        struct MiddleInfo
        {
            MicroInstrRef     ref;
            const MicroInstr* inst = nullptr;
        };

        struct TripleInfo
        {
            bool        middleIsRegImm = false;
            bool        middleIsRegReg = false;
            MicroOp     microOp        = MicroOp::Add;
            MicroOpBits opBits         = MicroOpBits::Zero;
            uint64_t    opImm          = 0;
            MicroReg    rhsReg         = MicroReg::invalid();
        };

        bool extractMiddleOperands(TripleInfo&              out,
                                   const MicroInstr&        mid,
                                   const MicroInstrOperand* opOps)
        {
            if (!opOps)
                return false;

            out.middleIsRegImm = mid.op == MicroInstrOpcode::OpBinaryRegImm;
            out.middleIsRegReg = mid.op == MicroInstrOpcode::OpBinaryRegReg;
            if (!out.middleIsRegImm && !out.middleIsRegReg)
                return false;

            out.opBits  = out.middleIsRegImm ? opOps[1].opBits : opOps[2].opBits;
            out.microOp = out.middleIsRegImm ? opOps[2].microOp : opOps[3].microOp;
            out.opImm   = out.middleIsRegImm ? opOps[3].valueU64 : 0;
            out.rhsReg  = out.middleIsRegReg ? opOps[1].reg : MicroReg::invalid();
            return true;
        }

        bool storeMatches(const MicroInstr&        store,
                          const MicroInstrOperand* storeOps,
                          MicroReg                 base,
                          MicroReg                 vt,
                          MicroOpBits              loadBits,
                          uint64_t                 loadOff)
        {
            if (store.op != MicroInstrOpcode::LoadMemReg || !storeOps)
                return false;
            return storeOps[0].reg == base &&
                   storeOps[1].reg == vt &&
                   storeOps[2].opBits == loadBits &&
                   storeOps[3].valueU64 == loadOff;
        }

        void emitFoldedTriple(Context&      ctx,
                              MicroInstrRef loadRef,
                              MicroInstrRef midRef,
                              MicroInstrRef storeRef,
                              MicroReg      base,
                              uint64_t      loadOff,
                              TripleInfo const& tri)
        {
            MicroInstrOperand newOps[5];
            if (tri.middleIsRegReg)
            {
                // OpBinaryMemReg: [memReg, reg, opBits, microOp, memOffset].
                newOps[0].reg      = base;
                newOps[1].reg      = tri.rhsReg;
                newOps[2].opBits   = tri.opBits;
                newOps[3].microOp  = tri.microOp;
                newOps[4].valueU64 = loadOff;
                ctx.emitRewrite(midRef, MicroInstrOpcode::OpBinaryMemReg, newOps, /*allocNewBlock=*/true);
            }
            else
            {
                // OpBinaryMemImm: [memReg, opBits, microOp, memOffset, imm].
                newOps[0].reg      = base;
                newOps[1].opBits   = tri.opBits;
                newOps[2].microOp  = tri.microOp;
                newOps[3].valueU64 = loadOff;
                newOps[4].valueU64 = tri.opImm;
                ctx.emitRewrite(midRef, MicroInstrOpcode::OpBinaryMemImm, newOps, /*allocNewBlock=*/true);
            }
            ctx.emitErase(loadRef);
            ctx.emitErase(storeRef);
        }

        bool findAnchorPosition(MicroStorage::Iterator& outIter,
                                MicroStorage&           storage,
                                MicroInstrRef           anchor)
        {
            const auto view  = storage.view();
            const auto endIt = view.end();
            for (auto it = view.begin(); it != endIt; ++it)
            {
                if (it.current == anchor)
                {
                    outIter = it;
                    return true;
                }
            }
            return false;
        }
    }

    bool tryMemoryFoldTriple(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroOpBits loadBits = loadOps[2].opBits;
        const uint64_t    loadOff  = loadOps[3].valueU64;
        if (!vt.isVirtualInt())
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();
        MiddleInfo mid;
        bool       foundMid = false;

        for (uint32_t step = 0; step < K_MAX_FOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;

            // Match the store first: it writes memory, so the generic
            // writesMemory abort below would otherwise reject it.
            if (foundMid)
            {
                const MicroInstrOperand* sOps = w.ops(*ctx.operands);
                if (!storeMatches(w, sOps, base, vt, loadBits, loadOff))
                    return false;

                TripleInfo                     tri;
                const MicroInstrOperand* const opOps = mid.inst->ops(*ctx.operands);
                if (!extractMiddleOperands(tri, *mid.inst, opOps))
                    return false;

                if (tri.opBits != loadBits || !isMemFoldableOp(tri.microOp))
                    return false;
                if (tri.middleIsRegReg && (tri.rhsReg == base || tri.rhsReg == vt))
                    return false;

                if (!valueHasSingleUse(*ctx.ssa, vt, loadRef))
                    return false;
                if (!valueHasSingleUse(*ctx.ssa, vt, mid.ref))
                    return false;

                const MicroInstrRef storeRef = walker.current;
                if (!ctx.claimAll({loadRef, mid.ref, storeRef}))
                    return false;

                emitFoldedTriple(ctx, loadRef, mid.ref, storeRef, base, loadOff, tri);
                return true;
            }

            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef   = ctx.ssa->instrUseDef(walker.current);
            const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);
            const bool  defsBase = useDef && microRegSpanContains(useDef->defs, base);
            const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);

            if (defsBase)
                return false;

            if (usesVt || defsVt)
            {
                if (w.op == MicroInstrOpcode::OpBinaryRegImm ||
                    w.op == MicroInstrOpcode::OpBinaryRegReg)
                {
                    const MicroInstrOperand* wOps = w.ops(*ctx.operands);
                    if (wOps && wOps[0].reg == vt)
                    {
                        mid.ref  = walker.current;
                        mid.inst = &w;
                        foundMid = true;
                        continue;
                    }
                }
                return false;
            }
        }

        return false;
    }
}

SWC_END_NAMESPACE();
