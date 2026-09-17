#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runInstCombinePass(MicroBuilder& builder)
    {
        MicroInstructionCombinePass pass;
        MicroPassManager            passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    bool firstBinaryRegImm(const MicroBuilder& builder, MicroOp& outOp, uint64_t& outImm)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                return false;
            outOp  = ops[2].microOp;
            outImm = ops[3].valueU64;
            return true;
        }
        return false;
    }
}

// add v, 0  -> erased when v is dead.
SWC_TEST_BEGIN(InstCombine_Identity_AddZero_Erased)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{0}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A scalar read from immutable constant storage consumes the address relocation
// directly and advances both the host address and the native segment offset.
SWC_TEST_BEGIN(InstCombine_ConstantAddressLoad_FoldsToRip)
{
    constexpr MicroReg address = MicroReg::virtualIntReg(1);
    constexpr MicroReg value   = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    std::array source{
        std::byte{0x10},
        std::byte{0x20},
        std::byte{0x30},
        std::byte{0x40},
        std::byte{0x50},
        std::byte{0x60},
        std::byte{0x70},
        std::byte{0x80},
    };
    std::array           dims{source.size()};
    const TypeRef        arrayTypeRef = ctx.typeMgr().addType(TypeInfo::makeArray(std::span<uint64_t>{dims}, ctx.typeMgr().typeU8()));
    const ConstantRef    cstRef       = ctx.cstMgr().addConstant(ctx, ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, std::span{source.data(), source.size()}));
    const ConstantValue& constant     = ctx.cstMgr().get(cstRef);
    const uint64_t       addressValue = reinterpret_cast<uint64_t>(constant.getArray().data());

    DataSegmentRef sourceRef;
    if (!ctx.cstMgr().resolveConstantDataSegmentRef(sourceRef, cstRef, constant.getArray().data()))
        return Result::Error;

    builder.emitLoadRegPtrReloc(address, addressValue, cstRef);
    builder.emitLoadRegMem(value, address, 2, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    bool foundFoldedLoad = false;
    for (const MicroRelocation& relocation : builder.codeRelocations())
    {
        const MicroInstr* inst = builder.instructions().ptr(relocation.instructionRef);
        if (!inst || inst->op != MicroInstrOpcode::LoadRegMem)
            continue;

        const MicroInstrOperand* ops = inst->ops(builder.operands());
        if (!ops || !ops[1].reg.isInstructionPointer() || ops[3].valueU64 != 0)
            return Result::Error;
        if (relocation.kind != MicroRelocation::Kind::ConstantAddress || relocation.form != MicroRelocation::Form::Relative32)
            return Result::Error;
        if (relocation.targetAddress != addressValue + 2 || relocation.constantShard != sourceRef.shardIndex || relocation.constantOffset != sourceRef.offset + 2)
            return Result::Error;
        foundFoldedLoad = true;
    }

    return foundFoldedLoad ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_RelocatedLoad_UsesExactTargetAndLiveMemory)
{
    enum class Case
    {
        Same,
        Kind,
        Address,
        Symbol,
        Constant,
        Shard,
        Offset,
        Width,
        Store,
        Call,
        Overwritten,
        Label,
    };
    SymbolFunction firstSymbol(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    SymbolFunction secondSymbol(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    for (const Case test : {Case::Same, Case::Kind, Case::Address, Case::Symbol, Case::Constant, Case::Shard, Case::Offset, Case::Width, Case::Store, Case::Call, Case::Overwritten, Case::Label})
        for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
        {
            constexpr MicroReg first  = MicroReg::virtualIntReg(1);
            constexpr MicroReg second = MicroReg::virtualIntReg(2);
            constexpr MicroReg base   = MicroReg::intReg(3);
            MicroBuilder       builder(ctx);
            builder.emitLoadRegMem(first, MicroReg::instructionPointer(), 0, bits);
            MicroRelocation relocation;
            const bool      constantTarget = test == Case::Constant || test == Case::Shard || test == Case::Offset;
            relocation.kind                = constantTarget ? MicroRelocation::Kind::ConstantAddress : MicroRelocation::Kind::GlobalInitAddress;
            if (constantTarget)
            {
                relocation.constantRef    = ConstantRef(0);
                relocation.constantShard  = 0;
                relocation.constantOffset = 8;
            }
            if (test == Case::Symbol)
            {
                relocation.kind         = MicroRelocation::Kind::LocalFunctionAddress;
                relocation.targetSymbol = &firstSymbol;
            }
            relocation.form           = MicroRelocation::Form::Relative32;
            relocation.targetAddress  = 8;
            relocation.instructionRef = builder.instructions().findPreviousInstructionRef(MicroInstrRef::invalid());
            builder.addRelocation(relocation);
            const MicroInstrRef firstRef = relocation.instructionRef;

            if (test == Case::Store)
                builder.emitLoadMemReg(base, 0, first, bits);
            else if (test == Case::Call)
                builder.emitCallReg(MicroReg::intReg(0), CallConvKind::Swag);
            else if (test == Case::Overwritten)
                builder.emitLoadRegImm(first, ApInt(7, 64), bits);
            else if (test == Case::Label)
                builder.placeLabel(builder.createLabel());

            builder.emitLoadRegMem(second, MicroReg::instructionPointer(), 0, test == Case::Width ? (bits == MicroOpBits::B32 ? MicroOpBits::B64 : MicroOpBits::B32) : bits);
            relocation.instructionRef     = builder.instructions().findPreviousInstructionRef(MicroInstrRef::invalid());
            const MicroInstrRef secondRef = relocation.instructionRef;
            switch (test)
            {
                case Case::Kind: relocation.kind = MicroRelocation::Kind::GlobalZeroAddress; break;
                case Case::Address: relocation.targetAddress = 16; break;
                case Case::Symbol: relocation.targetSymbol = &secondSymbol; break;
                case Case::Constant: relocation.constantRef = ConstantRef(1); break;
                case Case::Shard: relocation.constantShard = 1; break;
                case Case::Offset: relocation.constantOffset = 16; break;
                default: break;
            }
            builder.addRelocation(relocation);
            builder.emitLoadMemReg(base, 8, first, bits);
            builder.emitLoadMemReg(base, 16, second, bits);
            builder.emitRet();
            SWC_RESULT(runInstCombinePass(builder));
            const MicroInstr* folded = builder.instructions().ptr(secondRef);
            if (!folded || folded->op != (test == Case::Same ? MicroInstrOpcode::LoadRegReg : MicroInstrOpcode::LoadRegMem))
                return Result::Error;
            bool firstRelocation  = false;
            bool secondRelocation = false;
            for (const MicroRelocation& current : builder.codeRelocations())
            {
                firstRelocation |= current.instructionRef == firstRef;
                secondRelocation |= current.instructionRef == secondRef;
            }
            if (!firstRelocation || secondRelocation != (test != Case::Same))
                return Result::Error;
        }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_ForwardingCacheKeepsClaimedLoadsOut)
{
    constexpr MicroReg base = MicroReg::intReg(8);
    for (const bool firstClaimed : {false, true})
    {
        MicroBuilder                 builder(ctx);
        std::array<MicroInstrRef, 3> loads;
        for (uint32_t i = 0; i < loads.size(); ++i)
        {
            builder.emitLoadRegMem(MicroReg::virtualIntReg(i + 1), base, 0, MicroOpBits::B64);
            loads[i] = builder.instructions().lastInstructionRef();
        }
        builder.emitRet();

        MicroSsaState ssa;
        ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
        InstructionCombine::Context context;
        context.builder  = &builder;
        context.storage  = &builder.instructions();
        context.operands = &builder.operands();
        context.ssa      = &ssa;
        // A per-instruction pattern may already own the first load when the
        // whole-function forwarding scan begins.
        if (firstClaimed && !context.claimAll({loads[0]}))
            return Result::Error;
        InstructionCombine::runStoreToLoadForwarding(context);

        if (context.actions.size() != (firstClaimed ? 1 : 2))
            return Result::Error;
        for (uint32_t i = 0; i < context.actions.size(); ++i)
        {
            const auto&    action    = context.actions[i];
            const uint32_t loadIndex = i + (firstClaimed ? 2 : 1);
            if (action.ref != loads[loadIndex] || action.newOp != MicroInstrOpcode::LoadRegReg || action.ops[0].reg != MicroReg::virtualIntReg(loadIndex + 1) || action.ops[1].reg != MicroReg::virtualIntReg(firstClaimed ? 2 : 1))
                return Result::Error;
        }
        if (context.isClaimed(loads[0]) != firstClaimed || context.isClaimed(loads[1]) == firstClaimed || !context.isClaimed(loads[2]))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_ForwardingCacheKeepsSurvivingProducers)
{
    constexpr MicroReg base   = MicroReg::intReg(8);
    constexpr MicroReg first  = MicroReg::intReg(10);
    constexpr MicroReg second = MicroReg::intReg(11);
    for (const bool overlappingStore : {false, true})
    {
        MicroBuilder builder(ctx);
        for (uint32_t i = 0; i < 12; ++i)
            builder.emitLoadMemReg(base, i, i % 2 == 0 ? first : second, MicroOpBits::B8);
        // Cross the cache's inline capacity, then remove either alternating
        // producers or eight consecutive overlapping byte entries.
        if (overlappingStore)
            builder.emitLoadMemReg(base, 2, MicroReg::intReg(12), MicroOpBits::B64);
        else
            builder.emitClearReg(first, MicroOpBits::B64);
        std::array<MicroInstrRef, 12> loads;
        for (uint32_t i = 0; i < loads.size(); ++i)
        {
            builder.emitLoadRegMem(MicroReg::virtualIntReg(i + 1), base, i, MicroOpBits::B8);
            loads[i] = builder.instructions().lastInstructionRef();
        }
        builder.emitRet();

        SWC_RESULT(runInstCombinePass(builder));
        for (uint32_t i = 0; i < loads.size(); ++i)
        {
            const bool        survives = overlappingStore ? (i < 2 || i >= 10) : i % 2 != 0;
            const MicroInstr* inst     = builder.instructions().ptr(loads[i]);
            if (!inst || inst->op != (survives ? MicroInstrOpcode::LoadRegReg : MicroInstrOpcode::LoadRegMem))
                return Result::Error;
            if (survives && inst->ops(builder.operands())[1].reg != (i % 2 == 0 ? first : second))
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_RipForwardingInitializesBeforeFirstMatchedRelocation)
{
    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(MicroReg::virtualIntReg(10), MicroReg::intReg(8), 0, MicroOpBits::B64);
    builder.emitLoadRegMem(MicroReg::virtualIntReg(11), MicroReg::intReg(8), 0, MicroOpBits::B64);
    // Ordinary forwarding precedes the first RIP access. That access has no
    // relocation, but the snapshot must still include all later relocations.
    builder.emitLoadRegMem(MicroReg::virtualIntReg(12), MicroReg::instructionPointer(), 0, MicroOpBits::B64);
    std::array<MicroInstrRef, 3> relocated;
    for (uint32_t i = 0; i < relocated.size(); ++i)
    {
        builder.emitLoadRegMem(MicroReg::virtualIntReg(i + 1), MicroReg::instructionPointer(), 0, MicroOpBits::B64);
        relocated[i] = builder.instructions().lastInstructionRef();
        MicroRelocation relocation;
        relocation.kind           = MicroRelocation::Kind::GlobalInitAddress;
        relocation.form           = MicroRelocation::Form::Relative32;
        relocation.targetAddress  = 8;
        relocation.instructionRef = relocated[i];
        builder.addRelocation(relocation);
    }
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 3 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 3)
        return Result::Error;
    for (uint32_t i = 1; i < relocated.size(); ++i)
    {
        const MicroInstr* inst = builder.instructions().ptr(relocated[i]);
        if (!inst || inst->op != MicroInstrOpcode::LoadRegReg || inst->ops(builder.operands())[1].reg != MicroReg::virtualIntReg(1))
            return Result::Error;
    }
    if (builder.codeRelocations().size() != 1 || builder.codeRelocations()[0].instructionRef != relocated[0])
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// and v, 0  -> ClearReg.
SWC_TEST_BEGIN(InstCombine_Absorbing_AndZero_BecomesClear)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{0}, 64), MicroOp::And, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// or v, ~0  -> LoadRegImm v, ~0.
SWC_TEST_BEGIN(InstCombine_Absorbing_OrAllOnes_BecomesLoadImm)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(~uint64_t{0}, 64), MicroOp::Or, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The arithmetic value has one reader, but its flags have a separate reader.
SWC_TEST_BEGIN(InstCombine_Reassociate_PreservesIntermediateFlags)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    constexpr MicroReg flag  = MicroReg::virtualIntReg(2);
    constexpr MicroReg base  = MicroReg::virtualIntReg(3);
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadRegMem(value, base, 0, bits);
        builder.emitOpBinaryRegImm(value, ApInt(3, 64), MicroOp::Add, bits);
        builder.emitSetCondReg(flag, MicroCond::Overflow);
        builder.emitOpBinaryRegImm(value, ApInt(4, 64), MicroOp::Add, bits);
        builder.emitLoadMemReg(base, 8, value, bits);
        builder.emitLoadMemReg(base, 16, flag, MicroOpBits::B8);
        builder.emitRet();

        SWC_RESULT(runInstCombinePass(builder));

        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 2)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPassHelpers_PartialFlagWritersDoNotKillLiveness)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    constexpr MicroReg flag  = MicroReg::virtualIntReg(2);
    constexpr MicroReg base  = MicroReg::virtualIntReg(3);
    for (const auto bits : {MicroOpBits::B8, MicroOpBits::B16, MicroOpBits::B32, MicroOpBits::B64})
    {
        const uint64_t countMask = bits == MicroOpBits::B64 ? 63 : 31;
        for (const bool memory : {false, true})
        {
            for (const auto op : {MicroOp::ShiftLeft, MicroOp::ShiftRight, MicroOp::ShiftArithmeticRight, MicroOp::RotateLeft, MicroOp::RotateRight})
            {
                for (const uint64_t count : {0ull, 1ull, countMask + 1, countMask + 2})
                {
                    MicroBuilder builder(ctx);
                    builder.emitCmpRegImm(value, ApInt(0, 64), MicroOpBits::B64);
                    const auto compare = builder.instructions().lastInstructionRef();
                    if (memory)
                        builder.emitOpBinaryMemImm(base, 1, ApInt(count, 64), op, bits);
                    else
                        builder.emitOpBinaryRegImm(value, ApInt(count, 64), op, bits);
                    builder.emitSetCondReg(flag, MicroCond::Equal);
                    builder.emitRet();

                    const bool dead = op != MicroOp::RotateLeft && op != MicroOp::RotateRight && (count & countMask) != 0;
                    if (MicroPassHelpers::areCpuFlagsDeadAfter(builder.instructions(), builder.operands(), compare) != dead ||
                        MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(builder.instructions(), builder.operands(), compare) != dead ||
                        MicroPassHelpers::areCpuFlagsDeadAfterInCfg(builder, compare) != dead)
                        return Result::Error;
                }
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_Immediate_PreservesFlagsAcrossJump)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    constexpr MicroReg flag  = MicroReg::virtualIntReg(2);
    constexpr MicroReg base  = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    const auto         target = builder.createLabel();
    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(value, ApInt(0, 64), MicroOp::Add, MicroOpBits::B64);
    const auto addRef = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, target);
    builder.placeLabel(target);
    builder.emitSetCondReg(flag, MicroCond::Equal);
    builder.emitLoadMemReg(base, 8, flag, MicroOpBits::B8);
    builder.emitRet();

    if (MicroPassHelpers::areCpuFlagsDeadAfter(builder.instructions(), builder.operands(), addRef))
        return Result::Error;
    SWC_RESULT(runInstCombinePass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// add v, c1 ; add v, c2  -> add v, c1+c2.
SWC_TEST_BEGIN(InstCombine_Reassociate_AddAdd)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(4, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::Add || imm != 7)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// add v, 5 ; sub v, 3  -> add v, 2.
SWC_TEST_BEGIN(InstCombine_Reassociate_AddSub_PicksAdd)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(5, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::Add || imm != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// shl v, 2 ; shl v, 3  -> shl v, 5.
SWC_TEST_BEGIN(InstCombine_Reassociate_ShiftLeftChain)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(1, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(2, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::ShiftLeft || imm != 5)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_Reassociate_ShiftCountOverflow_NotFolded)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
        for (const MicroOp shift : {MicroOp::ShiftLeft, MicroOp::ShiftRight, MicroOp::ShiftArithmeticRight})
        {
            MicroOp  combined = MicroOp::Add;
            uint64_t amount   = 0;
            if (InstructionCombine::tryReassociate(shift, UINT64_MAX, shift, 1, bits, combined, amount))
                return Result::Error;
            if (InstructionCombine::tryReassociate(shift, 1, shift, UINT64_MAX, bits, combined, amount))
                return Result::Error;
        }
    return Result::Continue;
}
SWC_TEST_END()

// shl v, 60 ; shl v, 8  -> not folded (sum >= 64 for B64).
SWC_TEST_BEGIN(InstCombine_Reassociate_ShiftOverflow_NotFolded)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(1, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(60, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(8, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// xor v, v  -> ClearReg.
SWC_TEST_BEGIN(InstCombine_RegReg_XorSelf_BecomesClear)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v1, MicroOp::Xor, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// sub v, v  -> ClearReg.
SWC_TEST_BEGIN(InstCombine_RegReg_SubSelf_BecomesClear)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v1, MicroOp::Subtract, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// and v, v  -> erased when v is dead.
SWC_TEST_BEGIN(InstCombine_RegReg_AndSelf_DeadErased)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v1, MicroOp::And, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// mul v, c1 ; mul v, c2  -> mul v, c1*c2 (signed).
SWC_TEST_BEGIN(InstCombine_Reassociate_MulMulSigned)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(2, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(5, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::MultiplySigned || imm != 15)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// or v, c1 ; or v, c2  -> or v, c1|c2.
SWC_TEST_BEGIN(InstCombine_Reassociate_OrOr)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(0x0F, 64), MicroOp::Or, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(0xF0, 64), MicroOp::Or, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::Or || imm != 0xFF)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// LoadRegMem ; OpBinaryRegImm ; LoadMemReg  ->  OpBinaryMemImm
SWC_TEST_BEGIN(InstCombine_MemFold_Imm_Consecutive)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(2);
    constexpr MicroReg vt   = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(base, 0x1000);
    builder.emitLoadRegMem(vt, base, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(vt, ApInt(7, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 8, vt, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// LoadRegMem ; OpBinaryRegReg ; LoadMemReg  ->  OpBinaryMemReg
SWC_TEST_BEGIN(InstCombine_MemFold_Reg_Consecutive)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(2);
    constexpr MicroReg vt   = MicroReg::virtualIntReg(3);
    constexpr MicroReg rhs  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(base, 0x1000);
    builder.emitLoadRegImm(rhs, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(vt, base, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(vt, rhs, MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 0, vt, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Load ; <unrelated instr> ; Op ; Store  -> still folds (windowed scan).
SWC_TEST_BEGIN(InstCombine_MemFold_NonConsecutive)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(2);
    constexpr MicroReg vt   = MicroReg::virtualIntReg(3);
    constexpr MicroReg rhs  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(base, 0x1000);
    builder.emitLoadRegMem(vt, base, 0, MicroOpBits::B64);
    // Materialize rhs between the load and the op (mimics the codegen shape).
    builder.emitLoadRegImm(rhs, ApInt(11, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(vt, rhs, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 0, vt, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// vt is read after the store -> must NOT fold.
SWC_TEST_BEGIN(InstCombine_MemFold_VtReadAfterStore_NotFolded)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(2);
    constexpr MicroReg vt   = MicroReg::virtualIntReg(3);
    constexpr MicroReg out  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(base, 0x1000);
    builder.emitLoadRegMem(vt, base, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(vt, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 0, vt, MicroOpBits::B64);
    builder.emitLoadRegReg(out, vt, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    // The triple cannot be folded because vt's post-op SSA value has 2 uses
    // (the store and the subsequent copy).
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemImm) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    uint32_t countBinaryMicroOp(const MicroBuilder& builder, MicroOp wanted)
    {
        const MicroOperandStorage& operands = builder.operands();
        uint32_t                   count    = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;
            if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[2].microOp == wanted)
                ++count;
            else if (inst.op == MicroInstrOpcode::OpBinaryRegReg && ops[3].microOp == wanted)
                ++count;
        }
        return count;
    }
}

// (x & C) << s  ->  x << s  when C keeps every bit the shift preserves: the AND
// is dead and removed, the shift stays. Immediate mask, feeding the shift directly.
SWC_TEST_BEGIN(InstCombine_MaskBeforeLeftShift_DroppedDirect)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0x123456789ABCDEF}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{0x0007FFFFFFFFFFFF}, 64), MicroOp::And, MicroOpBits::B64); // low 51 bits
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{13}, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countBinaryMicroOp(builder, MicroOp::And) != 0)
        return Result::Error;
    if (countBinaryMicroOp(builder, MicroOp::ShiftLeft) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Same fold, but the masked value reaches the shift through value-preserving
// copies with a register-held mask (the shape codegen actually emits).
SWC_TEST_BEGIN(InstCombine_MaskBeforeLeftShift_DroppedThroughCopies)
{
    constexpr MicroReg seed  = MicroReg::virtualIntReg(1);
    constexpr MicroReg vmask = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2    = MicroReg::virtualIntReg(3);
    constexpr MicroReg v3    = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(seed, ApInt(uint64_t{0x123456789ABCDEF}, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vmask, ApInt(uint64_t{0x00007FFFFFFFFFFF}, 64), MicroOpBits::B64); // low 47 bits
    builder.emitLoadRegReg(v2, seed, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v2, vmask, MicroOp::And, MicroOpBits::B64);
    builder.emitLoadRegReg(v3, v2, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v3, ApInt(uint64_t{17}, 64), MicroOp::ShiftLeft, MicroOpBits::B64); // 64-17 = 47
    builder.emitRet();

    // Two iterations, mirroring the real optimization loop: pass 1 folds the
    // register-held mask into an immediate AND, pass 2 drops the now-redundant AND.
    SWC_RESULT(runInstCombinePass(builder));
    SWC_RESULT(runInstCombinePass(builder));

    if (countBinaryMicroOp(builder, MicroOp::And) != 0)
        return Result::Error;
    if (countBinaryMicroOp(builder, MicroOp::ShiftLeft) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Not folded: the mask clears bits the shift keeps (0xFF vs the low 51 bits a
// shift-by-13 preserves), so the AND is semantically required.
SWC_TEST_BEGIN(InstCombine_MaskBeforeLeftShift_KeptWhenMaskTooNarrow)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0x123456789ABCDEF}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{0xFF}, 64), MicroOp::And, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{13}, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    // The mask itself must survive; the byte-mask AND canonicalizes into the
    // equivalent zero-extending move, which keeps the masking effect.
    if (countBinaryMicroOp(builder, MicroOp::And) + Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Not folded: a right shift does not discard the masked high bits, so the mask
// is meaningful and must stay.
SWC_TEST_BEGIN(InstCombine_MaskBeforeRightShift_Kept)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0x123456789ABCDEF}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{0x0007FFFFFFFFFFFF}, 64), MicroOp::And, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{7}, 64), MicroOp::ShiftRight, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countBinaryMicroOp(builder, MicroOp::And) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // Width of the first binary operation of this kind, whether its source
    // stayed in a register or was folded into a memory operand.
    bool firstBinaryBits(const MicroBuilder& builder, MicroOp op, MicroOpBits& outBits)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegReg && inst.op != MicroInstrOpcode::OpBinaryRegMem)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops || ops[3].microOp != op)
                continue;
            outBits = ops[2].opBits;
            return true;
        }
        return false;
    }
}

// A 32-bit load already clears the upper half of its register, so widening
// its result to 64 bits is a plain copy.
SWC_TEST_BEGIN(InstCombine_ZeroExtendOfDwordLoad_BecomesCopy)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2   = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 8, MicroOpBits::B32);
    builder.emitLoadZeroExtendRegReg(v2, v1, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 16, v2, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A 64-bit definition says nothing about its upper half: the extend stays.
SWC_TEST_BEGIN(InstCombine_ZeroExtendOfQwordLoad_Kept)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2   = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 8, MicroOpBits::B64);
    builder.emitLoadZeroExtendRegReg(v2, v1, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 16, v2, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The `(u64(a) + u64(b)) & 0xFFFFFFFF` idiom: both widenings become copies and
// the masked 64-bit addition narrows to the 32-bit one it computes.
SWC_TEST_BEGIN(InstCombine_MaskedAddOfZeroExtendedWords_NarrowsToDword)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2   = MicroReg::virtualIntReg(3);
    constexpr MicroReg v3   = MicroReg::virtualIntReg(4);
    constexpr MicroReg v4   = MicroReg::virtualIntReg(5);
    constexpr MicroReg v5   = MicroReg::virtualIntReg(6);
    constexpr MicroReg v6   = MicroReg::virtualIntReg(7);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 0, MicroOpBits::B32);
    builder.emitLoadRegMem(v2, base, 4, MicroOpBits::B32);
    builder.emitLoadZeroExtendRegReg(v3, v1, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadZeroExtendRegReg(v4, v2, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadRegReg(v5, v3, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v5, v4, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadZeroExtendRegReg(v6, v5, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 8, v6, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 0)
        return Result::Error;
    MicroOpBits addBits = MicroOpBits::Zero;
    if (!firstBinaryBits(builder, MicroOp::Add, addBits) || addBits != MicroOpBits::B32)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The sum has a second reader that wants all 64 bits: the addition keeps its
// width and the mask its extend.
SWC_TEST_BEGIN(InstCombine_MaskedAddWithQwordReader_Kept)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2   = MicroReg::virtualIntReg(3);
    constexpr MicroReg v3   = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 0, MicroOpBits::B64);
    builder.emitLoadRegMem(v2, base, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadZeroExtendRegReg(v3, v1, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 16, v3, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 24, v1, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 1)
        return Result::Error;
    MicroOpBits addBits = MicroOpBits::Zero;
    if (!firstBinaryBits(builder, MicroOp::Add, addBits) || addBits != MicroOpBits::B64)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A shift count is masked differently at each width, so a masked 64-bit shift
// is not the 32-bit shift.
SWC_TEST_BEGIN(InstCombine_MaskedShift_Kept)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2   = MicroReg::virtualIntReg(3);
    constexpr MicroReg v3   = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 0, MicroOpBits::B64);
    builder.emitLoadRegMem(v2, base, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitLoadZeroExtendRegReg(v3, v1, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 16, v3, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 1)
        return Result::Error;
    MicroOpBits shiftBits = MicroOpBits::Zero;
    if (!firstBinaryBits(builder, MicroOp::ShiftLeft, shiftBits) || shiftBits != MicroOpBits::B64)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A load/modify/store round trip inside a loop body: the temporary flows into
// a phi at the header that nothing reads, which must not count as a second
// consumer.
SWC_TEST_BEGIN(InstCombine_MemoryFoldTriple_InsideLoop)
{
    constexpr MicroReg rcx   = MicroReg::intReg(2);
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg count = MicroReg::virtualIntReg(2);
    constexpr MicroReg key   = MicroReg::virtualIntReg(3);
    constexpr MicroReg word  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    const MicroLabelRef loopLabel = builder.createLabel();
    builder.emitLoadRegReg(base, rcx, MicroOpBits::B64);
    builder.emitLoadRegImm(count, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(key, ApInt(uint64_t{0x5A}, 64), MicroOpBits::B32);
    builder.placeLabel(loopLabel);
    builder.emitLoadRegMem(word, base, 0, MicroOpBits::B32);
    builder.emitOpBinaryRegReg(word, key, MicroOp::Xor, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 0, word, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(base, ApInt(uint64_t{4}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(count, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(count, ApInt(uint64_t{16}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loopLabel);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The same round trip on a frame slot stays scalar: inside a loop that slot
// is slot promotion's and the vectorizer's to take.
SWC_TEST_BEGIN(InstCombine_MemoryFoldTriple_LeavesLoopFrameSlot)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg count = MicroReg::virtualIntReg(2);
    constexpr MicroReg key   = MicroReg::virtualIntReg(3);
    constexpr MicroReg word  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    const MicroLabelRef loopLabel = builder.createLabel();
    builder.emitLoadAddressRegMem(base, stack, 16, MicroOpBits::B64);
    builder.emitLoadRegImm(count, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(key, ApInt(uint64_t{0x5A}, 64), MicroOpBits::B32);
    builder.placeLabel(loopLabel);
    builder.emitLoadRegMem(word, base, 0, MicroOpBits::B32);
    builder.emitOpBinaryRegReg(word, key, MicroOp::Xor, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 0, word, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(count, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(count, ApInt(uint64_t{16}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loopLabel);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_MemoryFoldTriple_FrameWithoutBackEdgesKeepsCfgGuards)
{
    enum class Case
    {
        Linear,
        MultipleRoots,
        IndirectExit,
    };
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg key   = MicroReg::virtualIntReg(2);
    constexpr MicroReg word  = MicroReg::virtualIntReg(3);
    for (const Case test : {Case::Linear, Case::MultipleRoots, Case::IndirectExit})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadAddressRegMem(base, stack, 16, MicroOpBits::B64);
        builder.emitLoadRegImm(key, ApInt(0x5A, 32), MicroOpBits::B32);
        builder.emitLoadRegMem(word, base, 0, MicroOpBits::B32);
        const auto load = builder.instructions().lastInstructionRef();
        builder.emitOpBinaryRegReg(word, key, MicroOp::Xor, MicroOpBits::B32);
        builder.emitLoadMemReg(base, 0, word, MicroOpBits::B32);
        const auto store = builder.instructions().lastInstructionRef();
        if (test == Case::IndirectExit)
            builder.emitJumpReg(MicroReg::intReg(0));
        else
        {
            builder.emitRet();
            if (test == Case::MultipleRoots)
                builder.emitRet();
        }

        const auto& cfg = builder.controlFlowGraph();
        if (cfg.hasLoop() || cfg.hasUnsupportedControlFlowForCfgLiveness() != (test == Case::IndirectExit))
            return Result::Error;
        uint32_t roots = 0;
        for (uint32_t i = 0; i < cfg.instructionCount(); ++i)
            roots += cfg.predecessors(i).empty();
        if (roots != (test == Case::MultipleRoots ? 2u : 1u))
            return Result::Error;

        SWC_RESULT(runInstCombinePass(builder));
        const bool folded = test == Case::Linear;
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != (folded ? 1u : 0u))
            return Result::Error;
        if ((builder.instructions().ptr(load) != nullptr) == folded || (builder.instructions().ptr(store) != nullptr) == folded)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// A loop-carried 32-bit accumulator: every input of its phi is a 32-bit write,
// so the widening at the top of the body is a copy, and the masked addition
// that feeds the back edge narrows.
SWC_TEST_BEGIN(InstCombine_ZeroExtendOfDwordPhi_BecomesCopy)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg acc   = MicroReg::virtualIntReg(2);
    constexpr MicroReg count = MicroReg::virtualIntReg(3);
    constexpr MicroReg wide  = MicroReg::virtualIntReg(4);
    constexpr MicroReg word  = MicroReg::virtualIntReg(5);
    constexpr MicroReg sum   = MicroReg::virtualIntReg(6);
    constexpr MicroReg next  = MicroReg::virtualIntReg(7);
    MicroBuilder       builder(ctx);

    const MicroLabelRef loopLabel = builder.createLabel();
    builder.emitLoadRegImm(acc, ApInt(uint64_t{0}, 64), MicroOpBits::B32);
    builder.emitLoadRegImm(count, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.placeLabel(loopLabel);
    builder.emitLoadZeroExtendRegReg(wide, acc, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadRegMem(word, base, 0, MicroOpBits::B32);
    builder.emitLoadRegReg(sum, wide, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(sum, word, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadZeroExtendRegReg(next, sum, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadRegReg(acc, next, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(count, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(count, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loopLabel);
    builder.emitLoadMemReg(base, 8, acc, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 0)
        return Result::Error;
    MicroOpBits addBits = MicroOpBits::Zero;
    if (!firstBinaryBits(builder, MicroOp::Add, addBits) || addBits != MicroOpBits::B32)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_MultiplyAddress_ImmediateMagnitude)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    constexpr MicroReg base  = MicroReg::virtualIntReg(2);
    for (const uint64_t multiplier : {2ull, 3ull, 5ull, 9ull, 0x8000000000000000ull, 0x8000000000000001ull})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(value, ApInt(multiplier, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
        builder.emitLoadMemReg(base, 8, value, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runInstCombinePass(builder));

        const bool address = multiplier <= 9;
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrAmcRegMem) != (address ? 1u : 0u))
            return Result::Error;
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != (address ? 0u : 1u))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_MultiplyAdd_BecomesTwoAddresses)
{
    constexpr MicroReg base    = MicroReg::virtualIntReg(1);
    constexpr MicroReg product = MicroReg::virtualIntReg(2);
    constexpr MicroReg addend  = MicroReg::virtualIntReg(3);
    constexpr MicroReg copied  = MicroReg::virtualIntReg(4);

    for (const uint64_t multiplier : {6ull, 10ull, 12ull, 18ull, 20ull, 24ull, 36ull, 40ull, 72ull})
    {
        for (const bool reverse : {false, true})
        {
            for (const bool copyProduct : {false, true})
            {
                MicroBuilder builder(ctx);
                builder.emitLoadRegMem(product, base, 0, MicroOpBits::B64);
                builder.emitLoadRegMem(addend, base, 8, MicroOpBits::B64);
                builder.emitLoadMemReg(base, 24, addend, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(product, ApInt(multiplier, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
                if (copyProduct)
                    builder.emitLoadRegReg(copied, product, MicroOpBits::B64);
                const MicroReg scaled = copyProduct ? copied : product;
                const MicroReg dst    = reverse ? addend : scaled;
                builder.emitOpBinaryRegReg(dst, reverse ? scaled : addend, MicroOp::Add, MicroOpBits::B64);
                builder.emitLoadMemReg(base, 16, dst, MicroOpBits::B64);
                builder.emitRet();

                SWC_RESULT(runInstCombinePass(builder));
                SWC_RESULT(runInstCombinePass(builder));

                if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrAmcRegMem) != 2)
                    return Result::Error;
                if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
                    return Result::Error;
                uint64_t actualMultiplier = 1;
                uint32_t addressCount     = 0;
                for (const MicroInstr& inst : builder.instructions().view())
                {
                    if (inst.op != MicroInstrOpcode::LoadAddrAmcRegMem)
                        continue;
                    const MicroInstrOperand* ops = inst.ops(builder.operands());
                    actualMultiplier *= addressCount++ == 0 ? 1 + ops[5].valueU64 : ops[5].valueU64;
                }
                if (actualMultiplier != multiplier)
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_MultiplyAdd_PreservesObservedValuesAndFlags)
{
    constexpr MicroReg base    = MicroReg::virtualIntReg(1);
    constexpr MicroReg product = MicroReg::virtualIntReg(2);
    constexpr MicroReg addend  = MicroReg::virtualIntReg(3);
    constexpr MicroReg copied  = MicroReg::virtualIntReg(4);

    // A live product, either operation's flags, and a changed source after a
    // copy each prevent changing the intermediate product's meaning.
    for (uint32_t scenario = 0; scenario < 6; ++scenario)
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef exitLabel = builder.createLabel();
        builder.emitLoadRegMem(product, base, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(addend, base, 8, MicroOpBits::B64);
        builder.emitLoadMemReg(base, 24, addend, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(product, ApInt(uint64_t{10}, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
        if (scenario == 0)
            builder.emitLoadMemReg(base, 32, product, MicroOpBits::B64);
        if (scenario == 4)
            builder.emitClearReg(MicroReg::virtualFloatReg(1), MicroOpBits::B64);
        if (scenario == 1 || scenario == 4)
            builder.emitJumpToLabel(MicroCond::Overflow, MicroOpBits::B32, exitLabel);
        if (scenario == 3)
        {
            builder.emitLoadRegReg(copied, product, MicroOpBits::B64);
            builder.emitLoadRegMem(product, base, 40, MicroOpBits::B64);
        }
        const MicroReg scaled = scenario == 3 ? copied : product;
        builder.emitOpBinaryRegReg(addend, scaled, MicroOp::Add, MicroOpBits::B64);
        if (scenario == 5)
            builder.emitClearReg(MicroReg::virtualFloatReg(1), MicroOpBits::B64);
        if (scenario == 2 || scenario == 5)
            builder.emitJumpToLabel(MicroCond::Overflow, MicroOpBits::B32, exitLabel);
        builder.emitLoadMemReg(base, 16, addend, MicroOpBits::B64);
        builder.placeLabel(exitLabel);
        builder.emitRet();

        SWC_RESULT(runInstCombinePass(builder));

        MicroOp  op;
        uint64_t immediate = 0;
        if (!firstBinaryRegImm(builder, op, immediate) || op != MicroOp::MultiplySigned || immediate != 10)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_AddressCopy_DefinesAccumulatorDirectly)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg acc  = MicroReg::virtualIntReg(2);
    constexpr MicroReg temp = MicroReg::virtualIntReg(3);
    for (const bool otherReader : {false, true})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadAddressAmcRegMem(temp, MicroOpBits::B64, base, acc, 2, 0, MicroOpBits::B64);
        builder.emitLoadRegReg(acc, temp, MicroOpBits::B64);
        if (otherReader)
            builder.emitLoadMemReg(base, 0, temp, MicroOpBits::B64);
        builder.emitLoadMemReg(base, 8, acc, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runInstCombinePass(builder));

        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != (otherReader ? 1 : 0))
            return Result::Error;
        const MicroInstr& first = *builder.instructions().view().begin();
        if (first.ops(builder.operands())[0].reg != (otherReader ? temp : acc))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_FloatResultCopy_DefinesAccumulatorDirectly)
{
    for (const MicroOp op : {MicroOp::FloatMultiply, MicroOp::FloatSqrt})
        for (const bool preserve : {false, true})
            for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
            {
                constexpr MicroReg acc    = MicroReg::virtualFloatReg(1);
                constexpr MicroReg src    = MicroReg::virtualFloatReg(2);
                constexpr MicroReg result = MicroReg::virtualFloatReg(3);
                constexpr MicroReg base   = MicroReg::virtualIntReg(1);
                MicroBuilder       builder(ctx);
                builder.emitLoadRegMem(acc, base, 0, bits);
                builder.emitLoadRegMem(src, base, 8, bits);
                if (op == MicroOp::FloatSqrt)
                    builder.emitOpBinaryRegReg(result, acc, op, bits);
                else
                    builder.emitOpBinaryRegRegReg(result, acc, src, op, bits);
                builder.emitLoadRegReg(acc, result, bits);
                if (preserve)
                    builder.preserveVirtualCopy(acc);
                builder.emitLoadMemReg(base, 16, acc, bits);
                builder.emitRet();
                SWC_RESULT(runInstCombinePass(builder));
                const MicroInstrOpcode opcode = op == MicroOp::FloatSqrt ? MicroInstrOpcode::OpBinaryRegReg : MicroInstrOpcode::OpBinaryRegRegReg;
                if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != (preserve ? 1u : 0u) ||
                    Backend::Unittest::countOpcode(builder, opcode) != 1)
                    return Result::Error;
                for (const MicroInstr& inst : builder.instructions().view())
                {
                    if (inst.op != opcode)
                        continue;
                    const MicroInstrOperand* ops = inst.ops(builder.operands());
                    if (ops[0].reg != (preserve ? result : acc) || ops[1].reg != acc ||
                        (op != MicroOp::FloatSqrt && ops[2].reg != src))
                        return Result::Error;
                }
            }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_SqrtResultCopy_PreservesPackedDestination)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        constexpr MicroReg src    = MicroReg::virtualFloatReg(1);
        constexpr MicroReg result = MicroReg::virtualFloatReg(2);
        constexpr MicroReg copied = MicroReg::virtualFloatReg(3);
        constexpr MicroReg base   = MicroReg::virtualIntReg(1);
        MicroBuilder       builder(ctx);
        builder.emitLoadVecRegMem(src, base, 0, MicroOpBits::B128);
        builder.emitLoadVecRegMem(copied, base, 16, MicroOpBits::B128);
        builder.emitOpBinaryRegReg(result, src, MicroOp::FloatSqrt, bits);
        builder.emitLoadRegReg(copied, result, bits);
        builder.emitStoreVecMemReg(base, 32, copied, MicroOpBits::B128);
        builder.emitRet();
        SWC_RESULT(runInstCombinePass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_SqrtResultCopy_ReusesGlobalReadCheckByWidth)
{
    for (const bool mixedWidths : {false, true})
    {
        for (uint32_t blockingRead = 0; blockingRead < 3; ++blockingRead)
        {
            constexpr MicroReg           base = MicroReg::intReg(8);
            MicroBuilder                 builder(ctx);
            std::array<MicroInstrRef, 4> roots;
            std::array<MicroInstrRef, 4> copies;
            for (uint32_t i = 0; i < roots.size(); ++i)
            {
                const MicroOpBits bits   = mixedWidths && i % 2 ? MicroOpBits::B64 : MicroOpBits::B32;
                const MicroReg    src    = MicroReg::virtualFloatReg(i * 3 + 1);
                const MicroReg    result = MicroReg::virtualFloatReg(i * 3 + 2);
                const MicroReg    copied = MicroReg::virtualFloatReg(i * 3 + 3);
                if (i == 2)
                    builder.placeLabel(builder.createLabel());
                builder.emitLoadRegMem(src, base, i * 16, bits);
                builder.emitOpBinaryRegReg(result, src, MicroOp::FloatSqrt, bits);
                roots[i] = builder.instructions().lastInstructionRef();
                builder.emitLoadRegReg(copied, result, bits);
                copies[i] = builder.instructions().lastInstructionRef();
                builder.emitLoadMemReg(base, 0x100 + i * 16, copied, bits);
            }
            // A later packed or unclassified read must reject every earlier
            // candidate, even across blocks and after the first cached answer.
            if (blockingRead == 1)
                builder.emitLoadRegReg(MicroReg::virtualFloatReg(21), MicroReg::virtualFloatReg(3), MicroOpBits::B128);
            else if (blockingRead == 2)
                builder.emitStoreVecMemReg(base, 0x200, MicroReg::virtualFloatReg(3), MicroOpBits::B128);
            builder.emitRet();

            SWC_RESULT(runInstCombinePass(builder));
            for (uint32_t i = 0; i < roots.size(); ++i)
            {
                const bool        folded = blockingRead == 0 && (!mixedWidths || i % 2 != 0);
                const MicroInstr* inst   = builder.instructions().ptr(roots[i]);
                if (!inst || inst->ops(builder.operands())[0].reg != MicroReg::virtualFloatReg(i * 3 + (folded ? 3 : 2)))
                    return Result::Error;
                if ((builder.instructions().ptr(copies[i]) == nullptr) != folded)
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_SqrtResultCopy_KeepsOtherUses)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        constexpr MicroReg src    = MicroReg::virtualFloatReg(1);
        constexpr MicroReg result = MicroReg::virtualFloatReg(2);
        constexpr MicroReg copied = MicroReg::virtualFloatReg(3);
        constexpr MicroReg base   = MicroReg::virtualIntReg(1);
        MicroBuilder       builder(ctx);
        builder.emitLoadRegMem(src, base, 0, bits);
        builder.emitOpBinaryRegReg(result, src, MicroOp::FloatSqrt, bits);
        builder.emitLoadRegReg(copied, result, bits);
        builder.emitLoadMemReg(base, 8, copied, bits);
        builder.emitLoadMemReg(base, 16, result, bits);
        builder.emitRet();
        SWC_RESULT(runInstCombinePass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_SharedAndInputs_PreservesValuesAndFlags)
{
    enum class Case
    {
        Fold,
        SharedResult,
        CommonChanged,
        CommonChangedAfter,
        LiveFirstFlags,
        LiveSecondFlags,
        CopyBeforeSecond,
    };
    for (const Case test : {Case::Fold, Case::SharedResult, Case::CommonChanged, Case::CommonChangedAfter, Case::LiveFirstFlags, Case::LiveSecondFlags, Case::CopyBeforeSecond})
        for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
            for (const bool copy : {false, true})
            {
                if (test == Case::CopyBeforeSecond && !copy)
                    continue;
                constexpr MicroReg common = MicroReg::virtualIntReg(1);
                constexpr MicroReg b      = MicroReg::virtualIntReg(2);
                constexpr MicroReg c      = MicroReg::virtualIntReg(3);
                constexpr MicroReg first  = MicroReg::virtualIntReg(4);
                constexpr MicroReg second = MicroReg::virtualIntReg(5);
                constexpr MicroReg copied = MicroReg::virtualIntReg(6);
                constexpr MicroReg flag   = MicroReg::virtualIntReg(7);
                constexpr MicroReg base   = MicroReg::intReg(3);
                const MicroReg     result = copy ? copied : first;
                MicroBuilder       builder(ctx);
                builder.emitLoadRegReg(common, MicroReg::intReg(0), bits);
                builder.emitLoadRegReg(b, MicroReg::intReg(1), bits);
                builder.emitLoadRegReg(c, MicroReg::intReg(2), bits);
                builder.emitLoadRegReg(first, common, bits);
                builder.emitOpBinaryRegReg(first, b, MicroOp::And, bits);
                if (test == Case::SharedResult)
                    builder.emitLoadMemReg(base, 8, first, bits);
                if (test == Case::LiveFirstFlags)
                    builder.emitSetCondReg(flag, MicroCond::Zero);
                if (test == Case::CommonChanged)
                    builder.emitLoadRegReg(common, MicroReg::intReg(4), bits);
                if (test == Case::CopyBeforeSecond)
                    builder.emitLoadRegReg(copied, first, bits);
                builder.emitLoadRegReg(second, common, bits);
                builder.emitOpBinaryRegReg(second, c, MicroOp::And, bits);
                if (test == Case::LiveSecondFlags)
                    builder.emitSetCondReg(flag, MicroCond::Zero);
                if (test == Case::CommonChangedAfter)
                    builder.emitLoadRegReg(common, MicroReg::intReg(4), bits);
                if (copy && test != Case::CopyBeforeSecond)
                    builder.emitLoadRegReg(copied, first, bits);
                builder.emitOpBinaryRegReg(result, second, MicroOp::Xor, bits);
                builder.emitLoadMemReg(base, 0, result, bits);
                if (test == Case::LiveFirstFlags || test == Case::LiveSecondFlags)
                    builder.emitLoadMemReg(base, 16, flag, MicroOpBits::B8);
                builder.emitRet();
                SWC_RESULT(runInstCombinePass(builder));
                uint32_t andCount = 0;
                for (const MicroInstr& inst : builder.instructions().view())
                    if (inst.op == MicroInstrOpcode::OpBinaryRegReg && inst.ops(builder.operands())[3].microOp == MicroOp::And)
                        ++andCount;
                if (andCount != (test == Case::Fold ? 1u : 2u))
                    return Result::Error;
            }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstructionCombine_FoldsBooleanSelect)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        for (const uint64_t sourceValue : {uint64_t{0}, uint64_t{1}})
        {
            constexpr MicroReg dst = MicroReg::virtualIntReg(1);
            constexpr MicroReg src = MicroReg::virtualIntReg(2);
            MicroBuilder       builder(ctx);
            builder.emitLoadRegImm(dst, ApInt(1 - sourceValue, 64), bits);
            builder.emitCmpRegReg(MicroReg::intReg(2), MicroReg::intReg(3), bits);
            builder.emitLoadRegImm(src, ApInt(sourceValue, 64), bits);
            builder.emitLoadCondRegReg(dst, src, MicroCond::Equal, bits);
            builder.emitLoadMemReg(MicroReg::intReg(2), 0, dst, bits);
            builder.emitRet();
            SWC_RESULT(runInstCombinePass(builder));
            if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 0 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::SetCondReg) != 1 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 1)
                return Result::Error;
            for (const MicroInstr& inst : builder.instructions().view())
            {
                const MicroInstrOperand* ops = inst.ops(builder.operands());
                if (inst.op == MicroInstrOpcode::SetCondReg &&
                    (ops[0].reg != src || ops[1].cpuCond != (sourceValue ? MicroCond::Equal : MicroCond::NotEqual)))
                    return Result::Error;
                if (inst.op == MicroInstrOpcode::LoadZeroExtRegReg &&
                    (ops[0].reg != dst || ops[1].reg != src || ops[2].opBits != bits || ops[3].opBits != MicroOpBits::B8))
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

// A zero/one select only needs SETcc and zero-extension, which preserve live flags.
SWC_TEST_BEGIN(InstructionCombine_BooleanSelectPreservesLiveFlags)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
        for (const bool sourceNonzero : {false, true})
        {
            constexpr MicroReg dst  = MicroReg::virtualIntReg(1);
            constexpr MicroReg src  = MicroReg::virtualIntReg(2);
            constexpr MicroReg flag = MicroReg::virtualIntReg(3);
            constexpr MicroReg base = MicroReg::intReg(2);
            MicroBuilder       builder(ctx);
            builder.emitLoadRegImm(dst, ApInt(sourceNonzero ? 0 : 1, 64), bits);
            builder.emitCmpRegReg(base, MicroReg::intReg(3), bits);
            builder.emitLoadRegImm(src, ApInt(sourceNonzero ? 1 : 0, 64), bits);
            builder.emitLoadCondRegReg(dst, src, MicroCond::Equal, bits);
            builder.emitSetCondReg(flag, MicroCond::Zero);
            builder.emitLoadMemReg(base, 8, flag, MicroOpBits::B8);
            builder.emitLoadMemReg(base, 0, dst, bits);
            builder.emitRet();
            SWC_RESULT(runInstCombinePass(builder));
            if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 0 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::SetCondReg) != 2 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 1 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpUnaryReg) != 0 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
                return Result::Error;
            for (const MicroInstr& inst : builder.instructions().view())
            {
                const MicroInstrOperand* ops = inst.ops(builder.operands());
                if (inst.op == MicroInstrOpcode::SetCondReg)
                {
                    if (ops[0].reg == src)
                    {
                        if (ops[1].cpuCond != (sourceNonzero ? MicroCond::Equal : MicroCond::NotEqual))
                            return Result::Error;
                    }
                    else if (ops[0].reg != flag || ops[1].cpuCond != MicroCond::Zero)
                        return Result::Error;
                }
                if (inst.op == MicroInstrOpcode::LoadZeroExtRegReg && (ops[0].reg != dst || ops[1].reg != src || ops[2].opBits != bits || ops[3].opBits != MicroOpBits::B8))
                    return Result::Error;
            }
        }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstructionCombine_KeepsUnsafeBooleanSelect)
{
    enum class Case
    {
        SharedSource,
        InterveningFlags,
        NarrowInitial,
        UnsupportedConstant,
        PartialMask,
        NoComplement
    };
    for (const Case test : {Case::SharedSource, Case::InterveningFlags, Case::NarrowInitial, Case::UnsupportedConstant, Case::PartialMask, Case::NoComplement})
    {
        constexpr MicroReg dst = MicroReg::virtualIntReg(1);
        constexpr MicroReg src = MicroReg::virtualIntReg(2);
        MicroBuilder       builder(ctx);
        // 129 fits neither a single LEA scale nor a sign-extended byte mask.
        const uint64_t initialValue = test == Case::UnsupportedConstant ? 129 : test == Case::PartialMask ? 0xFFFFFFFF
                                                                                                          : 1;
        builder.emitLoadRegImm(dst, ApInt(initialValue, 64), test == Case::NarrowInitial ? MicroOpBits::B8 : MicroOpBits::B64);
        builder.emitCmpRegReg(MicroReg::intReg(2), MicroReg::intReg(3), MicroOpBits::B64);
        builder.emitLoadRegImm(src, ApInt(0, 64), MicroOpBits::B64);
        if (test == Case::InterveningFlags)
            builder.emitCmpRegReg(MicroReg::intReg(3), MicroReg::intReg(2), MicroOpBits::B64);
        builder.emitLoadCondRegReg(dst, src, test == Case::NoComplement ? MicroCond::Sign : MicroCond::Equal, MicroOpBits::B64);
        if (test == Case::SharedSource)
            builder.emitLoadMemReg(MicroReg::intReg(2), 8, src, MicroOpBits::B64);
        builder.emitLoadMemReg(MicroReg::intReg(2), 0, dst, MicroOpBits::B64);
        builder.emitRet();
        SWC_RESULT(runInstCombinePass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 1 ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::SetCondReg) != 0)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// Affine selects preserve live flags and both selected values, including signed
// displacement limits and modulo-width wraparound. Rejected cases keep the CMOV.
SWC_TEST_BEGIN(InstructionCombine_AffineSelect_PreservesValuesAndFlags)
{
    struct Case
    {
        uint64_t first;
        uint64_t second;
        bool     folds32;
        bool     folds64;
    };
    constexpr Case cases[] = {
        {3, 4, true, true},
        {3, 5, true, true},
        {0, 3, true, true},
        {3, 7, true, true},
        {7, 12, true, true},
        {1, 9, true, true},
        {7, 16, true, true},
        {0x7FFFFFFF, 0x80000000, true, true},
        {0x80000000, 0x80000001, true, false},
        {0xFFFFFFFF80000000, 0xFFFFFFFF80000003, true, true},
        {0xFFFFFFFF7FFFFFFF, 0xFFFFFFFF80000000, true, false},
        {0xFFFFFFFFFFFFFFFF, 1, true, true},
        {3, 9, false, false},
        {3, 10, false, false},
    };
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
        for (const Case& test : cases)
            for (const bool reversed : {false, true})
            {
                constexpr MicroReg dst          = MicroReg::virtualIntReg(1);
                constexpr MicroReg src          = MicroReg::virtualIntReg(2);
                constexpr MicroReg flag         = MicroReg::virtualIntReg(3);
                constexpr MicroReg base         = MicroReg::intReg(2);
                const uint64_t     initialValue = (reversed ? test.second : test.first) & getBitsMask(bits);
                const uint64_t     sourceValue  = (reversed ? test.first : test.second) & getBitsMask(bits);
                const bool         folds        = bits == MicroOpBits::B32 ? test.folds32 : test.folds64;
                MicroBuilder       builder(ctx);
                builder.emitLoadRegImm(dst, ApInt(initialValue, 64), bits);
                builder.emitCmpRegReg(base, MicroReg::intReg(3), bits);
                builder.emitLoadRegImm(src, ApInt(sourceValue, 64), bits);
                builder.emitLoadCondRegReg(dst, src, MicroCond::Equal, bits);
                builder.emitSetCondReg(flag, MicroCond::Zero);
                builder.emitLoadMemReg(base, 8, flag, MicroOpBits::B8);
                builder.emitLoadMemReg(base, 0, dst, bits);
                builder.emitRet();
                SWC_RESULT(runInstCombinePass(builder));

                const uint32_t addresses = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrRegMem) + Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrAmcRegMem);
                if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != (folds ? 0u : 1u) ||
                    Backend::Unittest::countOpcode(builder, MicroInstrOpcode::SetCondReg) != (folds ? 2u : 1u) ||
                    Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != (folds ? 1u : 0u) ||
                    addresses != (folds ? 1u : 0u) ||
                    Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 1 ||
                    Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpUnaryReg) != 0 ||
                    Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0 ||
                    Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
                    return Result::Error;
                if (!folds)
                    continue;

                MicroCond selectedCondition = MicroCond::Unconditional;
                uint64_t  coefficient       = 0;
                uint64_t  offset            = 0;
                for (const MicroInstr& inst : builder.instructions().view())
                {
                    const MicroInstrOperand* ops = inst.ops(builder.operands());
                    if (inst.op == MicroInstrOpcode::SetCondReg)
                    {
                        if (ops[0].reg == src)
                            selectedCondition = ops[1].cpuCond;
                        else if (ops[0].reg != flag || ops[1].cpuCond != MicroCond::Zero)
                            return Result::Error;
                    }
                    if (inst.op == MicroInstrOpcode::LoadZeroExtRegReg &&
                        (ops[0].reg != dst || ops[1].reg != src || ops[2].opBits != bits || ops[3].opBits != MicroOpBits::B8))
                        return Result::Error;
                    if (inst.op == MicroInstrOpcode::LoadAddrRegMem)
                    {
                        if (ops[0].reg != dst || ops[1].reg != dst || ops[2].opBits != bits)
                            return Result::Error;
                        coefficient = 1;
                        offset      = ops[3].valueU64;
                    }
                    if (inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
                    {
                        if (ops[0].reg != dst || (ops[1].reg != dst && ops[1].reg != MicroReg::noBase()) || ops[2].reg != dst ||
                            ops[3].opBits != bits || ops[4].opBits != MicroOpBits::B64 ||
                            (ops[5].valueU64 != 1 && ops[5].valueU64 != 2 && ops[5].valueU64 != 4 && ops[5].valueU64 != 8))
                            return Result::Error;
                        coefficient = (ops[1].reg == dst ? 1u : 0u) + ops[5].valueU64;
                        offset      = ops[6].valueU64;
                    }
                }
                if (selectedCondition != MicroCond::Equal && selectedCondition != MicroCond::NotEqual)
                    return Result::Error;
                for (const bool equal : {false, true})
                {
                    const uint64_t selected = selectedCondition == MicroCond::Equal ? equal : !equal;
                    const uint64_t result   = (offset + coefficient * selected) & getBitsMask(bits);
                    if (result != (equal ? sourceValue : initialValue))
                        return Result::Error;
                }
            }
    return Result::Continue;
}
SWC_TEST_END()

// Shifts, negation and compact masks preserve the selected values, but their
// arithmetic must not overwrite flags consumed after the select.
SWC_TEST_BEGIN(InstructionCombine_ScaledBooleanSelect_PreservesMasksAndFlags)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
        for (const uint64_t mask : {uint64_t{2}, uint64_t{7}, uint64_t{127}, uint64_t{128}, uint64_t{129}, uint64_t{0x80000000}, uint64_t{0xFFFFFFFF}, uint64_t{0x100000000}, uint64_t{0x8000000000000000}, ~uint64_t{0}})
        {
            if (mask > getBitsMask(bits))
                continue;
            // A 32-bit all-one value is not an all-one mask for a 64-bit select.
            if (bits == MicroOpBits::B64 && mask == 0xFFFFFFFF)
                continue;
            for (const bool sourceNonzero : {false, true})
                for (const bool liveFlags : {false, true})
                {
                    constexpr MicroReg dst  = MicroReg::virtualIntReg(1);
                    constexpr MicroReg src  = MicroReg::virtualIntReg(2);
                    constexpr MicroReg flag = MicroReg::virtualIntReg(3);
                    constexpr MicroReg base = MicroReg::intReg(2);
                    MicroBuilder       builder(ctx);
                    builder.emitLoadRegImm(dst, ApInt(sourceNonzero ? 0 : mask, 64), bits);
                    builder.emitCmpRegReg(base, MicroReg::intReg(3), bits);
                    builder.emitLoadRegImm(src, ApInt(sourceNonzero ? mask : 0, 64), bits);
                    builder.emitLoadCondRegReg(dst, src, MicroCond::Equal, bits);
                    if (liveFlags)
                    {
                        builder.emitSetCondReg(flag, MicroCond::Zero);
                        builder.emitLoadMemReg(base, 8, flag, MicroOpBits::B8);
                    }
                    builder.emitLoadMemReg(base, 0, dst, bits);
                    builder.emitRet();
                    SWC_RESULT(runInstCombinePass(builder));
                    // 127 is the compact-mask boundary; 128 uses a shift and 129 stays a select.
                    const bool folds = !liveFlags && mask != 129;
                    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != (folds ? 0u : 1u) ||
                        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::SetCondReg) != (folds || liveFlags ? 1u : 0u) ||
                        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != (folds ? 1u : 0u))
                        return Result::Error;
                    if (!folds)
                    {
                        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpUnaryReg) != 0 ||
                            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
                            return Result::Error;
                        for (const MicroInstr& inst : builder.instructions().view())
                        {
                            const MicroInstrOperand* ops = inst.ops(builder.operands());
                            if (inst.op == MicroInstrOpcode::SetCondReg && (ops[0].reg != flag || ops[1].cpuCond != MicroCond::Zero))
                                return Result::Error;
                        }
                        continue;
                    }

                    const bool              compactMask = mask == 7 || mask == 127;
                    const bool              negate      = mask == getBitsMask(bits);
                    uint32_t                scales      = 0;
                    std::array<uint64_t, 2> values{0, 1};
                    for (const MicroInstr& inst : builder.instructions().view())
                    {
                        const MicroInstrOperand* ops = inst.ops(builder.operands());
                        if (inst.op == MicroInstrOpcode::SetCondReg && (ops[0].reg != src || ops[1].cpuCond != (sourceNonzero ? MicroCond::Equal : MicroCond::NotEqual)))
                            return Result::Error;
                        if (inst.op == MicroInstrOpcode::LoadZeroExtRegReg && (ops[0].reg != dst || ops[1].reg != src || ops[2].opBits != bits || ops[3].opBits != MicroOpBits::B8))
                            return Result::Error;
                        if (inst.op == MicroInstrOpcode::OpUnaryReg)
                        {
                            if ((!negate && !compactMask) || ops[0].reg != dst || ops[1].opBits != bits || ops[2].microOp != MicroOp::Negate)
                                return Result::Error;
                            for (uint64_t& value : values)
                                value = (0ull - value) & getBitsMask(bits);
                            ++scales;
                            continue;
                        }
                        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                            continue;
                        ++scales;
                        const MicroOpBits scaleBits = mask > 0xFFFFFFFF ? bits : MicroOpBits::B32;
                        if (negate || ops[0].reg != dst || ops[1].opBits != scaleBits || ops[2].microOp != (compactMask ? MicroOp::And : MicroOp::ShiftLeft) ||
                            ops[3].valueU64 != (compactMask ? mask : std::countr_zero(mask)))
                            return Result::Error;
                        for (uint64_t& value : values)
                            value = (compactMask ? value & ops[3].valueU64 : value << ops[3].valueU64) & getBitsMask(scaleBits);
                    }
                    if (scales != (compactMask ? 2u : 1u) || values[0] != 0 || values[1] != mask)
                        return Result::Error;
                }
        }
    return Result::Continue;
}
SWC_TEST_END()

// The shift-legalization clamp `cmp count, 64; cmov value, 0 if ae` dies when the
// count provably stays below the width: here it reaches the compare through
// `and count, 0x1F` and a zero-extend.
SWC_TEST_BEGIN(InstCombine_RangeProvedCompare_ClampErased)
{
    constexpr MicroReg count   = MicroReg::virtualIntReg(1);
    constexpr MicroReg count64 = MicroReg::virtualIntReg(2);
    constexpr MicroReg value   = MicroReg::virtualIntReg(3);
    constexpr MicroReg zero    = MicroReg::virtualIntReg(4);
    constexpr MicroReg base    = MicroReg::virtualIntReg(5);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(count, base, 0, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(count, ApInt(uint64_t{0x1F}, 64), MicroOp::And, MicroOpBits::B32);
    builder.emitLoadRegMem(value, base, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(value, count, MicroOp::ShiftRight, MicroOpBits::B64);
    builder.emitClearReg(zero, MicroOpBits::B64);
    builder.emitLoadZeroExtendRegReg(count64, count, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitCmpRegImm(count64, ApInt(uint64_t{64}, 64), MicroOpBits::B64);
    builder.emitLoadCondRegReg(value, zero, MicroCond::AboveOrEqual, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 16, value, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A mask that does not bound the count below the width keeps the clamp.
SWC_TEST_BEGIN(InstCombine_RangeProvedCompare_WideMaskKept)
{
    constexpr MicroReg count   = MicroReg::virtualIntReg(1);
    constexpr MicroReg count64 = MicroReg::virtualIntReg(2);
    constexpr MicroReg value   = MicroReg::virtualIntReg(3);
    constexpr MicroReg zero    = MicroReg::virtualIntReg(4);
    constexpr MicroReg base    = MicroReg::virtualIntReg(5);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(count, base, 0, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(count, ApInt(uint64_t{0x7F}, 64), MicroOp::And, MicroOpBits::B32);
    builder.emitLoadRegMem(value, base, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(value, count, MicroOp::ShiftRight, MicroOpBits::B64);
    builder.emitClearReg(zero, MicroOpBits::B64);
    builder.emitLoadZeroExtendRegReg(count64, count, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitCmpRegImm(count64, ApInt(uint64_t{64}, 64), MicroOpBits::B64);
    builder.emitLoadCondRegReg(value, zero, MicroCond::AboveOrEqual, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 16, value, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A byte-wide source write merges with stale upper bits and proves nothing.
SWC_TEST_BEGIN(InstCombine_RangeProvedCompare_NarrowWriteKept)
{
    constexpr MicroReg count   = MicroReg::virtualIntReg(1);
    constexpr MicroReg count64 = MicroReg::virtualIntReg(2);
    constexpr MicroReg value   = MicroReg::virtualIntReg(3);
    constexpr MicroReg zero    = MicroReg::virtualIntReg(4);
    constexpr MicroReg base    = MicroReg::virtualIntReg(5);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(count, base, 0, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(count, ApInt(uint64_t{0x1F}, 64), MicroOp::And, MicroOpBits::B8);
    builder.emitLoadRegMem(value, base, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(value, count, MicroOp::ShiftRight, MicroOpBits::B64);
    builder.emitClearReg(zero, MicroOpBits::B64);
    builder.emitLoadRegReg(count64, count, MicroOpBits::B64);
    builder.emitCmpRegImm(count64, ApInt(uint64_t{64}, 64), MicroOpBits::B64);
    builder.emitLoadCondRegReg(value, zero, MicroCond::AboveOrEqual, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 16, value, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_CompareRereadsKeepOriginalAddressValues)
{
    constexpr MicroReg base       = MicroReg::virtualIntReg(1);
    constexpr MicroReg index      = MicroReg::virtualIntReg(2);
    constexpr MicroReg savedBase  = MicroReg::virtualIntReg(4);
    constexpr MicroReg savedIndex = MicroReg::virtualIntReg(6);
    constexpr MicroReg otherBase  = MicroReg::virtualIntReg(7);
    constexpr MicroReg otherIndex = MicroReg::virtualIntReg(8);
    constexpr MicroReg loaded     = MicroReg::virtualIntReg(20);
    for (const bool sameCell : {false, true})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadRegImm(base, ApInt(0x1000, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(index, ApInt(3, 64), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(3), base, MicroOpBits::B64);
        builder.emitLoadRegReg(savedBase, MicroReg::virtualIntReg(3), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(5), index, MicroOpBits::B64);
        builder.emitLoadRegReg(savedIndex, MicroReg::virtualIntReg(5), MicroOpBits::B64);
        builder.emitLoadRegImm(otherBase, ApInt(0x2000, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(otherIndex, ApInt(5, 64), MicroOpBits::B64);
        builder.emitLoadAmcRegMem(loaded, MicroOpBits::B32, savedBase, savedIndex, 4, 0, MicroOpBits::B64);
        const auto loadRef = builder.instructions().lastInstructionRef();
        builder.emitCmpRegImm(loaded, ApInt(7, 32), MicroOpBits::B32);
        const auto compareRef = builder.instructions().lastInstructionRef();
        // A failed base match must not resolve the index at the candidate,
        // and a failed index match must not replace the original base value.
        builder.emitLoadAmcRegMem(MicroReg::virtualIntReg(21), MicroOpBits::B32, otherBase, savedIndex, 4, 0, MicroOpBits::B64);
        builder.emitLoadAmcRegMem(MicroReg::virtualIntReg(22), MicroOpBits::B32, savedBase, otherIndex, 4, 0, MicroOpBits::B64);
        builder.emitLoadRegImm(base, ApInt(0x3000, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(index, ApInt(9, 64), MicroOpBits::B64);
        builder.emitLoadAmcRegMem(MicroReg::virtualIntReg(23), MicroOpBits::B32, base, index, 4, 0, MicroOpBits::B64);
        builder.emitLoadAmcRegMem(MicroReg::virtualIntReg(24), MicroOpBits::B32, savedBase, sameCell ? savedIndex : index, 4, 0, MicroOpBits::B64);
        builder.emitRet();

        MicroSsaState ssa;
        ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
        InstructionCombine::Context context;
        context.builder   = &builder;
        context.storage   = &builder.instructions();
        context.operands  = &builder.operands();
        context.ssa       = &ssa;
        const bool folded = InstructionCombine::tryFoldAmcLoadIntoCompare(context, loadRef, *builder.instructions().ptr(loadRef));
        if (folded == sameCell || context.actions.size() != (sameCell ? 0 : 2))
            return Result::Error;
        if (!sameCell)
        {
            const auto& rewrite = context.actions[0];
            const auto& erase   = context.actions[1];
            if (rewrite.ref != compareRef || rewrite.newOp != MicroInstrOpcode::CmpAmcImm || rewrite.ops[0].reg != savedBase || rewrite.ops[1].reg != savedIndex ||
                rewrite.ops[2].opBits != MicroOpBits::B32 || erase.ref != loadRef || !erase.erase)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_LoadFoldWindowStartsAfterAnchor)
{
    for (const uint32_t gap : {15u, 16u})
    {
        const MicroReg accumulator = MicroReg::virtualIntReg(1);
        const MicroReg loaded      = MicroReg::virtualIntReg(2);
        MicroBuilder   builder(ctx);
        for (uint32_t i = 0; i < 24; ++i)
            builder.emitNop();
        const MicroInstrRef erasedPrefix = builder.instructions().lastInstructionRef();
        builder.emitLoadRegReg(accumulator, MicroReg::intReg(9), MicroOpBits::B64);
        builder.emitLoadRegMem(loaded, MicroReg::intReg(8), 0, MicroOpBits::B64);
        const MicroInstrRef load = builder.instructions().lastInstructionRef();
        for (uint32_t i = 0; i < gap; ++i)
            builder.emitNop();
        builder.emitOpBinaryRegReg(accumulator, loaded, MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(MicroReg::intReg(10), 0, accumulator, MicroOpBits::B64);
        builder.emitRet();
        // Live layout differs from slot order and contains an erased prefix.
        builder.instructions().erase(erasedPrefix);
        builder.instructions().insertSyntheticBefore(builder.operands(), load, MicroInstrOpcode::Nop, {});

        SWC_RESULT(runInstCombinePass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != (gap == 15 ? 1 : 0))
            return Result::Error;
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != (gap == 15 ? 0 : 1))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_InPlaceWindowIncludesAnchor)
{
    for (const uint32_t gap : {29u, 30u})
    {
        const MicroReg accumulator = MicroReg::virtualIntReg(1);
        const MicroReg temporary   = MicroReg::virtualIntReg(2);
        MicroBuilder   builder(ctx);
        for (uint32_t i = 0; i < 24; ++i)
            builder.emitNop();
        builder.emitLoadRegReg(accumulator, MicroReg::intReg(9), MicroOpBits::B64);
        builder.emitLoadRegReg(temporary, accumulator, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(temporary, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
        for (uint32_t i = 0; i < gap; ++i)
            builder.emitNop();
        builder.emitLoadRegReg(accumulator, temporary, MicroOpBits::B64);
        builder.emitLoadMemReg(MicroReg::intReg(8), 0, accumulator, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runInstCombinePass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != (gap == 29 ? 1 : 3))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_VectorPlans_KeepFreshRegistersAcrossRollback)
{
    for (const bool rejectedPrefix : {false, true})
    {
        constexpr MicroReg base = MicroReg::virtualIntReg(1);
        MicroBuilder       builder(ctx);
        builder.emitLoadRegReg(base, CallConv::get(CallConvKind::Swag).stackPointer, MicroOpBits::B64);
        if (rejectedPrefix)
        {
            // Four different immediates require more instructions than their
            // stores and load. The rejected plan must release its scratch names.
            for (uint32_t lane = 0; lane < 4; ++lane)
                builder.emitLoadMemImm(base, 0x20 + lane * 4, ApInt(lane + 1, 32), MicroOpBits::B32);
            builder.emitLoadVecRegMem(MicroReg::virtualFloatReg(3), base, 0x20, MicroOpBits::B128);
        }
        for (uint32_t group = 0; group < 2; ++group)
        {
            for (uint32_t lane = 0; lane < 4; ++lane)
                builder.emitLoadMemImm(base, 0x40 + group * 0x20 + lane * 4, ApInt(7 + group * 2, 32), MicroOpBits::B32);
            builder.emitLoadVecRegMem(MicroReg::virtualFloatReg(group + 1), base, 0x40 + group * 0x20, MicroOpBits::B128);
        }
        // The first plan must also respect registers occurring later in the IR.
        builder.emitLoadRegImm(MicroReg::virtualIntReg(900), ApInt(1234, 64), MicroOpBits::B64);
        builder.emitClearReg(MicroReg::virtualFloatReg(800), MicroOpBits::B128);
        builder.emitRet();

        std::unordered_set<uint32_t> originalRefs;
        for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
            originalRefs.insert(it.current.get());
        SWC_RESULT(runInstCombinePass(builder));

        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemImm) != (rejectedPrefix ? 4 : 0) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != (rejectedPrefix ? 1 : 0) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::VecShuffleRegRegImm) != 2)
            return Result::Error;

        std::unordered_set<uint32_t> generatedInts;
        std::unordered_set<uint32_t> generatedFloats;
        for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
        {
            if (originalRefs.contains(it.current.get()))
                continue;
            const auto useDef = it->collectUseDef(builder.operands(), nullptr);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg.isVirtualInt() && (reg.index() <= 900 || !generatedInts.insert(reg.index()).second))
                    return Result::Error;
                if (reg.isVirtualFloat() && (reg.index() <= 800 || !generatedFloats.insert(reg.index()).second))
                    return Result::Error;
            }
        }
        if (generatedInts.size() != 2 || !generatedInts.contains(901) || !generatedInts.contains(902) ||
            generatedFloats.size() != 2 || !generatedFloats.contains(801))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_ComplementaryShiftsToRotate)
{
    for (const MicroOpBits shiftBits : {MicroOpBits::B32, MicroOpBits::B64})
        for (const bool narrow : {false, true})
            for (const bool leftFirst : {false, true})
                for (const bool resultCopy : {false, true})
                    for (uint32_t test = 0; test < 7; ++test)
                    {
                        if (narrow && shiftBits != MicroOpBits::B64)
                            continue;
                        const MicroOpBits  bits = narrow ? MicroOpBits::B32 : shiftBits;
                        MicroBuilder       builder(ctx);
                        constexpr MicroReg source = MicroReg::virtualIntReg(1);
                        constexpr MicroReg alias  = MicroReg::virtualIntReg(2);
                        constexpr MicroReg lhs    = MicroReg::virtualIntReg(3);
                        constexpr MicroReg rhs    = MicroReg::virtualIntReg(4);
                        constexpr MicroReg output = MicroReg::virtualIntReg(5);
                        const MicroOp      first  = leftFirst ? MicroOp::ShiftLeft : MicroOp::ShiftRight;
                        const MicroOp      second = leftFirst ? MicroOp::ShiftRight : MicroOp::ShiftLeft;
                        builder.emitLoadRegMem(source, MicroReg::intReg(8), 0, narrow && test != 6 ? MicroOpBits::B32 : shiftBits);
                        builder.emitLoadRegReg(alias, source, MicroOpBits::B64);
                        builder.emitLoadRegReg(lhs, alias, shiftBits);
                        builder.emitOpBinaryRegImm(lhs, ApInt(6, 64), first, shiftBits);
                        if (test == 1)
                            builder.emitSetCondReg(MicroReg::virtualIntReg(6), MicroCond::Zero);
                        if (test == 3)
                            builder.emitLoadMemReg(MicroReg::intReg(9), 0, lhs, shiftBits);
                        if (test == 4)
                            builder.emitLoadRegMem(alias, MicroReg::intReg(8), 8, shiftBits);
                        builder.emitLoadRegReg(rhs, alias, shiftBits);
                        builder.emitOpBinaryRegImm(rhs, ApInt(getNumBits(bits) - (test == 5 ? 7 : 6), 64), second, shiftBits);
                        const MicroReg dst = resultCopy ? output : lhs;
                        if (resultCopy)
                            builder.emitLoadRegReg(output, lhs, shiftBits);
                        builder.emitOpBinaryRegReg(dst, rhs, MicroOp::Or, bits);
                        if (test == 2)
                            builder.emitSetCondReg(MicroReg::virtualIntReg(7), MicroCond::Zero);
                        builder.emitLoadMemReg(MicroReg::intReg(9), 8, dst, bits);
                        builder.emitRet();
                        SWC_RESULT(runInstCombinePass(builder));
                        uint32_t rotates = 0;
                        for (const MicroInstr& inst : builder.instructions().view())
                        {
                            const auto* ops = inst.ops(builder.operands());
                            if (inst.op == MicroInstrOpcode::OpBinaryRegImm &&
                                (ops[2].microOp == MicroOp::RotateLeft || ops[2].microOp == MicroOp::RotateRight))
                            {
                                ++rotates;
                                if (ops[1].opBits != bits || ops[3].valueU64 != 6)
                                    return Result::Error;
                            }
                        }
                        const bool expected = test == 0 || (test == 6 && !narrow);
                        if (rotates != (expected ? 1u : 0u))
                            return Result::Error;
                    }
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    uint32_t countUnaryMicroOp(const MicroBuilder& builder, MicroOp op)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::OpUnaryReg && ops && ops[2].microOp == op)
                ++count;
        }
        return count;
    }
}

SWC_TEST_BEGIN(InstCombine_SignExtendOfLoad_FoldsIntoLoad)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2   = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 8, MicroOpBits::B32);
    builder.emitLoadSignedExtendRegReg(v2, v1, MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 16, v2, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadSignedExtRegMem) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(InstCombine_ZeroExtendOfByteLoad_FoldsIntoLoad)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 3, MicroOpBits::B8);
    builder.emitLoadZeroExtendRegReg(v1, v1, MicroOpBits::B32, MicroOpBits::B8);
    builder.emitLoadMemReg(base, 16, v1, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegMem) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The loaded value has a second reader: the load stays.
SWC_TEST_BEGIN(InstCombine_ExtendOfSharedLoad_Kept)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2   = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 8, MicroOpBits::B16);
    builder.emitLoadSignedExtendRegReg(v2, v1, MicroOpBits::B64, MicroOpBits::B16);
    builder.emitLoadMemReg(base, 16, v2, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 24, v1, MicroOpBits::B16);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// ~(x - 1) -> -x
SWC_TEST_BEGIN(InstCombine_ComplementOfDecrement_BecomesNegate)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    constexpr MicroReg v2   = MicroReg::virtualIntReg(3);
    constexpr MicroReg v3   = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 0, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(v2, v1, UINT64_MAX, MicroOpBits::B64);
    builder.emitLoadRegReg(v3, v2, MicroOpBits::B64);
    builder.emitOpUnaryReg(v3, MicroOp::BitwiseNot, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 8, v3, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countUnaryMicroOp(builder, MicroOp::Negate) != 1 || countUnaryMicroOp(builder, MicroOp::BitwiseNot) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The decrement is read elsewhere: the complement stays.
SWC_TEST_BEGIN(InstCombine_ComplementOfSharedDecrement_Kept)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg v1   = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(v1, base, 0, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(v1, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 4, v1, MicroOpBits::B32);
    builder.emitOpUnaryReg(v1, MicroOp::BitwiseNot, MicroOpBits::B32);
    builder.emitLoadMemReg(base, 8, v1, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countUnaryMicroOp(builder, MicroOp::BitwiseNot) != 1 || countUnaryMicroOp(builder, MicroOp::Negate) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The widened boolean only reaches a byte copy and a join nothing else reads
// through: its extension is dead.
SWC_TEST_BEGIN(InstCombine_ExtendReadThroughJoinAsByte_Erased)
{
    constexpr MicroReg base   = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg first  = MicroReg::virtualIntReg(3);
    constexpr MicroReg merged = MicroReg::virtualIntReg(4);
    constexpr MicroReg second = MicroReg::virtualIntReg(5);
    constexpr MicroReg wide   = MicroReg::virtualIntReg(6);
    MicroBuilder       builder(ctx);
    const auto         label = builder.createLabel();

    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
    builder.emitCmpRegImm(value, ApInt(0, 64), MicroOpBits::B64);
    builder.emitSetCondReg(first, MicroCond::NotEqual);
    builder.emitLoadRegReg(merged, first, MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, label);
    builder.emitCmpRegImm(value, ApInt(1, 64), MicroOpBits::B64);
    builder.emitSetCondReg(second, MicroCond::Equal);
    builder.emitLoadZeroExtendRegReg(second, second, MicroOpBits::B32, MicroOpBits::B8);
    builder.emitLoadRegReg(merged, second, MicroOpBits::B8);
    builder.placeLabel(label);
    builder.emitLoadZeroExtendRegReg(wide, merged, MicroOpBits::B64, MicroOpBits::B8);
    builder.emitLoadMemReg(base, 8, wide, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    bool hasLoadRegRegBits(const MicroBuilder& builder, MicroReg dst, MicroOpBits bits)
    {
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::LoadRegReg && ops && ops[0].reg == dst && ops[2].opBits == bits)
                return true;
        }
        return false;
    }
}

// A byte selected on two paths and read back only as a byte is moved at 32
// bits on both.
SWC_TEST_BEGIN(InstCombine_ByteSelectReadAsByte_WidensToDword)
{
    constexpr MicroReg base   = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg merged = MicroReg::virtualIntReg(3);
    constexpr MicroReg wide   = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);
    const auto         other = builder.createLabel();
    const auto         done  = builder.createLabel();

    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B8);
    builder.emitCmpRegImm(value, ApInt(3, 64), MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, other);
    builder.emitLoadRegImm(merged, ApInt(0xFF, 64), MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
    builder.placeLabel(other);
    builder.emitLoadRegReg(merged, value, MicroOpBits::B8);
    builder.placeLabel(done);
    builder.emitLoadZeroExtendRegReg(wide, merged, MicroOpBits::B64, MicroOpBits::B8);
    builder.emitLoadMemReg(base, 8, wide, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (!hasLoadRegRegBits(builder, merged, MicroOpBits::B32))
        return Result::Error;
    bool wideImmediate = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadRegImm && ops && ops[0].reg == merged)
            wideImmediate = ops[1].opBits == MicroOpBits::B32 && ops[2].valueU64 == 0xFF;
    }
    if (!wideImmediate)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The joined byte is read at 32 bits: the byte writes keep their width.
SWC_TEST_BEGIN(InstCombine_ByteSelectReadWide_Kept)
{
    constexpr MicroReg base   = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg merged = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    const auto         other = builder.createLabel();
    const auto         done  = builder.createLabel();

    builder.emitLoadRegMem(merged, base, 16, MicroOpBits::B32);
    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B8);
    builder.emitCmpRegImm(value, ApInt(3, 64), MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, other);
    builder.emitLoadRegImm(merged, ApInt(0x7F, 64), MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
    builder.placeLabel(other);
    builder.emitLoadRegReg(merged, value, MicroOpBits::B8);
    builder.placeLabel(done);
    builder.emitLoadMemReg(base, 8, merged, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (!hasLoadRegRegBits(builder, merged, MicroOpBits::B8))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // fb = sp; x, y read from the frame; [fb] = 0; [fb] = x; [fb + 4] = y; v = [fb]
    void emitPairThroughFrame(MicroBuilder& builder, bool escape)
    {
        constexpr MicroReg fb    = MicroReg::virtualIntReg(1);
        constexpr MicroReg x     = MicroReg::virtualIntReg(2);
        constexpr MicroReg y     = MicroReg::virtualIntReg(3);
        constexpr MicroReg value = MicroReg::virtualIntReg(4);
        constexpr MicroReg addr  = MicroReg::virtualIntReg(5);

        builder.emitLoadRegReg(fb, CallConv::get(CallConvKind::Swag).stackPointer, MicroOpBits::B64);
        builder.emitLoadRegMem(x, fb, 32, MicroOpBits::B32);
        builder.emitLoadRegMem(y, fb, 36, MicroOpBits::B32);
        builder.emitLoadMemImm(fb, 0, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(fb, 0, x, MicroOpBits::B32);
        builder.emitLoadMemReg(fb, 4, y, MicroOpBits::B32);
        if (escape)
        {
            builder.emitLoadAddressRegMem(addr, fb, 0, MicroOpBits::B64);
            builder.emitLoadMemReg(fb, 24, addr, MicroOpBits::B64);
        }
        builder.emitLoadRegMem(value, fb, 0, MicroOpBits::B64);
        builder.emitLoadMemReg(fb, 16, value, MicroOpBits::B64);
        builder.emitRet();
    }
}

SWC_TEST_BEGIN(InstCombine_PairBuiltInFrame_AssembledInRegister)
{
    MicroBuilder builder(ctx);
    emitPairThroughFrame(builder, false);

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 2)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemImm) != 0)
        return Result::Error;
    if (countBinaryMicroOp(builder, MicroOp::Or) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The slot's address escapes: the aggregate stays in memory.
SWC_TEST_BEGIN(InstCombine_PairWithEscapedSlot_Kept)
{
    MicroBuilder builder(ctx);
    emitPairThroughFrame(builder, true);

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 3)
        return Result::Error;
    if (countBinaryMicroOp(builder, MicroOp::Or) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A boolean merged from two setcc results stays a byte: branch
// simplification reads those merges at byte width.
SWC_TEST_BEGIN(InstCombine_BooleanMergeCopy_KeepsByteWidth)
{
    constexpr MicroReg base   = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg first  = MicroReg::virtualIntReg(3);
    constexpr MicroReg second = MicroReg::virtualIntReg(4);
    constexpr MicroReg merged = MicroReg::virtualIntReg(5);
    constexpr MicroReg wide   = MicroReg::virtualIntReg(6);
    MicroBuilder       builder(ctx);
    const auto         done = builder.createLabel();

    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
    builder.emitCmpRegImm(value, ApInt(0, 64), MicroOpBits::B64);
    builder.emitSetCondReg(first, MicroCond::NotEqual);
    builder.emitLoadRegReg(merged, first, MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, done);
    builder.emitCmpRegImm(value, ApInt(5, 64), MicroOpBits::B64);
    builder.emitSetCondReg(second, MicroCond::Less);
    builder.emitLoadRegReg(merged, second, MicroOpBits::B8);
    builder.placeLabel(done);
    builder.emitLoadZeroExtendRegReg(wide, merged, MicroOpBits::B64, MicroOpBits::B8);
    builder.emitLoadMemReg(base, 8, wide, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (hasLoadRegRegBits(builder, merged, MicroOpBits::B32) || !hasLoadRegRegBits(builder, merged, MicroOpBits::B8))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// cmp's left operand loaded just before it: the compare reads memory.
SWC_TEST_BEGIN(InstCombine_LeftCompareLoad_FoldsIntoMemoryCompare)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg left  = MicroReg::virtualIntReg(2);
    constexpr MicroReg right = MicroReg::virtualIntReg(3);
    constexpr MicroReg flag  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegMem(right, base, 8, MicroOpBits::B8);
    builder.emitLoadRegMem(left, base, 2, MicroOpBits::B8);
    builder.emitCmpRegReg(left, right, MicroOpBits::B8);
    builder.emitSetCondReg(flag, MicroCond::Less);
    builder.emitLoadMemReg(base, 16, flag, MicroOpBits::B8);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpMemReg) != 1 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Folding the right operand would reverse the compare: it stays a register.
SWC_TEST_BEGIN(InstCombine_RightCompareLoad_Kept)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg left  = MicroReg::virtualIntReg(2);
    constexpr MicroReg right = MicroReg::virtualIntReg(3);
    constexpr MicroReg flag  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegReg(left, base, MicroOpBits::B64);
    builder.emitLoadRegMem(right, base, 8, MicroOpBits::B64);
    builder.emitCmpRegReg(left, right, MicroOpBits::B64);
    builder.emitSetCondReg(flag, MicroCond::Less);
    builder.emitLoadMemReg(base, 16, flag, MicroOpBits::B8);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpMemReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // (x >> 24) | ((x >> 8) & 0xFF00) | ((x << 8) & middle) | (x << 24)
    void emitDwordSwap(MicroBuilder& builder, uint64_t middleMask)
    {
        constexpr MicroReg base = MicroReg::virtualIntReg(1);
        constexpr MicroReg x    = MicroReg::virtualIntReg(2);
        constexpr MicroReg a    = MicroReg::virtualIntReg(3);
        constexpr MicroReg b    = MicroReg::virtualIntReg(4);
        constexpr MicroReg c    = MicroReg::virtualIntReg(5);
        constexpr MicroReg d    = MicroReg::virtualIntReg(6);

        builder.emitLoadRegMem(x, base, 0, MicroOpBits::B32);
        builder.emitLoadRegReg(a, x, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(a, ApInt(24, 64), MicroOp::ShiftRight, MicroOpBits::B32);
        builder.emitLoadRegReg(b, x, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(b, ApInt(8, 64), MicroOp::ShiftRight, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(b, ApInt(0xFF00, 64), MicroOp::And, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(a, b, MicroOp::Or, MicroOpBits::B32);
        builder.emitLoadRegReg(c, x, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(c, ApInt(8, 64), MicroOp::ShiftLeft, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(c, ApInt(middleMask, 64), MicroOp::And, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(a, c, MicroOp::Or, MicroOpBits::B32);
        builder.emitLoadRegReg(d, x, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(d, ApInt(24, 64), MicroOp::ShiftLeft, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(a, d, MicroOp::Or, MicroOpBits::B32);
        builder.emitLoadMemReg(base, 8, a, MicroOpBits::B32);
        builder.emitRet();
    }
}

SWC_TEST_BEGIN(InstCombine_ByteSwapIdiom_BecomesByteSwap)
{
    MicroBuilder builder(ctx);
    emitDwordSwap(builder, 0xFF0000);

    SWC_RESULT(runInstCombinePass(builder));

    if (countUnaryMicroOp(builder, MicroOp::ByteSwap) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The third byte is masked off: not a byte swap.
SWC_TEST_BEGIN(InstCombine_ByteSwapWithMissingByte_Kept)
{
    MicroBuilder builder(ctx);
    emitDwordSwap(builder, 0xFF00000);

    SWC_RESULT(runInstCombinePass(builder));

    if (countUnaryMicroOp(builder, MicroOp::ByteSwap) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
