#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
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

SWC_TEST_BEGIN(InstructionCombine_KeepsUnsafeBooleanSelect)
{
    enum class Case
    {
        SharedSource,
        InterveningFlags,
        NarrowInitial,
        DifferentValues,
        NoComplement
    };
    for (const Case test : {Case::SharedSource, Case::InterveningFlags, Case::NarrowInitial, Case::DifferentValues, Case::NoComplement})
    {
        constexpr MicroReg dst = MicroReg::virtualIntReg(1);
        constexpr MicroReg src = MicroReg::virtualIntReg(2);
        MicroBuilder       builder(ctx);
        builder.emitLoadRegImm(dst, ApInt(test == Case::DifferentValues ? 2 : 1, 64), test == Case::NarrowInitial ? MicroOpBits::B8 : MicroOpBits::B64);
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

SWC_END_NAMESPACE();

#endif
