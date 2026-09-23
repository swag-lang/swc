#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

// Fold the copy that legacy SSE forces in front of every float binary operation
// into the operation itself.
//
// SSE only writes its result back into one of its inputs, so `c = a * b` is
// built as `c = a` followed by `c *= b`. The copy is not an artifact of register
// allocation - no allocator can remove it, because the destination genuinely has
// to start out holding one of the operands - and it lands squarely in hot loops:
// raytrace's sphere-intersection loop spends 14 of its 102 instructions on them.
//
// AVX's VEX encoding names all three registers, so the copy disappears.

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        bool hasThreeOperandForm(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::FloatAdd:
                case MicroOp::FloatSubtract:
                case MicroOp::FloatMultiply:
                case MicroOp::FloatDivide:
                case MicroOp::FloatMin:
                case MicroOp::FloatMax:
                case MicroOp::FloatAnd:
                case MicroOp::FloatXor:
                    return true;
                default:
                    return false;
            }
        }

        // The 128-bit packed integer operations the vectorizer emits are in the
        // same position as the scalar float ones: legacy SSE writes the result
        // back into one of its inputs, VEX names all three registers. Their
        // three-operand forms are AVX1, like the float ones, so one encoder
        // capability covers both.
        bool foldableIntoThreeOperand(const MicroOp op, const MicroOpBits opBits)
        {
            if (opBits == MicroOpBits::B128)
                return isVecMicroOp(op);
            return (opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64) && hasThreeOperandForm(op);
        }

        // The integer operations whose two-operand form reads its source from
        // memory. The forms that name a fixed register - a multiply through
        // rax, a shift by cl, the one-operand byte multiply - would hand the
        // encoder a legalization nothing runs any more, so they keep the load.
        bool hasIntegerMemoryOperandForm(const MicroOp op, const MicroOpBits opBits)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                    return true;
                case MicroOp::MultiplySigned:
                    return opBits != MicroOpBits::B8;
                default:
                    return false;
            }
        }

        bool isStandardIntBits(const MicroOpBits opBits)
        {
            return opBits == MicroOpBits::B8 || opBits == MicroOpBits::B16 || opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64;
        }

        // Whether the encoder takes the rewritten form as it stands. The
        // legalization sweep already ran, so a form it would have to rewrite
        // again has nobody left to rewrite it.
        bool encoderAcceptsAsIs(const Context& ctx, const MicroInstrOpcode op, std::span<const MicroInstrOperand> ops)
        {
            MicroInstr probe;
            probe.op          = op;
            probe.numOperands = static_cast<uint8_t>(ops.size());

            MicroConformanceIssue issue;
            return !ctx.encoder->queryConformanceIssue(issue, probe, ops.data());
        }

        // The consumer a reload folds into: a binary operation reading the
        // loaded register as its source, or a compare reading it on the left,
        // which is the side `cmp [mem], reg` names.
        bool isFoldableConsumer(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg loaded, const bool isFloat)
        {
            if (!ops)
                return false;
            if (inst.op == MicroInstrOpcode::OpBinaryRegReg && inst.numOperands >= 4)
                return ops[1].reg == loaded && ops[0].reg != loaded;
            if (isFloat && inst.op == MicroInstrOpcode::OpBinaryRegRegReg && inst.numOperands >= 5)
            {
                if (ops[2].reg != loaded)
                    return false;
                return (ops[0].reg == ops[1].reg && ops[0].reg != loaded) ||
                       (ops[0].reg == loaded && ops[1].reg != loaded);
            }
            if (!isFloat && inst.op == MicroInstrOpcode::CmpRegReg && inst.numOperands >= 3)
                return ops[0].reg == loaded && ops[1].reg != loaded;
            return false;
        }
    }

    bool tryFoldLoadIntoTest(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder)
            return false;
        const auto* load = inst.ops(*ctx.operands);
        if (!load || !load[0].reg.isInt() || !load[1].reg.isInt() ||
            load[1].reg.isInstructionPointer() || ctx.isPrivateFrameBase(load[0].reg))
            return false;
        const MicroInstrRef testRef = ctx.nextRef(ref);
        const MicroInstr*   test    = ctx.instruction(testRef);
        if (!test || test->op != MicroInstrOpcode::TestRegImm)
            return false;
        const auto* testOps = test->ops(*ctx.operands);
        if (!testOps || testOps[0].reg != load[0].reg || getNumBits(testOps[1].opBits) > getNumBits(load[2].opBits) ||
            !ctx.isRegDeadAfter(load[0].reg, ctx.instructionIndex + 1))
            return false;

        MicroInstrOperand rewritten[4] = {load[1], testOps[1], load[3], testOps[2]};
        MicroInstr        probe        = *test;
        probe.op                       = MicroInstrOpcode::TestMemImm;
        probe.numOperands              = 4;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, probe, rewritten) || !ctx.claimAll({ref, testRef}))
            return false;
        ctx.emitRewrite(ref, probe.op, rewritten);
        ctx.emitErase(testRef);
        return true;
    }

    bool tryFoldLoadIntoNarrowExtract(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder)
            return false;
        const auto* load = inst.ops(*ctx.operands);
        if (!load || !load[0].reg.isInt() || !load[1].reg.isInt() ||
            load[1].reg.isInstructionPointer() || ctx.isPrivateFrameBase(load[0].reg) ||
            (load[2].opBits != MicroOpBits::B32 && load[2].opBits != MicroOpBits::B64))
            return false;

        MicroInstrRef     extRef    = ctx.nextRef(ref);
        const MicroInstr* ext       = ctx.instruction(extRef);
        MicroInstrRef     shiftRef  = MicroInstrRef::invalid();
        uint64_t          shiftBits = 0;
        uint32_t          extIndex  = ctx.instructionIndex + 1;
        if (ext && ext->op == MicroInstrOpcode::OpBinaryRegImm)
        {
            const auto* shift = ext->ops(*ctx.operands);
            if (!shift || shift[0].reg != load[0].reg || shift[2].microOp != MicroOp::ShiftRight ||
                shift[3].hasWideImmediateValue() || shift[3].valueU64 >= getNumBits(shift[1].opBits) ||
                (shift[3].valueU64 & 7) != 0)
                return false;
            shiftBits = shift[3].valueU64;
            shiftRef  = extRef;
            extRef    = ctx.nextRef(extRef);
            ext       = ctx.instruction(extRef);
            ++extIndex;
        }
        if (!ext || ext->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* narrow = ext->ops(*ctx.operands);
        if (!narrow || narrow[1].reg != load[0].reg || !narrow[0].reg.isInt() || ctx.isPrivateFrameBase(narrow[0].reg) ||
            (narrow[2].opBits != MicroOpBits::B32 && narrow[2].opBits != MicroOpBits::B64) ||
            (narrow[3].opBits != MicroOpBits::B8 && narrow[3].opBits != MicroOpBits::B16 && narrow[3].opBits != MicroOpBits::B32) ||
            getNumBits(narrow[2].opBits) <= getNumBits(narrow[3].opBits) ||
            shiftBits + getNumBits(narrow[3].opBits) > getNumBits(load[2].opBits))
            return false;
        if (shiftRef.isValid())
        {
            const auto* shift = ctx.operandsFor(shiftRef);
            if (shiftBits + getNumBits(narrow[3].opBits) > getNumBits(shift[1].opBits) ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, extRef, ctx.builder))
                return false;
        }
        if (narrow[0].reg != load[0].reg && !ctx.isRegDeadAfter(load[0].reg, extIndex))
            return false;

        // Read the selected bytes at the original load's position. The x64
        // byte order turns an aligned right shift into a displacement.
        MicroInstrOperand rewritten[5] = {};
        rewritten[0]                   = narrow[0];
        rewritten[1]                   = load[1];
        rewritten[2]                   = narrow[2];
        rewritten[3]                   = narrow[3];
        rewritten[4].valueU64          = load[3].valueU64 + shiftBits / 8;
        MicroInstr probe               = inst;
        probe.op                       = MicroInstrOpcode::LoadZeroExtRegMem;
        probe.numOperands              = 5;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, probe, rewritten))
            return false;
        if (shiftRef.isValid() ? !ctx.claimAll({ref, shiftRef, extRef}) : !ctx.claimAll({ref, extRef}))
            return false;
        ctx.emitRewrite(ref, probe.op, rewritten, true);
        if (shiftRef.isValid())
            ctx.emitErase(shiftRef);
        ctx.emitErase(extRef);
        return true;
    }

    // A scalar integer conversion only defines the low f32/f64 lane. The IR
    // therefore models it as reading the destination and normally clears that
    // register first. At an immediate scalar ABI return the upper lanes are
    // unobservable, so the clear is pure encoding overhead.
    bool tryEraseScalarReturnConversionClear(Context& ctx, const MicroInstrRef clearRef, const MicroInstr& clearInst)
    {
        if (ctx.isClaimed(clearRef) || clearInst.op != MicroInstrOpcode::ClearReg ||
            !ctx.passContext || !ctx.passContext->usesFloatReturnRegOnRet)
            return false;
        const auto* clear = clearInst.ops(*ctx.operands);
        if (!clear || clear[0].reg != ctx.floatReturn ||
            (clear[1].opBits != MicroOpBits::B32 && clear[1].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef convertRef = ctx.nextRef(clearRef);
        const MicroInstr*   convert    = ctx.instruction(convertRef);
        const auto*         convertOps = convert ? convert->ops(*ctx.operands) : nullptr;
        if (!convert || convert->op != MicroInstrOpcode::OpBinaryRegReg || !convertOps ||
            convertOps[0].reg != clear[0].reg || !convertOps[1].reg.isInt() ||
            convertOps[2].opBits != clear[1].opBits ||
            (convertOps[3].microOp != MicroOp::ConvertIntToFloat && convertOps[3].microOp != MicroOp::ConvertInt64ToFloat32))
            return false;

        const MicroInstrRef retRef = ctx.nextRef(convertRef);
        const MicroInstr*   ret    = ctx.instruction(retRef);
        if (!ret || ret->op != MicroInstrOpcode::Ret || !ctx.claimAll({clearRef, convertRef}))
            return false;

        ctx.emitErase(clearRef);
        return true;
    }

    // Fold an operand's reload into the operation that consumes it.
    //
    // x86 arithmetic can read one operand straight from memory, but the
    // encoder only ever built the register form, so every value coming out of a
    // spill slot cost a separate load. raytrace's inner loop reloads twenty-two
    // times; each fold turns two instructions into one and frees the scratch
    // register the value was staged in. The integer side covers the same
    // shape for the operations x64 reads from memory, and a compare whose
    // left operand is the reload.
    bool tryFoldLoadIntoBinary(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        const bool indexed = loadInst.op == MicroInstrOpcode::LoadAmcRegMem;
        if ((!indexed && loadInst.op != MicroInstrOpcode::LoadRegMem) || loadInst.numOperands < (indexed ? 7 : 4))
            return false;

        const MicroInstrOperand* loadOps = ctx.operandsFor(loadRef);
        if (!loadOps)
            return false;

        const MicroReg loaded  = loadOps[0].reg;
        const MicroReg base    = loadOps[1].reg;
        const MicroReg index   = indexed ? loadOps[2].reg : MicroReg::invalid();
        const bool     isFloat = loaded.isFloat();
        if ((!isFloat && !loaded.isAnyInt()) || base.isFloat() || !base.isValid() ||
            (indexed && (!index.isValid() || index.isFloat())))
            return false;

        // A RIP-relative load carries the constant's relocation. The folded
        // arithmetic instruction can carry it instead, but only when this is
        // the one ordinary rel32 relocation the memory form expects.
        MicroRelocation* loadRelocation = nullptr;
        if (base.isInstructionPointer())
        {
            if (!isFloat || !ctx.builder)
                return false;
            for (MicroRelocation& relocation : ctx.builder->codeRelocations())
            {
                if (relocation.instructionRef != loadRef)
                    continue;
                if (loadRelocation || relocation.form != MicroRelocation::Form::Relative32)
                    return false;
                loadRelocation = &relocation;
            }
            if (!loadRelocation)
                return false;
        }

        // The integer rewrite is probed against the encoder before it lands.
        if (!isFloat && !ctx.encoder)
            return false;

        const MicroOpBits opBits = loadOps[indexed ? 3 : 2].opBits;
        if (isFloat ? (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64) : !isStandardIntBits(opBits))
            return false;

        constexpr uint32_t kMaxScan = 12;

        MicroInstrRef     opRef   = ctx.nextRef(loadRef);
        const MicroInstr* opInst  = nullptr;
        uint32_t          opIndex = ctx.instructionIndex + 1;
        for (uint32_t step = 0; step < kMaxScan; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate)
                return false;

            if (isFoldableConsumer(*candidate, ctx.operandsFor(opRef), loaded, isFloat))
            {
                opInst = candidate;
                break;
            }

            if (candidate->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrDef& info = MicroInstr::info(candidate->op);
            if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            // The read moves later, so anything that could change what it sees
            // stops the fold: a write to the address register, and any store at
            // all - this pass has no aliasing information.
            if (info.flags.has(MicroInstrFlagsE::WritesMemory))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == loaded || reg == base || (indexed && reg == index))
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == loaded)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
            ++opIndex;
        }

        if (!opInst)
            return false;

        if (loadRelocation)
            for (const MicroRelocation& relocation : ctx.builder->codeRelocations())
                if (&relocation != loadRelocation && relocation.instructionRef == opRef)
                    return false;

        const MicroInstrOperand* consumerOps = ctx.operandsFor(opRef);
        if (!consumerOps)
            return false;

        if (opInst->op == MicroInstrOpcode::CmpRegReg)
        {
            // The register only existed to carry the loaded value across; if
            // anything reads it afterwards it has to keep existing.
            if (!regIsDeadAfter(ctx, opRef, loaded) && !ctx.isRegDeadAfter(loaded, opIndex))
                return false;
            if (indexed)
                return false;
            if (consumerOps[2].opBits != opBits || !consumerOps[1].reg.isAnyInt())
                return false;

            MicroInstrOperand newOps[4] = {};
            newOps[0].reg               = base;
            newOps[1].reg               = consumerOps[1].reg;
            newOps[2].opBits            = opBits;
            newOps[3].valueU64          = loadOps[3].valueU64;
            if (!encoderAcceptsAsIs(ctx, MicroInstrOpcode::CmpMemReg, std::span{newOps, 4}))
                return false;
            if (!ctx.claimAll({loadRef, opRef}))
                return false;

            ctx.emitRewrite(opRef, MicroInstrOpcode::CmpMemReg, std::span{newOps, 4}, true);
            ctx.emitErase(loadRef);
            return true;
        }

        const bool        threeOperand = opInst->op == MicroInstrOpcode::OpBinaryRegRegReg;
        const MicroOpBits consumerBits = consumerOps[threeOperand ? 3 : 2].opBits;
        const MicroOp     op           = consumerOps[threeOperand ? 4 : 3].microOp;
        if (consumerBits != opBits)
            return false;
        if (isFloat ? (!hasThreeOperandForm(op) || !consumerOps[0].reg.isFloat()) : (!hasIntegerMemoryOperandForm(op, opBits) || !consumerOps[0].reg.isAnyInt()))
            return false;
        // FloatAnd/FloatXor are packed 128-bit instructions even when the
        // scalar value is 32 or 64 bits. A scalar constant allocation only
        // guarantees those 4 or 8 bytes, so reading it as a memory operand can
        // cross the allocation boundary. Keep the scalar load for those ops.
        if (loadRelocation && (op == MicroOp::FloatAnd || op == MicroOp::FloatXor))
            return false;

        MicroInstrRef sourceCopyRef = MicroInstrRef::invalid();
        if (threeOperand && consumerOps[0].reg == loaded)
        {
            // Allocation can preserve the original destination in a temporary,
            // load the constant over the destination, then use both in a VEX
            // operation. Removing the load restores the original destination;
            // the temporary copy and the third operand then both disappear.
            sourceCopyRef                     = ctx.previousRef(loadRef);
            const MicroInstr*        copyInst = ctx.instruction(sourceCopyRef);
            const MicroInstrOperand* copyOps  = copyInst ? copyInst->ops(*ctx.operands) : nullptr;
            if (!copyInst || copyInst->op != MicroInstrOpcode::LoadRegReg || !copyOps ||
                copyOps[0].reg != consumerOps[1].reg || copyOps[1].reg != loaded || copyOps[2].opBits != opBits)
                return false;
            const MicroReg copied = copyOps[0].reg;
            if (!regIsDeadAfter(ctx, opRef, copied) && !ctx.isRegDeadAfter(copied, opIndex))
                return false;
        }
        else if (!regIsDeadAfter(ctx, opRef, loaded) && !ctx.isRegDeadAfter(loaded, opIndex))
        {
            return false;
        }

        MicroInstrOpcode  rewrittenOp = MicroInstrOpcode::OpBinaryRegMem;
        MicroInstrOperand newOps[8]   = {};
        uint32_t          numOps       = 5;
        newOps[0].reg                  = consumerOps[0].reg;
        newOps[1].reg                  = base;
        if (indexed)
        {
            rewrittenOp        = MicroInstrOpcode::OpBinaryRegAmcMem;
            numOps             = 8;
            newOps[2].reg      = index;
            newOps[3].opBits   = opBits;
            newOps[4]          = loadOps[4];
            newOps[5]          = loadOps[5];
            newOps[6]          = loadOps[6];
            newOps[7].microOp  = op;
        }
        else
        {
            newOps[2].opBits   = opBits;
            newOps[3].microOp  = op;
            newOps[4].valueU64 = loadOps[3].valueU64;
        }
        const std::span rewrittenOps(newOps, numOps);
        if (!isFloat && !encoderAcceptsAsIs(ctx, rewrittenOp, rewrittenOps))
            return false;
        MicroInstrRef clearRef = MicroInstrRef::invalid();
        if (isFloat)
        {
            const MicroInstrRef      previousRef = ctx.previousRef(loadRef);
            const MicroInstr*        previous    = ctx.instruction(previousRef);
            const MicroInstrOperand* clearOps   = previous ? previous->ops(*ctx.operands) : nullptr;
            if (previous && previous->op == MicroInstrOpcode::ClearReg && clearOps &&
                clearOps[0].reg == loaded && clearOps[1].opBits == opBits)
                clearRef = previousRef;
        }

        if (sourceCopyRef.isValid())
        {
            if (!ctx.claimAll({loadRef, opRef, sourceCopyRef}))
                return false;
        }
        else if (clearRef.isValid())
        {
            if (!ctx.claimAll({loadRef, opRef, clearRef}))
                return false;
        }
        else if (!ctx.claimAll({loadRef, opRef}))
        {
            return false;
        }

        if (loadRelocation)
            loadRelocation->instructionRef = opRef;
        ctx.emitRewrite(opRef, rewrittenOp, rewrittenOps, true);
        ctx.emitErase(loadRef);
        if (sourceCopyRef.isValid())
            ctx.emitErase(sourceCopyRef);
        if (clearRef.isValid())
            ctx.emitErase(clearRef);
        return true;
    }

    // `x * x` reads the same slot twice: once to load the destination, once as
    // the operation's memory operand. Naming the register on both sides drops
    // one of the two reads and costs nothing - no extra instruction, no extra
    // dependency, since the value is already in the register the operation is
    // about to write.
    bool tryUseSelfOperandForFloatBinary(Context& ctx, const MicroInstrRef opRef, const MicroInstr& opInst)
    {
        if (opInst.op != MicroInstrOpcode::OpBinaryRegMem || opInst.numOperands < 5)
            return false;

        const MicroInstrOperand* ops = ctx.operandsFor(opRef);
        if (!ops)
            return false;

        const MicroReg dst  = ops[0].reg;
        const MicroReg base = ops[1].reg;
        if (!dst.isFloat() || !base.isValid() || base.isInstructionPointer())
            return false;

        const MicroOpBits opBits = ops[2].opBits;
        if (!hasThreeOperandForm(ops[3].microOp))
            return false;

        const uint64_t offset = ops[4].valueU64;

        // Walk back to whatever last wrote the destination. Only a load of this
        // very address means the register already holds the memory operand;
        // running out of budget before finding that write proves nothing.
        constexpr uint32_t kMaxScan = 12;

        bool          loadFound = false;
        MicroInstrRef cursor    = ctx.previousRef(opRef);
        for (uint32_t step = 0; step < kMaxScan && !loadFound; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(cursor);
            if (!candidate)
                return false;

            const MicroInstrDef& info = MicroInstr::info(candidate->op);
            if (candidate->op == MicroInstrOpcode::Label ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::WritesMemory))
                return false;

            if (candidate->op == MicroInstrOpcode::LoadRegMem && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* loadOps = ctx.operandsFor(cursor);
                if (loadOps && loadOps[0].reg == dst)
                {
                    if (loadOps[1].reg != base || loadOps[3].valueU64 != offset || loadOps[2].opBits != opBits)
                        return false;
                    loadFound = true;
                    continue;
                }
            }

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == base)
                    return false;
            }

            cursor = ctx.previousRef(cursor);
        }

        if (!loadFound || !ctx.claimAll({opRef}))
            return false;

        MicroInstrOperand newOps[4] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = dst;
        newOps[2].opBits            = opBits;
        newOps[3].microOp           = ops[3].microOp;

        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegReg, std::span{newOps, 4});
        return true;
    }

    // An integer multiply by a constant names its destination separately too:
    //
    //     mov rax, rcx ; imul rax, 16843010    ->    imul rax, rcx, 16843010
    //
    // The copy the two-address form needs goes, as clang's `imul rax, rdx,
    // 16843010` shows in every magic-number division.
    bool tryFoldCopyIntoIntegerMultiply(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        constexpr uint32_t K_MAX_SCAN = 8;

        if (copyInst.op != MicroInstrOpcode::LoadRegReg || copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;
        const MicroOpBits copyBits = copyOps[2].opBits;
        if (copyBits != MicroOpBits::B32 && copyBits != MicroOpBits::B64)
            return false;

        const MicroReg dst = copyOps[0].reg;
        const MicroReg src = copyOps[1].reg;
        if (!dst.isInt() || !src.isInt() || dst == src || ctx.isPrivateFrameBase(dst) || ctx.isPrivateFrameBase(src))
            return false;

        // The multiply that consumes the copy, with nothing in between that
        // touches either register.
        MicroInstrRef     opRef  = ctx.nextRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < K_MAX_SCAN; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate || candidate->op == MicroInstrOpcode::Label)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegImm && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == dst)
                {
                    opInst = candidate;
                    break;
                }
            }

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
        }

        if (!opInst || ctx.isClaimed(opRef))
            return false;
        const MicroInstrOperand* mulOps = ctx.operandsFor(opRef);
        if (!mulOps || mulOps[2].microOp != MicroOp::MultiplySigned || mulOps[1].opBits != copyBits ||
            mulOps[3].hasWideImmediateValue())
            return false;

        // The three-operand form takes a signed dword immediate.
        const uint64_t value = mulOps[3].valueU64;
        const auto     signedValue = static_cast<int64_t>(copyBits == MicroOpBits::B32 ? static_cast<int64_t>(static_cast<int32_t>(value)) : static_cast<int64_t>(value));
        if (signedValue < INT32_MIN || signedValue > INT32_MAX)
            return false;

        if (!ctx.claimAll({copyRef, opRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = src;
        newOps[2].opBits            = copyBits;
        newOps[3].microOp           = MicroOp::MultiplySigned;
        newOps[4].valueU64          = value;
        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegImm, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }

    // The result of a multiply by a constant can be named where it is wanted,
    // the other way round:
    //
    //     imul rcx, 16843010 ; mov rax, rcx    ->    imul rax, rcx, 16843010
    //
    // The multiplied register must die at the copy, since it no longer holds
    // the product afterwards.
    bool tryFoldMultiplyIntoResultCopy(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        constexpr uint32_t K_MAX_SCAN = 8;

        if (copyInst.op != MicroInstrOpcode::LoadRegReg || copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;
        const MicroOpBits copyBits = copyOps[2].opBits;
        if (copyBits != MicroOpBits::B32 && copyBits != MicroOpBits::B64)
            return false;

        const MicroReg dst = copyOps[0].reg;
        const MicroReg src = copyOps[1].reg;
        if (!dst.isInt() || !src.isInt() || dst == src || ctx.isPrivateFrameBase(dst) || ctx.isPrivateFrameBase(src))
            return false;
        // The product only reaches the copy: anything else still reading the
        // multiplied register would read the value it no longer gets.
        if (!ctx.isRegDeadAfterCurrent(src))
            return false;

        // The multiply that feeds the copy, with nothing in between that
        // touches either register.
        MicroInstrRef     mulRef  = ctx.previousRef(copyRef);
        const MicroInstr* mulInst = nullptr;
        for (uint32_t step = 0; step < K_MAX_SCAN; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(mulRef);
            if (!candidate || candidate->op == MicroInstrOpcode::Label)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegImm && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(mulRef);
                if (candidateOps && candidateOps[0].reg == src)
                {
                    mulInst = candidate;
                    break;
                }
            }

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst || reg == src)
                    return false;
            }

            mulRef = ctx.previousRef(mulRef);
        }

        if (!mulInst || ctx.isClaimed(mulRef))
            return false;
        const MicroInstrOperand* mulOps = ctx.operandsFor(mulRef);
        if (!mulOps || mulOps[2].microOp != MicroOp::MultiplySigned || mulOps[1].opBits != copyBits ||
            mulOps[3].hasWideImmediateValue())
            return false;

        // The three-operand form takes a signed dword immediate.
        const uint64_t value       = mulOps[3].valueU64;
        const auto     signedValue = copyBits == MicroOpBits::B32 ? static_cast<int64_t>(static_cast<int32_t>(value)) : static_cast<int64_t>(value);
        if (signedValue < INT32_MIN || signedValue > INT32_MAX)
            return false;

        if (!ctx.claimAll({mulRef, copyRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = src;
        newOps[2].opBits            = copyBits;
        newOps[3].microOp           = MicroOp::MultiplySigned;
        newOps[4].valueU64          = value;
        ctx.emitRewrite(mulRef, MicroInstrOpcode::OpBinaryRegRegImm, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }

    // A three-operand float operation names its destination freely, so a
    // result computed into a temporary and then copied can be computed where
    // it is wanted:
    //
    //     vmaxss xmm3, xmm0, xmm1 ; movss xmm0, xmm3    ->    vmaxss xmm0, xmm0, xmm1
    //
    // The temporary must die at the copy. Both sources are read before the
    // destination is written, so the destination may be one of them.
    bool tryFoldFloatBinaryIntoResultCopy(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        constexpr uint32_t K_MAX_SCAN = 8;

        if (copyInst.op != MicroInstrOpcode::LoadRegReg || copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;
        const MicroReg    dst      = copyOps[0].reg;
        const MicroReg    src      = copyOps[1].reg;
        const MicroOpBits copyBits = copyOps[2].opBits;
        if (!dst.isFloat() || !src.isFloat() || dst == src || !ctx.isRegDeadAfterCurrent(src))
            return false;

        // The operation that feeds the copy, with nothing in between that
        // touches either register.
        MicroInstrRef     opRef  = ctx.previousRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < K_MAX_SCAN; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate || candidate->op == MicroInstrOpcode::Label)
                return false;

            if ((candidate->op == MicroInstrOpcode::OpBinaryRegRegReg && candidate->numOperands >= 5) ||
                (candidate->op == MicroInstrOpcode::OpBinaryRegReg && candidate->numOperands >= 4))
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == src)
                {
                    opInst = candidate;
                    break;
                }
            }

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst || reg == src)
                    return false;
            }

            opRef = ctx.previousRef(opRef);
        }

        if (!opInst || ctx.isClaimed(opRef))
            return false;
        const MicroInstrOperand* opOps = ctx.operandsFor(opRef);
        if (!opOps)
            return false;

        // The two-operand form names its destination as its own left source:
        // `xmm1 *= xmm0` spelled out is `xmm1 = xmm1 * xmm0`. Widening it here
        // is what lets the copy go, since the temporary is the destination.
        MicroInstrOperand newOps[5] = {};
        if (opInst->op == MicroInstrOpcode::OpBinaryRegReg)
        {
            if (opOps[2].opBits != copyBits || !foldableIntoThreeOperand(opOps[3].microOp, copyBits) ||
                !opOps[0].reg.isFloat() || !opOps[1].reg.isFloat())
                return false;
            if (!ctx.encoder || !ctx.encoder->supportsNonDestructiveFloatBinary())
                return false;
            newOps[1].reg    = opOps[0].reg;
            newOps[2].reg    = opOps[1].reg;
            newOps[3].opBits = opOps[2].opBits;
            newOps[4]        = opOps[3];
        }
        else
        {
            if (opOps[3].opBits != copyBits || !opOps[1].reg.isFloat() || !opOps[2].reg.isFloat())
                return false;
            std::ranges::copy(std::span{opOps, 5}, newOps);
        }

        if (!ctx.claimAll({opRef, copyRef}))
            return false;

        newOps[0].reg = dst;
        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegReg, std::span{newOps, 5}, /*allocNewBlock=*/true);
        ctx.emitErase(copyRef);
        return true;
    }

    // Constant unsigned division can leave its magic multiply and logical
    // shift in a temporary immediately copied to the return register:
    //
    //     imul T, R        imul R, T
    //     shr  T, K   ->   shr  R, K
    //     mov  R, T
    //
    // The multiply is commutative, so the register holding the magic constant
    // can become the product and final result. A narrowing copy may disappear
    // only when the logical shift itself proves the upper dword is zero.
    bool tryFoldMultiplyShiftResultCopy(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef) || !ctx.encoder || copyInst.op != MicroInstrOpcode::LoadRegReg)
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64) ||
            !ctx.isRegDeadAfterCurrent(copy[1].reg))
            return false;
        const MicroReg dst = copy[0].reg;
        const MicroReg src = copy[1].reg;

        const MicroInstrRef shiftRef = ctx.previousRef(copyRef);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        const auto*         shiftOps = shift ? shift->ops(*ctx.operands) : nullptr;
        if (!shift || shift->op != MicroInstrOpcode::OpBinaryRegImm || !shiftOps ||
            shiftOps[0].reg != src || shiftOps[2].microOp != MicroOp::ShiftRight || shiftOps[3].hasWideImmediateValue() ||
            (shiftOps[1].opBits != MicroOpBits::B32 && shiftOps[1].opBits != MicroOpBits::B64))
            return false;
        if (copy[2].opBits != shiftOps[1].opBits &&
            !(copy[2].opBits == MicroOpBits::B32 && shiftOps[1].opBits == MicroOpBits::B64 && shiftOps[3].valueU64 >= 32))
            return false;

        const MicroInstrRef multiplyRef = ctx.previousRef(shiftRef);
        const MicroInstr*   multiply    = ctx.instruction(multiplyRef);
        const auto*         multiplyOps = multiply ? multiply->ops(*ctx.operands) : nullptr;
        if (!multiply || multiply->op != MicroInstrOpcode::OpBinaryRegReg || !multiplyOps ||
            multiplyOps[0].reg != src || multiplyOps[1].reg != dst ||
            multiplyOps[2].opBits != shiftOps[1].opBits || multiplyOps[3].microOp != MicroOp::MultiplySigned)
            return false;

        MicroInstrOperand rewrittenMultiply[4] = {multiplyOps[0], multiplyOps[1], multiplyOps[2], multiplyOps[3]};
        rewrittenMultiply[0].reg               = dst;
        rewrittenMultiply[1].reg               = src;
        MicroInstrOperand rewrittenShift[4]    = {shiftOps[0], shiftOps[1], shiftOps[2], shiftOps[3]};
        rewrittenShift[0].reg                  = dst;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, *multiply, rewrittenMultiply) ||
            ctx.encoder->queryConformanceIssue(issue, *shift, rewrittenShift) ||
            !ctx.claimAll({multiplyRef, shiftRef, copyRef}))
            return false;

        ctx.emitRewrite(multiplyRef, multiply->op, rewrittenMultiply);
        ctx.emitRewrite(shiftRef, shift->op, rewrittenShift);
        ctx.emitErase(copyRef);
        return true;
    }

    // The same fold for a packed shift by an immediate. A rotate needs its
    // source twice - once shifted left, once right - so the vectorizer copies
    // it before each destructive shift, and the register allocator was giving
    // one of those copies a stack home rather than a register: in a vectorized
    // ChaCha20 round loop that was four stores and four reloads per iteration,
    // on the dependency chain. VEX names the destination separately, so the
    // copy disappears and the pressure that caused the spill with it.
    bool tryFoldCopyIntoVecShiftImm(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (!ctx.encoder || !ctx.encoder->supportsNonDestructiveFloatBinary())
            return false;
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps || copyOps[2].opBits != MicroOpBits::B128)
            return false;

        const MicroReg dst = copyOps[0].reg;
        const MicroReg src = copyOps[1].reg;
        if (!dst.isFloat() || !src.isFloat() || dst == src)
            return false;

        constexpr uint32_t kMaxScan = 12;

        MicroInstrRef     opRef  = ctx.nextRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < kMaxScan; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegImm && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == dst)
                {
                    opInst = candidate;
                    break;
                }
            }

            if (candidate->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
        }

        if (!opInst)
            return false;

        const MicroInstrOperand* shiftOps = ctx.operandsFor(opRef);
        if (!shiftOps || shiftOps[1].opBits != MicroOpBits::B128)
            return false;

        const MicroOp shiftOp = shiftOps[2].microOp;
        if (shiftOp != MicroOp::VecShiftLeft32 && shiftOp != MicroOp::VecShiftRight32)
            return false;

        const uint64_t shiftValue = shiftOps[3].valueU64;
        if (shiftValue > 31)
            return false;

        if (!ctx.claimAll({copyRef, opRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = src;
        newOps[2].opBits            = MicroOpBits::B128;
        newOps[3].microOp           = shiftOp;
        newOps[4].valueU64          = shiftValue;

        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegImm, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }

    bool tryFoldCopyIntoFloatBinary(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (!ctx.encoder || !ctx.encoder->supportsNonDestructiveFloatBinary())
            return false;
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;

        const MicroReg dst  = copyOps[0].reg;
        const MicroReg src1 = copyOps[1].reg;
        if (!dst.isFloat() || !src1.isFloat())
            return false;

        // The operation is rarely the next instruction: the second operand
        // usually has to be loaded first. Scan ahead for it, but only across
        // instructions that leave both registers alone, and stop at anything
        // control flow can enter from elsewhere - reaching the operation
        // without having run the copy would find a destination that never
        // received src1.
        constexpr uint32_t kMaxScan = 12;

        MicroInstrRef     opRef  = ctx.nextRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < kMaxScan; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegReg)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == dst)
                {
                    opInst = candidate;
                    break;
                }
            }

            if (candidate->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            // A write to either register breaks the chain, and so does a read of
            // the destination: after the fold it no longer holds src1 there.
            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src1)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
        }

        if (!opInst || opInst->numOperands < 4)
            return false;

        const MicroInstrOperand* binOps = ctx.operandsFor(opRef);
        if (!binOps)
            return false;

        if (binOps[0].reg != dst)
            return false;

        const MicroReg src2 = binOps[1].reg;
        if (!src2.isFloat())
            return false;

        // `dst op= dst` reads the destination as its second source. Folding the
        // copy away would make that read see the pre-copy value instead of src1,
        // so this shape stays as it is.
        if (src2 == dst)
            return false;

        const MicroOpBits opBits = binOps[2].opBits;
        if (opBits != copyOps[2].opBits)
            return false;
        if (!foldableIntoThreeOperand(binOps[3].microOp, opBits))
            return false;

        if (!ctx.claimAll({copyRef, opRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = src1;
        newOps[2].reg               = src2;
        newOps[3].opBits            = opBits;
        newOps[4].microOp           = binOps[3].microOp;

        // Five operands where the original had four, so the rewrite needs a
        // fresh operand block.
        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegReg, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }
}

SWC_END_NAMESPACE();
