#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Load into source-operand folding (register destination).
//
//     LoadRegMem     vt,  [b+o]
//     OpBinaryRegReg dst, vt        (dst = dst <op> vt)
//   ->
//     OpBinaryRegMem dst, [b+o]     (dst = dst <op> [b+o])
//
// This is the counterpart to tryMemoryFoldTriple: the triple folds a
// load/modify/store back to the *same* memory cell (memory destination),
// whereas this rule folds a load consumed as the *source* of an op whose
// destination stays in a register. It matches `acc <op>= data[i]` once
// mem2reg has promoted the accumulators to virtual registers, removing the
// copy chain that used to sit between the load and its consumer.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_LOADFOLD_WINDOW = 16;

        // A returned 64-bit boolean is cheapest when its SETcc destination can
        // occupy the integer return register and be cleared before CMP. If the
        // other comparison operand is a one-use load, keeping that temporary
        // out of the return register creates exactly that allocation without
        // changing the 64-bit instruction lengths (REX.W is already present).
        void protectReturnedB64ComparisonSource(Context& ctx, MicroInstrRef cmpRef, MicroReg source)
        {
            if (!ctx.builder || !ctx.passContext || !source.isVirtualInt())
                return;

            const MicroInstrRef setRef = ctx.storage->findNextInstructionRef(cmpRef);
            const MicroInstr*   set    = ctx.storage->ptr(setRef);
            const auto*         setOps = set && set->op == MicroInstrOpcode::SetCondReg ? set->ops(*ctx.operands) : nullptr;
            if (!setOps || !setOps[0].reg.isVirtualInt())
                return;

            MicroInstrRef       extRef = ctx.storage->findNextInstructionRef(setRef);
            const MicroInstr*   ext    = ctx.storage->ptr(extRef);
            const auto*         extOps = ext && ext->op == MicroInstrOpcode::LoadZeroExtRegReg ? ext->ops(*ctx.operands) : nullptr;
            if (extOps && extOps[0].reg == setOps[0].reg && extOps[1].reg == setOps[0].reg &&
                extOps[2].opBits == MicroOpBits::B32 && extOps[3].opBits == MicroOpBits::B8)
            {
                extRef = ctx.storage->findNextInstructionRef(extRef);
                ext    = ctx.storage->ptr(extRef);
                extOps = ext && ext->op == MicroInstrOpcode::LoadZeroExtRegReg ? ext->ops(*ctx.operands) : nullptr;
            }
            if (!extOps || extOps[1].reg != setOps[0].reg || extOps[2].opBits != MicroOpBits::B64 || extOps[3].opBits != MicroOpBits::B8)
                return;

            const CallConv&     conv    = CallConv::get(ctx.passContext->callConvKind);
            const MicroInstrRef copyRef = ctx.storage->findNextInstructionRef(extRef);
            const MicroInstr*   copy    = ctx.storage->ptr(copyRef);
            const auto*         copyOps = copy && copy->op == MicroInstrOpcode::LoadRegReg ? copy->ops(*ctx.operands) : nullptr;
            if (!copyOps || copyOps[0].reg != conv.intReturn || copyOps[1].reg != extOps[0].reg || copyOps[2].opBits != MicroOpBits::B64)
                return;

            const MicroInstrRef retRef = ctx.storage->findNextInstructionRef(copyRef);
            const MicroInstr*   ret    = ctx.storage->ptr(retRef);
            if (!ret || ret->op != MicroInstrOpcode::Ret)
                return;

            ctx.builder->addVirtualRegForbiddenPhysReg(source, conv.intReturn);
        }

        // Ops the encoder can express as `reg <op>= [mem]` (encodeOpBinaryRegMem).
        // Note: shifts are NOT foldable here (no `shl reg, [mem]` form), but
        // MultiplySigned IS (`imul reg, [mem]`), unlike the memory-destination
        // set covered by isMemFoldableOp.
        bool isRegMemFoldableOp(MicroOp op, MicroOpBits opBits)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                case MicroOp::PopCount:
                case MicroOp::LeadingZeroCount:
                case MicroOp::TrailingZeroCount:
                    return opBits != MicroOpBits::B8;
                default:
                    return false;
            }
        }

        bool findAnchorPosition(MicroStorage::Iterator& outIter, MicroStorage& storage, MicroInstrRef anchor)
        {
            if (!storage.ptr(anchor))
                return false;
            outIter = {&storage, anchor};
            return true;
        }
    }

    bool tryFoldLoadIntoRegOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
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

        // The loaded value is consumed by an integer ALU op, so it must live
        // in an integer vreg. base==vt would mean the load clobbers its own
        // address register, which folding would then misuse.
        if (!vt.isVirtualInt() || base == vt)
            return false;
        if (keepAccessScalar(ctx, loadRef, base))
            return false;

        // The load value must flow into exactly one consumer for the move to
        // be sound; otherwise the other uses would lose their definition.
        if (!valueHasSingleUse(*ctx.ssa, vt, loadRef))
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();

        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;

            // The load read is being delayed to the consumer's position, so an
            // aliasing memory write, a call, or any control flow in between
            // could change the value it observes.
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef   = ctx.ssa->instrUseDef(walker.current);
            const bool  defsBase = useDef && microRegSpanContains(useDef->defs, base);
            const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);
            const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);

            // Rewriting [base+off] in place requires base to be unchanged.
            if (defsBase)
                return false;

            if (!usesVt && !defsVt)
                continue;

            // First (and, by single-use, only) reference to vt. It must be an
            // OpBinaryRegReg with vt as the right-hand source and a distinct
            // register destination; anything else is not foldable.
            if (w.op != MicroInstrOpcode::OpBinaryRegReg)
                return false;

            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (!wOps)
                return false;

            const MicroReg    dstReg  = wOps[0].reg;
            const MicroReg    rhsReg  = wOps[1].reg;
            const MicroOpBits opBits  = wOps[2].opBits;
            const MicroOp     microOp = wOps[3].microOp;

            if (rhsReg != vt || dstReg == vt)
                return false;
            if (opBits != loadBits || !isRegMemFoldableOp(microOp, opBits))
                return false;

            const MicroInstrRef opRef = walker.current;
            if (!ctx.claimAll({loadRef, opRef}))
                return false;

            // OpBinaryRegMem: [regDst, memReg, opBits, microOp, memOffset].
            MicroInstrOperand newOps[5];
            newOps[0].reg      = dstReg;
            newOps[1].reg      = base;
            newOps[2].opBits   = opBits;
            newOps[3].microOp  = microOp;
            newOps[4].valueU64 = loadOff;
            ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegMem, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            return true;
        }

        return false;
    }

    // An access whose address is a single-use indexed `lea` reads through
    // that address directly: `add T, [lea]` becomes `add T, [B + I*S + d]`,
    // `mov T, [lea]` an indexed load. A memory operand scales by 1, 2, 4 or
    // 8 only, so the index of a wider element - a 16-byte struct in an
    // array - is shifted first, as LLVM's x86 lowering scales it:
    //
    //     lea A, [B + I*16 + 8] ; add T, [A]    ->    X = I << 4 ; add T, [B + X + 8]
    //
    // Left to the legalizer, that address cost a multiply and two adds.
    bool tryFoldIndexedAddressIntoAccess(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;
        const bool               isLoad = inst.op == MicroInstrOpcode::LoadRegMem;
        const MicroInstrOperand* ops    = inst.ops(*ctx.operands);
        if (!ops || (!isLoad && inst.op != MicroInstrOpcode::OpBinaryRegMem))
            return false;

        const MicroReg    dst      = ops[0].reg;
        const MicroReg    address  = ops[1].reg;
        const MicroOpBits bits     = ops[2].opBits;
        const uint64_t    accessAt = isLoad ? ops[3].valueU64 : ops[4].valueU64;
        if (!address.isVirtualInt() || dst == address || (bits != MicroOpBits::B32 && bits != MicroOpBits::B64))
            return false;
        if (!isLoad)
        {
            switch (ops[3].microOp)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                    if (!dst.isVirtualInt())
                        return false;
                    break;
                case MicroOp::FloatAdd:
                case MicroOp::FloatSubtract:
                case MicroOp::FloatMultiply:
                case MicroOp::FloatDivide:
                    if (!dst.isVirtualFloat())
                        return false;
                    break;
                default:
                    return false;
            }
        }
        else if (!dst.isVirtual())
            return false;

        const auto lea = ctx.ssa->reachingDef(address, ref);
        if (!lea.valid() || lea.isPhi || !lea.inst || lea.inst->op != MicroInstrOpcode::LoadAddrAmcRegMem || ctx.isClaimed(lea.instRef) ||
            !valueHasSingleUse(*ctx.ssa, address, lea.instRef))
            return false;
        const MicroInstrOperand* leaOps = lea.inst->ops(*ctx.operands);
        if (!leaOps || leaOps[0].reg != address || leaOps[3].opBits != MicroOpBits::B64 || leaOps[4].opBits != MicroOpBits::B64 ||
            !leaOps[1].reg.isVirtualInt() || !leaOps[2].reg.isVirtualInt())
            return false;

        const MicroReg base  = leaOps[1].reg;
        const MicroReg index = leaOps[2].reg;
        const uint64_t scale = leaOps[5].valueU64;
        const bool     fits  = scale == 1 || scale == 2 || scale == 4 || scale == 8;
        if (!fits && (scale < 16 || scale > (uint64_t{1} << 30) || !std::has_single_bit(scale)))
            return false;

        const auto baseAtAddress  = ctx.ssa->reachingDef(base, lea.instRef);
        const auto baseAtAccess   = ctx.ssa->reachingDef(base, ref);
        const auto indexAtAddress = ctx.ssa->reachingDef(index, lea.instRef);
        const auto indexAtAccess  = ctx.ssa->reachingDef(index, ref);
        if (!baseAtAddress.valid() || !baseAtAccess.valid() || baseAtAddress.valueId != baseAtAccess.valueId || !indexAtAddress.valid() ||
            !indexAtAccess.valid() || indexAtAddress.valueId != indexAtAccess.valueId)
            return false;
        if (keepAccessScalar(ctx, ref, base))
            return false;

        const int64_t offset = static_cast<int64_t>(leaOps[6].valueU64 + accessAt);
        if (offset != static_cast<int64_t>(static_cast<int32_t>(offset)))
            return false;
        if (!ctx.claimAll({ref, lea.instRef}))
            return false;

        MicroReg scaledIndex = index;
        if (!fits)
        {
            ctx.ensureVirtualIndices();
            if (ctx.nextVirtualIntRegIndex >= MicroReg::K_MAX_INDEX)
                return false;
            scaledIndex = MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);

            MicroInstrOperand copy[3] = {};
            copy[0].reg               = scaledIndex;
            copy[1].reg               = index;
            copy[2].opBits            = MicroOpBits::B64;
            ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, copy);
            MicroInstrOperand shift[4] = {};
            shift[0].reg               = scaledIndex;
            shift[1].opBits            = MicroOpBits::B64;
            shift[2].microOp           = MicroOp::ShiftLeft;
            shift[3].valueU64          = static_cast<uint64_t>(std::countr_zero(scale));
            ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegImm, shift);
        }

        MicroInstrOperand access[8] = {};
        access[0].reg               = dst;
        access[1].reg               = base;
        access[2].reg               = scaledIndex;
        access[3].opBits            = bits;
        access[4].opBits            = MicroOpBits::B64;
        access[5].valueU64          = fits ? scale : 1;
        access[6].valueU64          = static_cast<uint64_t>(offset);
        if (isLoad)
        {
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadAmcRegMem, std::span{access, 7}, true);
        }
        else
        {
            access[7].microOp = ops[3].microOp;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegAmcMem, std::span{access, 8}, true);
        }
        ctx.emitErase(lea.instRef);
        return true;
    }

    // Fold a load through its indexed address directly into an integer ALU
    // consumer. Keeping this atomic avoids changing standalone indexed loads.
    bool tryFoldAmcAddressedLoadIntoRegOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        const MicroReg vt      = loadOps[0].reg;
        const MicroReg address = loadOps[1].reg;
        if (!vt.isVirtualInt() || !address.isVirtualInt() || vt == address || !valueHasSingleUse(*ctx.ssa, vt, loadRef))
            return false;

        const auto reaching = ctx.ssa->reachingDef(address, loadRef);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst || reaching.inst->op != MicroInstrOpcode::LoadAddrAmcRegMem ||
            !valueHasSingleUse(*ctx.ssa, address, reaching.instRef))
            return false;

        const MicroInstrOperand* addressOps = reaching.inst->ops(*ctx.operands);
        if (!addressOps || addressOps[0].reg != address || addressOps[3].opBits != MicroOpBits::B64 || addressOps[4].opBits != MicroOpBits::B64)
            return false;

        // A memory operand only scales by 1, 2, 4 or 8: the address of a wider
        // element stays a separate computation the legalizer can split.
        const uint64_t scale = addressOps[5].valueU64;
        if (scale != 1 && scale != 2 && scale != 4 && scale != 8)
            return false;

        const MicroReg base  = addressOps[1].reg;
        const MicroReg index = addressOps[2].reg;
        const auto     baseAtAddress  = ctx.ssa->reachingDef(base, reaching.instRef);
        const auto     baseAtLoad     = ctx.ssa->reachingDef(base, loadRef);
        const auto     indexAtAddress = ctx.ssa->reachingDef(index, reaching.instRef);
        const auto     indexAtLoad    = ctx.ssa->reachingDef(index, loadRef);
        if (!baseAtAddress.valid() || !baseAtLoad.valid() || baseAtAddress.valueId != baseAtLoad.valueId ||
            !indexAtAddress.valid() || !indexAtLoad.valid() || indexAtAddress.valueId != indexAtLoad.valueId)
            return false;
        if (keepAccessScalar(ctx, loadRef, base))
            return false;

        const int64_t offset = static_cast<int64_t>(addressOps[6].valueU64 + loadOps[3].valueU64);
        if (offset != static_cast<int64_t>(static_cast<int32_t>(offset)))
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();
        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef = ctx.ssa->instrUseDef(walker.current);
            if (!useDef || microRegSpanContains(useDef->defs, base) || microRegSpanContains(useDef->defs, index))
                return false;
            const bool defsVt = microRegSpanContains(useDef->defs, vt);
            const bool usesVt = microRegSpanContains(useDef->uses, vt);
            if (!defsVt && !usesVt)
                continue;

            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (w.op != MicroInstrOpcode::OpBinaryRegReg || !wOps || wOps[1].reg != vt || wOps[0].reg == vt ||
                wOps[2].opBits != loadOps[2].opBits || !isRegMemFoldableOp(wOps[3].microOp, wOps[2].opBits) ||
                (wOps[3].microOp == MicroOp::MultiplySigned && wOps[2].opBits == MicroOpBits::B8))
                return false;

            const MicroInstrRef opRef = walker.current;
            if (!ctx.claimAll({reaching.instRef, loadRef, opRef}))
                return false;

            MicroInstrOperand newOps[8] = {};
            newOps[0].reg               = wOps[0].reg;
            newOps[1].reg               = base;
            newOps[2].reg               = index;
            newOps[3].opBits            = wOps[2].opBits;
            newOps[4].opBits            = MicroOpBits::B64;
            newOps[5].valueU64          = addressOps[5].valueU64;
            newOps[6].valueU64          = static_cast<uint64_t>(offset);
            newOps[7].microOp           = wOps[3].microOp;
            ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegAmcMem, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            ctx.emitErase(reaching.instRef);
            return true;
        }

        return false;
    }

    // Fold an already canonical indexed load into the right operand of an
    // integer operation. This complements tryFoldAmcAddressedLoadIntoRegOp:
    // later combine sweeps have often replaced the separate address and load
    // with LoadAmcRegMem before the consumer becomes foldable.
    bool tryFoldAmcLoadIntoRegOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa || loadInst.op != MicroInstrOpcode::LoadAmcRegMem)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroReg    index    = loadOps[2].reg;
        const MicroOpBits loadBits = loadOps[3].opBits;
        if (!vt.isVirtualInt() || base == vt || index == vt || loadOps[4].opBits != MicroOpBits::B64 ||
            keepAccessScalar(ctx, loadRef, base) || !valueHasSingleUse(*ctx.ssa, vt, loadRef))
            return false;

        const uint64_t scale = loadOps[5].valueU64;
        if (scale != 1 && scale != 2 && scale != 4 && scale != 8)
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();
        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef = ctx.ssa->instrUseDef(walker.current);
            if (!useDef || microRegSpanContains(useDef->defs, base) || microRegSpanContains(useDef->defs, index))
                return false;
            const bool defsVt = microRegSpanContains(useDef->defs, vt);
            const bool usesVt = microRegSpanContains(useDef->uses, vt);
            if (!defsVt && !usesVt)
                continue;

            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (w.op != MicroInstrOpcode::OpBinaryRegReg || !wOps || wOps[1].reg != vt || wOps[0].reg == vt ||
                wOps[2].opBits != loadBits || !isRegMemFoldableOp(wOps[3].microOp, wOps[2].opBits) ||
                (wOps[3].microOp == MicroOp::MultiplySigned && loadBits == MicroOpBits::B8))
                return false;

            const MicroInstrRef opRef = walker.current;
            if (!ctx.claimAll({loadRef, opRef}))
                return false;

            MicroInstrOperand newOps[8] = {};
            newOps[0].reg               = wOps[0].reg;
            newOps[1].reg               = base;
            newOps[2].reg               = index;
            newOps[3].opBits            = loadBits;
            newOps[4]                   = loadOps[4];
            newOps[5].valueU64          = scale;
            newOps[6].valueU64          = loadOps[6].valueU64;
            newOps[7].microOp           = wOps[3].microOp;
            ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegAmcMem, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            return true;
        }

        return false;
    }

    // The left operand of a register compare loaded just before it compares
    // in place, as `cmp byte [rcx + 2], dl` does in a struct equality:
    //
    //     LoadRegMem vt, [base + disp]         CmpMemReg [base + disp], rhs
    //     CmpRegReg  vt, rhs              ->
    //
    // The operands keep their order, so the flags mean the same thing.
    bool tryFoldLoadIntoRegCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        // LoadRegMem: [dst, base, loadBits, offset].
        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroOpBits loadBits = loadOps[2].opBits;
        if (!vt.isVirtualInt() || !base.isAnyInt() || base == vt || keepAccessScalar(ctx, loadRef, base))
            return false;
        if (!valueHasSingleUse(*ctx.ssa, vt, loadRef))
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();
        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef = ctx.ssa->instrUseDef(walker.current);
            if (!useDef || microRegSpanContains(useDef->defs, base))
                return false;
            if (!microRegSpanContains(useDef->uses, vt) && !microRegSpanContains(useDef->defs, vt))
                continue;

            // CmpRegReg: [lhs, rhs, opBits].
            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (w.op != MicroInstrOpcode::CmpRegReg || !wOps || wOps[0].reg != vt || wOps[1].reg == vt || !wOps[1].reg.isAnyInt() ||
                wOps[2].opBits != loadBits)
                return false;

            const MicroInstrRef cmpRef = walker.current;
            if (!ctx.claimAll({loadRef, cmpRef}))
                return false;

            // CmpMemReg: [base, reg, opBits, offset].
            MicroInstrOperand newOps[4];
            newOps[0].reg      = base;
            newOps[1].reg      = wOps[1].reg;
            newOps[2].opBits   = loadBits;
            newOps[3].valueU64 = loadOps[3].valueU64;
            ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpMemReg, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            return true;
        }

        return false;
    }

    // Fuse a plain load feeding a widening of the loaded bits into one
    // extending load, as the indexed forms below do for arrays:
    //
    //     LoadRegMem          vt,  [base + disp]           (load bN)
    //     LoadSignedExtRegReg dst, vt, bM <- bN            (or the zero form)
    //   ->
    //     LoadSignedExtRegMem dst, [base + disp], bM <- bN
    //
    // A 32-bit load already clears the upper half, so only the sign form
    // takes one. The destination may be the loaded register itself: the
    // extension is the load's first and only reader.
    bool tryFoldLoadIntoExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        // LoadRegMem: [dst, base, loadBits, offset].
        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroOpBits loadBits = loadOps[2].opBits;
        const uint64_t    loadOff  = loadOps[3].valueU64;
        if (!vt.isVirtualInt() || !base.isAnyInt() || base == vt)
            return false;
        if (loadBits != MicroOpBits::B8 && loadBits != MicroOpBits::B16 && loadBits != MicroOpBits::B32)
            return false;
        if (keepAccessScalar(ctx, loadRef, base))
            return false;

        uint32_t loadValueId = 0;
        if (!ctx.ssa->defValue(vt, loadRef, loadValueId) || ctx.ssa->transitiveInstructionUseCount(loadValueId, 2) != 1)
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();
        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef = ctx.ssa->instrUseDef(walker.current);
            if (!useDef || microRegSpanContains(useDef->defs, base))
                return false;
            const bool usesVt = microRegSpanContains(useDef->uses, vt);
            const bool defsVt = microRegSpanContains(useDef->defs, vt);
            if (!usesVt && !defsVt)
                continue;

            const bool signExtend = w.op == MicroInstrOpcode::LoadSignedExtRegReg;
            if (!signExtend && w.op != MicroInstrOpcode::LoadZeroExtRegReg)
                return false;
            if (!signExtend && loadBits == MicroOpBits::B32)
                return false;

            // LoadSignedExtRegReg / LoadZeroExtRegReg: [dst, src, dstBits, srcBits].
            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (!wOps || wOps[1].reg != vt || !wOps[0].reg.isAnyInt() || wOps[3].opBits != loadBits)
                return false;
            if (wOps[2].opBits != MicroOpBits::B32 && wOps[2].opBits != MicroOpBits::B64)
                return false;

            const MicroInstrRef extRef = walker.current;
            if (!ctx.claimAll({loadRef, extRef}))
                return false;

            // LoadSignedExtRegMem / LoadZeroExtRegMem: [dst, base, dstBits, srcBits, offset].
            MicroInstrOperand newOps[5];
            newOps[0].reg      = wOps[0].reg;
            newOps[1].reg      = base;
            newOps[2].opBits   = wOps[2].opBits;
            newOps[3].opBits   = loadBits;
            newOps[4].valueU64 = loadOff;
            ctx.emitRewrite(extRef, signExtend ? MicroInstrOpcode::LoadSignedExtRegMem : MicroInstrOpcode::LoadZeroExtRegMem, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            return true;
        }

        return false;
    }

    // Fuse an indexed byte, word, or dword load feeding a sign extension into
    // one indexed movsx/movsxd (LoadSignedExtAmcRegMem):
    //
    //     LoadAmcRegMem       vt,  [base + idx*scale + disp]   (load b32)
    //     LoadSignedExtRegReg dst, vt, b64<-b32
    //   ->
    //     LoadSignedExtAmcRegMem dst, [base + idx*scale + disp], b64<-b32
    //
    // Matches a widening reduction `acc(s64) += narrowArray[i]`. Uses the
    // transitive-instruction use count (not raw uses.size()) so a dead loop-header
    // phi on the element temp does not hide its single-consumer shape — local to
    // this fold, so it does not perturb the global single-use heuristics that
    // mem2reg promotion depends on.
    bool tryFoldAmcLoadIntoSignExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        // LoadAmcRegMem: [dst, base, index, loadBits, addrBits, mulValue, addValue].
        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroReg    index    = loadOps[2].reg;
        const MicroOpBits loadBits = loadOps[3].opBits;
        const MicroOpBits addrBits = loadOps[4].opBits;

        // Indexed sign extension accepts byte/word sources into 32/64 bits
        // and dword sources into 64 bits, with 64-bit addressing.
        if ((loadBits != MicroOpBits::B8 && loadBits != MicroOpBits::B16 && loadBits != MicroOpBits::B32) || addrBits != MicroOpBits::B64)
            return false;
        if (!vt.isVirtualInt() || base == vt || index == vt)
            return false;

        uint32_t loadValueId = 0;
        if (!ctx.ssa->defValue(vt, loadRef, loadValueId) || ctx.ssa->transitiveInstructionUseCount(loadValueId, 2) != 1)
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();
        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;

            // Delaying the load to the extend's position must not cross an
            // aliasing store, a call, control flow, or a redefinition of an
            // addressing register.
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef   = ctx.ssa->instrUseDef(walker.current);
            const bool  defsAddr = useDef && (microRegSpanContains(useDef->defs, base) || microRegSpanContains(useDef->defs, index));
            const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);
            const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);

            if (defsAddr)
                return false;
            if (!usesVt && !defsVt)
                continue;

            // First reference to vt must be the sign-extend.
            if (w.op != MicroInstrOpcode::LoadSignedExtRegReg)
                return false;

            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (!wOps)
                return false;
            const MicroReg    dstReg  = wOps[0].reg;
            const MicroReg    srcReg  = wOps[1].reg;
            const MicroOpBits dstBits = wOps[2].opBits;
            const MicroOpBits srcBits = wOps[3].opBits;
            if (srcReg != vt || dstReg == vt || srcBits != loadBits ||
                (dstBits != MicroOpBits::B32 && dstBits != MicroOpBits::B64) || getNumBits(dstBits) <= getNumBits(srcBits))
                return false;

            const MicroInstrRef extRef = walker.current;
            if (!ctx.claimAll({loadRef, extRef}))
                return false;

            // LoadSignedExtAmcRegMem: [dst, base, index, dstBits, srcBits, mul, add].
            MicroInstrOperand newOps[7];
            newOps[0].reg      = dstReg;
            newOps[1].reg      = base;
            newOps[2].reg      = index;
            newOps[3].opBits   = dstBits;
            newOps[4].opBits   = srcBits;
            newOps[5].valueU64 = loadOps[5].valueU64;
            newOps[6].valueU64 = loadOps[6].valueU64;
            ctx.emitRewrite(extRef, MicroInstrOpcode::LoadSignedExtAmcRegMem, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            return true;
        }

        return false;
    }

    // Fuse an indexed byte or word load feeding a zero-extend into a single
    // indexed movzx (LoadZeroExtAmcRegMem):
    //
    //     LoadAmcRegMem     vt,  [base + idx*scale + disp]   (load b8/b16)
    //     LoadZeroExtRegReg dst, vt, b32/b64<-b8/b16
    //   ->
    //     LoadZeroExtAmcRegMem dst, [base + idx*scale + disp], b32/b64<-b8/b16
    //
    // The byte-scan shape of every text parser: load text[p], widen, compare.
    // The rewrite happens at the extend's position like the sign-extend fold
    // above, under the same no-store/no-call/no-redef window.
    bool tryFoldAmcLoadIntoZeroExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        // LoadAmcRegMem: [dst, base, index, loadBits, addrBits, mulValue, addValue].
        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroReg    index    = loadOps[2].reg;
        const MicroOpBits loadBits = loadOps[3].opBits;
        const MicroOpBits addrBits = loadOps[4].opBits;

        // The encoder's indexed movzx handles byte and word sources into a 32-
        // or 64-bit register with 64-bit addressing.
        if ((loadBits != MicroOpBits::B8 && loadBits != MicroOpBits::B16) || addrBits != MicroOpBits::B64)
            return false;
        if (!vt.isVirtualInt() || base == vt || index == vt)
            return false;

        uint32_t loadValueId = 0;
        if (!ctx.ssa->defValue(vt, loadRef, loadValueId) || ctx.ssa->transitiveInstructionUseCount(loadValueId, 2) != 1)
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();
        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;

            // Delaying the load to the extend's position must not cross an
            // aliasing store, a call, control flow, or a redefinition of an
            // addressing register.
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef   = ctx.ssa->instrUseDef(walker.current);
            const bool  defsAddr = useDef && (microRegSpanContains(useDef->defs, base) || microRegSpanContains(useDef->defs, index));
            const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);
            const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);

            if (defsAddr)
                return false;
            if (!usesVt && !defsVt)
                continue;

            // First reference to vt must be the zero-extend.
            if (w.op != MicroInstrOpcode::LoadZeroExtRegReg)
                return false;

            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (!wOps)
                return false;
            const MicroReg    dstReg  = wOps[0].reg;
            const MicroReg    srcReg  = wOps[1].reg;
            const MicroOpBits dstBits = wOps[2].opBits;
            const MicroOpBits srcBits = wOps[3].opBits;
            if (srcReg != vt || dstReg == vt || srcBits != loadBits)
                return false;
            if (dstBits != MicroOpBits::B32 && dstBits != MicroOpBits::B64)
                return false;

            const MicroInstrRef extRef = walker.current;
            if (!ctx.claimAll({loadRef, extRef}))
                return false;

            // LoadZeroExtAmcRegMem: [dst, base, index, dstBits, srcBits, mul, add].
            MicroInstrOperand newOps[7];
            newOps[0].reg      = dstReg;
            newOps[1].reg      = base;
            newOps[2].reg      = index;
            newOps[3].opBits   = dstBits;
            newOps[4].opBits   = srcBits;
            newOps[5].valueU64 = loadOps[5].valueU64;
            newOps[6].valueU64 = loadOps[6].valueU64;
            ctx.emitRewrite(extRef, MicroInstrOpcode::LoadZeroExtAmcRegMem, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            return true;
        }

        return false;
    }

    namespace
    {
        // Operand index of the MicroCond for each UsesCpuFlags opcode this
        // fold understands; anything else blocks the rewrite.
        // Conditions whose verdict is unchanged when a compare of a
        // zero-extended value is narrowed to the source width: unsigned
        // orders and equality. Signed orders are not — 0x80..0xFF flip sign
        // at the narrow width.
        bool condSurvivesZeroExtNarrowing(MicroCond cond)
        {
            switch (cond)
            {
                case MicroCond::Equal:
                case MicroCond::NotEqual:
                case MicroCond::Zero:
                case MicroCond::NotZero:
                case MicroCond::Below:
                case MicroCond::BelowOrEqual:
                case MicroCond::NotAbove:
                case MicroCond::Above:
                case MicroCond::AboveOrEqual:
                    return true;
                default:
                    return false;
            }
        }

        // Every reader of the flags a compare at cmpRef defines must satisfy
        // `condOk`. Mirrors ConstProp's consumer scan: a terminator or label
        // ends flag liveness in this IR, and an unknown flags reader blocks.
        bool allCmpFlagConsumersSatisfy(const Context& ctx, const MicroInstrRef cmpRef, bool (*condOk)(MicroCond))
        {
            MicroStorage::Iterator walker;
            if (!findAnchorPosition(walker, *ctx.storage, cmpRef))
                return false;
            ++walker;

            const auto endIt = ctx.storage->view().end();
            for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
            {
                const MicroInstr&    inst = *walker;
                const MicroInstrDef& info = MicroInstr::info(inst.op);

                if (info.flags.has(MicroInstrFlagsE::UsesCpuFlags))
                {
                    uint8_t condIdx = 0;
                    if (!MicroPassHelpers::conditionOperandIndex(inst.op, condIdx))
                        return false;

                    const MicroInstrOperand* ops = inst.ops(*ctx.operands);
                    if (!ops)
                        return false;

                    const MicroCond cond = ops[condIdx].cpuCond;
                    if (cond != MicroCond::Unconditional && !condOk(cond))
                        return false;
                }

                if (MicroPassHelpers::instructionActuallyDefinesCpuFlags(inst, inst.ops(*ctx.operands)))
                    return true;
                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) || inst.op == MicroInstrOpcode::Label)
                    return true;
            }

            return true;
        }

        constexpr uint32_t K_MAX_REREAD_WINDOW = 32;

        // The SSA value a register carries at an instruction, looked up through
        // the plain 64-bit copies mem2reg and the front end leave between a
        // promoted local and its uses.
        MicroSsaState::ReachingDef rootAddressValue(const Context& ctx, MicroReg reg, MicroInstrRef atRef)
        {
            MicroSsaState::ReachingDef reach = ctx.ssa->reachingDef(reg, atRef);
            for (uint32_t depth = 0; depth < 8 && reach.valid() && !reach.isPhi && reach.inst && reach.inst->op == MicroInstrOpcode::LoadRegReg; ++depth)
            {
                const MicroInstrOperand* copyOps = reach.inst->ops(*ctx.operands);
                if (!copyOps || copyOps[2].opBits != MicroOpBits::B64 || !copyOps[1].reg.isVirtual())
                    break;
                const MicroSsaState::ReachingDef src = ctx.ssa->reachingDef(copyOps[1].reg, reach.instRef);
                if (!src.valid())
                    break;
                reach = src;
            }
            return reach;
        }

        // True when no write or call separates `fromRef` from `toRef` within
        // the window, `toRef` being later in the straight line.
        bool noMemoryChangeBetween(const Context& ctx, MicroInstrRef fromRef, MicroInstrRef toRef)
        {
            MicroInstrRef ref = ctx.storage->findNextInstructionRef(fromRef);
            for (uint32_t step = 0; step < K_MAX_REREAD_WINDOW && ref.isValid(); ++step, ref = ctx.storage->findNextInstructionRef(ref))
            {
                if (ref == toRef)
                    return true;
                const MicroInstr& inst = *ctx.storage->ptr(ref);
                if (writesMemory(inst) || MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                    return false;
            }
            return false;
        }

        // True when the two registers hold the same address at their respective
        // instructions: the same SSA value, or — before mem2reg has promoted the
        // local both read — two reloads of one frame slot with nothing written
        // in between, which is how every use of `p` is spelled on the first
        // sweep, while the compare fold is already eligible.
        bool sameAddressValue(const Context& ctx, const MicroSsaState::ReachingDef& a, MicroReg regB, MicroInstrRef atB)
        {
            const MicroSsaState::ReachingDef b = rootAddressValue(ctx, regB, atB);
            if (!a.valid() || !b.valid())
                return false;
            if (a.valueId == b.valueId)
                return true;
            if (a.isPhi || b.isPhi || !a.inst || !b.inst)
                return false;
            if (a.inst->op != MicroInstrOpcode::LoadRegMem || b.inst->op != MicroInstrOpcode::LoadRegMem)
                return false;

            // LoadRegMem: [dst, base, opBits, offset].
            const MicroInstrOperand* aOps = a.inst->ops(*ctx.operands);
            const MicroInstrOperand* bOps = b.inst->ops(*ctx.operands);
            if (!aOps || !bOps || aOps[2].opBits != bOps[2].opBits || aOps[3].valueU64 != bOps[3].valueU64)
                return false;

            const MicroSsaState::ReachingDef baseA = ctx.ssa->reachingDef(aOps[1].reg, a.instRef);
            const MicroSsaState::ReachingDef baseB = ctx.ssa->reachingDef(bOps[1].reg, b.instRef);
            if (!baseA.valid() || !baseB.valid() || baseA.valueId != baseB.valueId)
                return false;
            return noMemoryChangeBetween(ctx, a.instRef, b.instRef);
        }

        // The addressing of an indexed read: an indexed load itself, or a
        // plain load at offset zero through an address an indexed lea computed,
        // which is how every `text[p]` is spelled before the lea is folded into
        // the access. `atRef` is where the base and index registers are read.
        struct IndexedRead
        {
            MicroInstrRef atRef    = MicroInstrRef::invalid();
            MicroReg      base     = MicroReg::invalid();
            MicroReg      index    = MicroReg::invalid();
            uint64_t      mulValue = 0;
            uint64_t      addValue = 0;
            MicroOpBits   cellBits = MicroOpBits::Zero;
        };

        bool matchIndexedRead(IndexedRead& out, const Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
        {
            const MicroInstrOperand* ops = inst.ops(*ctx.operands);
            if (!ops)
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::LoadAmcRegMem:
                    // [dst, base, index, loadBits, addrBits, mul, add]
                    if (ops[4].opBits != MicroOpBits::B64)
                        return false;
                    out = {.atRef = ref, .base = ops[1].reg, .index = ops[2].reg, .mulValue = ops[5].valueU64, .addValue = ops[6].valueU64, .cellBits = ops[3].opBits};
                    return true;

                case MicroInstrOpcode::LoadSignedExtAmcRegMem:
                case MicroInstrOpcode::LoadZeroExtAmcRegMem:
                    // [dst, base, index, dstBits, srcBits, mul, add]
                    out = {.atRef = ref, .base = ops[1].reg, .index = ops[2].reg, .mulValue = ops[5].valueU64, .addValue = ops[6].valueU64, .cellBits = ops[4].opBits};
                    return true;

                case MicroInstrOpcode::LoadRegMem:
                case MicroInstrOpcode::LoadSignedExtRegMem:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                {
                    // [dst, base, bits, off] or [dst, base, dstBits, srcBits, off], through an
                    // address from LoadAddrAmcRegMem [dst, base, index, dstBits, addrBits, mul, add].
                    const bool plain = inst.op == MicroInstrOpcode::LoadRegMem;
                    if (ops[plain ? 3 : 4].valueU64 != 0)
                        return false;
                    const MicroSsaState::ReachingDef addr = ctx.ssa->reachingDef(ops[1].reg, ref);
                    if (!addr.valid() || addr.isPhi || !addr.inst || addr.inst->op != MicroInstrOpcode::LoadAddrAmcRegMem)
                        return false;
                    const MicroInstrOperand* leaOps = addr.inst->ops(*ctx.operands);
                    if (!leaOps || leaOps[3].opBits != MicroOpBits::B64)
                        return false;
                    out = {.atRef = addr.instRef, .base = leaOps[1].reg, .index = leaOps[2].reg, .mulValue = leaOps[5].valueU64, .addValue = leaOps[6].valueU64, .cellBits = ops[plain ? 2 : 3].opBits};
                    return true;
                }

                default:
                    return false;
            }
        }

        // True when the straight line after `fromRef` reads the same cell
        // again — the same bytes at the same address values — before any write,
        // call or exit. Folding the first read into the compare would leave
        // nothing for that second read to share; left as a load, value
        // numbering feeds both from it. This is the `text[p] != ','` guard
        // followed by the `text[p] - 48` consumer of every text scanner, read
        // once instead of twice. Labels and conditional jumps are looked
        // through: the decision only keeps a load, which is always sound, and
        // the join of a short-circuit condition sits between the guard and the
        // body it protects until branch simplification threads it.
        bool cellReadAgainInStraightLine(const Context& ctx, MicroInstrRef loadRef, MicroInstrRef fromRef, MicroReg base, MicroReg index, uint64_t mulValue, uint64_t addValue, MicroOpBits cellBits)
        {
            MicroSsaState::ReachingDef baseValue;
            MicroSsaState::ReachingDef indexValue;
            MicroInstrRef              ref = ctx.storage->findNextInstructionRef(fromRef);
            for (uint32_t step = 0; step < K_MAX_REREAD_WINDOW && ref.isValid(); ++step, ref = ctx.storage->findNextInstructionRef(ref))
            {
                const MicroInstr&    inst = *ctx.storage->ptr(ref);
                const MicroInstrDef& info = MicroInstr::info(inst.op);
                if (writesMemory(inst) || info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                    return false;
                if (inst.op == MicroInstrOpcode::JumpCond)
                {
                    if (MicroInstrInfo::isUnconditionalJumpInstruction(inst, inst.ops(*ctx.operands)))
                        return false;
                }
                else if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                {
                    return false;
                }

                IndexedRead read;
                if (!matchIndexedRead(read, ctx, ref, inst))
                    continue;
                if (read.cellBits != cellBits || read.mulValue != mulValue || read.addValue != addValue)
                    continue;
                // Only the candidate position changes during this read-only
                // scan. Resolve each original copy chain once, when needed.
                if (!baseValue.valid())
                {
                    baseValue = rootAddressValue(ctx, base, loadRef);
                    if (!baseValue.valid())
                        return false;
                }
                if (!sameAddressValue(ctx, baseValue, read.base, read.atRef))
                    continue;
                if (!indexValue.valid())
                {
                    indexValue = rootAddressValue(ctx, index, loadRef);
                    if (!indexValue.valid())
                        return false;
                }
                if (sameAddressValue(ctx, indexValue, read.index, read.atRef))
                    return true;
            }

            return false;
        }

        // Shared tail of the two compare folds below: from an indexed load at
        // loadRef whose single consumer must compare the loaded value, rewrite
        // that compare to use the indexed memory operand at cmpBits and erase
        // the load. `cmpBits` is the width the memory operand is compared at.
        bool foldAmcLoadIntoCompareAt(Context& ctx, MicroInstrRef loadRef, MicroReg vt, MicroReg base, MicroReg index, uint64_t mulValue, uint64_t addValue, MicroOpBits expectedCmpBits, MicroOpBits cmpBits, bool needsUnsignedConds)
        {
            MicroStorage::Iterator walker;
            if (!findAnchorPosition(walker, *ctx.storage, loadRef))
                return false;
            ++walker;

            const auto endIt = ctx.storage->view().end();
            for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
            {
                const MicroInstr& w = *walker;

                // Delaying the load to the compare's position must not cross
                // an aliasing store, a call, control flow, or a redefinition
                // of an addressing register.
                if (isControlOrCall(w) || writesMemory(w))
                    return false;

                const auto* useDef   = ctx.ssa->instrUseDef(walker.current);
                const bool  defsAddr = useDef && (microRegSpanContains(useDef->defs, base) || microRegSpanContains(useDef->defs, index));
                const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);
                const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);

                if (defsAddr)
                    return false;
                if (!usesVt && !defsVt)
                    continue;

                // First reference to vt must be a comparison with vt on the
                // left, so replacing that operand preserves every condition.
                if (w.op != MicroInstrOpcode::CmpRegImm && w.op != MicroInstrOpcode::CmpRegReg)
                    return false;

                // CmpRegImm: [reg, opBits, imm].
                // CmpRegReg: [lhs, rhs, opBits].
                const MicroInstrOperand* wOps = w.ops(*ctx.operands);
                if (!wOps)
                    return false;
                const MicroOpBits actualCmpBits = w.op == MicroInstrOpcode::CmpRegImm ? wOps[1].opBits : wOps[2].opBits;
                if (wOps[0].reg != vt || actualCmpBits != expectedCmpBits)
                    return false;

                if (w.op == MicroInstrOpcode::CmpRegReg)
                {
                    const MicroReg rhs = wOps[1].reg;
                    if (needsUnsignedConds || !rhs.isVirtualInt() || rhs == vt || rhs == base || rhs == index)
                        return false;

                    const MicroSsaState::ReachingDef rhsDef = ctx.ssa->reachingDef(rhs, walker.current);
                    const bool rhsIsSingleUseMemoryLoad = rhsDef.valid() && !rhsDef.isPhi && rhsDef.inst &&
                                                          (rhsDef.inst->op == MicroInstrOpcode::LoadRegMem ||
                                                           rhsDef.inst->op == MicroInstrOpcode::LoadAmcRegMem) &&
                                                          valueHasSingleUse(*ctx.ssa, rhs, rhsDef.instRef);

                    const MicroInstrRef cmpRef = walker.current;
                    if (cellReadAgainInStraightLine(ctx, loadRef, cmpRef, base, index, mulValue, addValue, cmpBits))
                        return false;
                    if (!ctx.claimAll({loadRef, cmpRef}))
                        return false;

                    // CmpAmcReg: [base, index, src, addrBits, cmpBits, mul, add].
                    MicroInstrOperand newOps[7];
                    newOps[0].reg      = base;
                    newOps[1].reg      = index;
                    newOps[2].reg      = rhs;
                    newOps[3].opBits   = MicroOpBits::B64;
                    newOps[4].opBits   = cmpBits;
                    newOps[5].valueU64 = mulValue;
                    newOps[6].valueU64 = addValue;
                    if (cmpBits == MicroOpBits::B64 && rhsIsSingleUseMemoryLoad)
                        protectReturnedB64ComparisonSource(ctx, cmpRef, rhs);
                    ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpAmcReg, newOps, /*allocNewBlock=*/true);
                    ctx.emitErase(loadRef);
                    return true;
                }

                // The immediate must keep its meaning at the memory width,
                // and stay encodable (cmp r/m64 sign-extends a 32-bit
                // immediate).
                const uint64_t immU64 = wOps[2].valueU64;
                if (needsUnsignedConds)
                {
                    const uint64_t maxNarrow = cmpBits == MicroOpBits::B8 ? 0xFFull : 0xFFFFull;
                    if (immU64 > maxNarrow)
                        return false;
                }
                else if (cmpBits == MicroOpBits::B64)
                {
                    const uint64_t signExtended = static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(immU64)));
                    if (immU64 != signExtended)
                        return false;
                }

                if (needsUnsignedConds && !allCmpFlagConsumersSatisfy(ctx, walker.current, condSurvivesZeroExtNarrowing))
                    return false;

                const MicroInstrRef cmpRef = walker.current;
                if (cellReadAgainInStraightLine(ctx, loadRef, cmpRef, base, index, mulValue, addValue, cmpBits))
                    return false;
                if (!ctx.claimAll({loadRef, cmpRef}))
                    return false;

                // CmpAmcImm: [base, index, cmpBits, addrBits, mul, add, imm].
                MicroInstrOperand newOps[7];
                newOps[0].reg      = base;
                newOps[1].reg      = index;
                newOps[2].opBits   = cmpBits;
                newOps[3].opBits   = MicroOpBits::B64;
                newOps[4].valueU64 = mulValue;
                newOps[5].valueU64 = addValue;
                newOps[6]          = wOps[2];
                ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpAmcImm, newOps, /*allocNewBlock=*/true);
                ctx.emitErase(loadRef);
                return true;
            }

            return false;
        }
    }

    // Factor a product plus/minus a reread of the same ordinary memory cell.
    // A bounded straight-line scan proves the two reads observe one value.
    bool tryFactorReloadedProduct(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!ctx.ssa || ctx.isClaimed(ref))
            return false;
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isVirtualInt() || !ops[1].reg.isVirtualInt() || (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
            (ops[3].microOp != MicroOp::Add && ops[3].microOp != MicroOp::Subtract) ||
            keepAccessScalar(ctx, ref, ops[1].reg))
            return false;

        MicroReg      productReg  = ops[0].reg;
        auto          product     = ctx.ssa->reachingDef(productReg, ref);
        MicroInstrRef productCopy = MicroInstrRef::invalid();
        if (product.valid() && !product.isPhi && product.inst && product.inst->op == MicroInstrOpcode::LoadRegReg)
        {
            const auto* copy = product.inst->ops(*ctx.operands);
            if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(ops[2].opBits) ||
                ctx.ssa->transitiveInstructionUseCount(product.valueId, 2) != 1)
                return false;
            productCopy = product.instRef;
            productReg  = copy[1].reg;
            product     = ctx.ssa->reachingDef(productReg, productCopy);
        }
        if (!product.valid() || product.isPhi || !product.inst || product.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
            ctx.ssa->transitiveInstructionUseCount(product.valueId, 2) != 1)
            return false;
        const auto* multiply = product.inst->ops(*ctx.operands);
        if (!multiply || multiply[3].microOp != MicroOp::MultiplySigned || multiply[2].opBits != ops[2].opBits || !multiply[1].reg.isVirtualInt())
            return false;
        const auto initial = ctx.ssa->reachingDef(productReg, product.instRef);
        if (!initial.valid() || initial.isPhi || !initial.inst || initial.inst->op != MicroInstrOpcode::LoadRegMem ||
            ctx.ssa->transitiveInstructionUseCount(initial.valueId, 2) != 1)
            return false;
        const auto* load = initial.inst->ops(*ctx.operands);
        if (!load || load[2].opBits != ops[2].opBits || load[3].valueU64 != ops[4].valueU64 ||
            !sameAddressValue(ctx, rootAddressValue(ctx, load[1].reg, initial.instRef), ops[1].reg, ref))
            return false;
        const MicroReg factor      = multiply[1].reg;
        const auto     factorValue = ctx.ssa->reachingDef(factor, product.instRef);
        if (!factorValue.valid() || ctx.ssa->reachingDef(factor, ref).valueId != factorValue.valueId)
            return false;

        bool          reached = false;
        MicroInstrRef scan    = ctx.storage->findNextInstructionRef(initial.instRef);
        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && scan.isValid(); ++step, scan = ctx.storage->findNextInstructionRef(scan))
        {
            if (scan == ref)
            {
                reached = true;
                break;
            }
            const auto& between = *ctx.storage->ptr(scan);
            if (isControlOrCall(between) || writesMemory(between) || between.op == MicroInstrOpcode::LoadVolatileRegMem)
                return false;
        }
        if (!reached || !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, product.instRef, ctx.builder))
            return false;
        if (!ctx.nextVirtualFloatRegIndex)
            MicroPassHelpers::computeNextVirtualRegIndices(*ctx.passContext, ctx.nextVirtualIntRegIndex, ctx.nextVirtualFloatRegIndex);
        if (ctx.nextVirtualIntRegIndex >= MicroReg::K_MAX_INDEX ||
            !ctx.claimAll({ref, product.instRef, initial.instRef, productCopy.isValid() ? productCopy : ref}))
            return false;

        const MicroReg    temporary   = MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);
        MicroInstrOperand adjusted[4] = {};
        adjusted[0].reg               = temporary;
        adjusted[1].reg               = factor;
        adjusted[2].opBits            = ops[2].opBits;
        adjusted[3].valueU64          = ops[3].microOp == MicroOp::Add ? 1 : UINT64_MAX;
        ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadAddrRegMem, adjusted);
        MicroInstrOperand result[5] = {};
        result[0].reg               = temporary;
        result[1]                   = ops[1];
        result[2]                   = ops[2];
        result[3].microOp           = MicroOp::MultiplySigned;
        result[4]                   = ops[4];
        ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegMem, result);
        MicroInstrOperand copy[3] = {};
        copy[0]                   = ops[0];
        copy[1].reg               = temporary;
        copy[2]                   = ops[2];
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, copy);
        ctx.emitErase(initial.instRef);
        ctx.emitErase(product.instRef);
        if (productCopy.isValid())
            ctx.emitErase(productCopy);
        return true;
    }

    // Fuse an indexed zero-extending load whose only consumer is a compare
    // against an immediate into a single memory compare at the source width:
    //
    //     LoadZeroExtAmcRegMem vt, [base + idx*scale + disp], b32<-b8
    //     CmpRegImm            vt, imm, b32
    //   ->
    //     CmpAmcImm [base + idx*scale + disp], imm, b8
    //
    // The byte-scan test of every text parser. Narrowing the compare is only
    // sound for unsigned/equality consumers with an immediate that fits the
    // source width; both are checked.
    bool tryFoldZeroExtAmcLoadIntoCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        // LoadZeroExtAmcRegMem: [dst, base, index, dstBits, srcBits, mul, add].
        const MicroReg    vt      = loadOps[0].reg;
        const MicroReg    base    = loadOps[1].reg;
        const MicroReg    index   = loadOps[2].reg;
        const MicroOpBits dstBits = loadOps[3].opBits;
        const MicroOpBits srcBits = loadOps[4].opBits;

        if (srcBits != MicroOpBits::B8 && srcBits != MicroOpBits::B16)
            return false;
        if (!vt.isVirtualInt() || base == vt || index == vt)
            return false;

        uint32_t loadValueId = 0;
        if (!ctx.ssa->defValue(vt, loadRef, loadValueId) || ctx.ssa->transitiveInstructionUseCount(loadValueId, 2) != 1)
            return false;

        return foldAmcLoadIntoCompareAt(ctx, loadRef, vt, base, index, loadOps[5].valueU64, loadOps[6].valueU64, dstBits, srcBits, /*needsUnsignedConds=*/true);
    }

    // Same fold for a plain indexed load compared at its own width — no
    // narrowing, so every condition is preserved as-is.
    bool tryFoldAmcLoadIntoCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        // LoadAmcRegMem: [dst, base, index, loadBits, addrBits, mul, add].
        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroReg    index    = loadOps[2].reg;
        const MicroOpBits loadBits = loadOps[3].opBits;
        const MicroOpBits addrBits = loadOps[4].opBits;

        if (addrBits != MicroOpBits::B64)
            return false;
        if (!vt.isVirtualInt() || base == vt || index == vt)
            return false;

        uint32_t loadValueId = 0;
        if (!ctx.ssa->defValue(vt, loadRef, loadValueId) || ctx.ssa->transitiveInstructionUseCount(loadValueId, 2) != 1)
            return false;

        return foldAmcLoadIntoCompareAt(ctx, loadRef, vt, base, index, loadOps[5].valueU64, loadOps[6].valueU64, loadBits, loadBits, /*needsUnsignedConds=*/false);
    }

    // A value loaded into a general register only to be moved into a vector
    // register is loaded into the vector register instead:
    //
    //     LoadRegMem  vt,   [b+o]           LoadRegMem  fd, [b+o]
    //     LoadRegReg  fd,   vt        ->
    //
    // This is the mirror of tryFoldLaneCopyIntoStore, which sends a lane to
    // memory without the general register. A scalar float load zeroes the
    // upper lanes exactly as MOVD/MOVQ from a general register does, so the
    // vector register holds the same bits. Reading a global double went
    // through `mov rax, [rip]` + `movq xmm0, rax` before this.
    //
    // The load keeps its own instruction - only its destination operand
    // changes - so a relocation bound to it stays bound.
    bool tryLoadDirectlyIntoFloat(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa || !ctx.builder)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        // LoadRegMem: [dst, base, valBits, offset].
        // LoadAmcRegMem: [dst, base, index, valBits, addrBits, scale, disp].
        uint8_t valBitsIndex = 0;
        switch (loadInst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
                valBitsIndex = 2;
                break;
            case MicroInstrOpcode::LoadAmcRegMem:
                valBitsIndex = 3;
                break;
            default:
                return false;
        }

        const MicroReg    vt       = loadOps[0].reg;
        const MicroOpBits loadBits = loadOps[valBitsIndex].opBits;
        if (!vt.isVirtualInt())
            return false;
        if (loadBits != MicroOpBits::B32 && loadBits != MicroOpBits::B64)
            return false;
        if (!valueHasSingleUse(*ctx.ssa, vt, loadRef))
            return false;

        // The move must sit right after the load: the vector register's
        // definition then moves up by one instruction, over nothing.
        const MicroInstrRef copyRef  = ctx.storage->findNextInstructionRef(loadRef);
        const MicroInstr*   copyInst = copyRef.isValid() ? ctx.storage->ptr(copyRef) : nullptr;
        if (!copyInst || copyInst->op != MicroInstrOpcode::LoadRegReg)
            return false;

        const MicroInstrOperand* copyOps = copyInst->ops(*ctx.operands);
        if (!copyOps || copyOps[1].reg != vt || copyOps[2].opBits != loadBits)
            return false;

        const MicroReg fd = copyOps[0].reg;
        if (!fd.isVirtualFloat() || ctx.builder->shouldPreserveVirtualCopy(fd))
            return false;

        // The load is rewritten where it stands, so its relocation survives;
        // the erased move must carry none of its own.
        if (ctx.isRelocated(copyRef) || !ctx.claimAll({loadRef, copyRef}, /*allowRelocated=*/true))
            return false;

        MicroInstrOperand newOps[8] = {};
        for (uint8_t idx = 0; idx < loadInst.numOperands; ++idx)
            newOps[idx] = loadOps[idx];
        newOps[0].reg = fd;
        ctx.emitRewrite(loadRef, loadInst.op, std::span{newOps, loadInst.numOperands}, /*allocNewBlock=*/false);
        ctx.emitErase(copyRef);
        return true;
    }
}

SWC_END_NAMESPACE();
