#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.ConstantFolding.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runConstantFoldingPass(MicroBuilder& builder)
    {
        MicroConstantFoldingPass pass;
        MicroPassManager         passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

}

// load v1, 5; add v1, 3  ->  load v1, 8 (folded semantically)
SWC_TEST_BEGIN(ConstantFolding_FoldBinaryRegImm)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(5, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    // The add is folded into a LoadRegImm. The original load is now dead
    // (removed by DCE later). We expect: load v1,5; load v1,8; ret.
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// load v1, 42; mov v2, v1  ->  load v1, 42; load v2, 42
SWC_TEST_BEGIN(ConstantFolding_FoldCopyFromKnown)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    constexpr MicroReg v2 = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(42, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v2, v1, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 2)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// load v1, 5; add v1, 3; shl v1, 2  ->  three LoadRegImm (5, 8, 32)
SWC_TEST_BEGIN(ConstantFolding_ChainedFold)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(5, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(2, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    // Each binary op is folded into a LoadRegImm. Dead loads removed by DCE later.
    // Result: load v1,5; load v1,8; load v1,32; ret.
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 3)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// clear v1; add v1, 7  ->  load v1, 7  (ClearReg tracked as v1=0)
SWC_TEST_BEGIN(ConstantFolding_FoldFromClearReg)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitClearReg(v1, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(7, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Fold through a phi-like merge when both incoming branch values are the same constant.
SWC_TEST_BEGIN(ConstantFolding_FoldAcrossJoinSameConstant)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, labelThen);
    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitOpBinaryRegImm(v1, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 3)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantFolding_BinaryRequiresKnownInputsAndDeadFlags)
{
    for (const bool regOperand : {false, true})
    {
        for (const bool known : {false, true})
        {
            for (const bool liveFlags : {false, true})
            {
                constexpr MicroReg lhs = MicroReg::virtualIntReg(1);
                constexpr MicroReg rhs = MicroReg::virtualIntReg(2);
                MicroBuilder       builder(ctx);
                if (known)
                    builder.emitLoadRegImm(lhs, ApInt(5, 64), MicroOpBits::B64);
                else
                    builder.emitLoadRegReg(lhs, MicroReg::intReg(1), MicroOpBits::B64);
                if (regOperand)
                {
                    builder.emitLoadRegImm(rhs, ApInt(3, 64), MicroOpBits::B64);
                    builder.emitOpBinaryRegReg(lhs, rhs, MicroOp::Add, MicroOpBits::B64);
                }
                else
                    builder.emitOpBinaryRegImm(lhs, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
                if (liveFlags)
                    builder.emitSetCondReg(MicroReg::virtualIntReg(3), MicroCond::Zero);
                builder.emitRet();

                SWC_RESULT(runConstantFoldingPass(builder));
                const auto opcode = regOperand ? MicroInstrOpcode::OpBinaryRegReg : MicroInstrOpcode::OpBinaryRegImm;
                if (Backend::Unittest::countOpcode(builder, opcode) != (known && !liveFlags ? 0 : 1))
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantFolding_PropagatesInDominatorOrderWithoutPhis)
{
    constexpr MicroReg source = MicroReg::virtualIntReg(1);
    constexpr MicroReg copy1  = MicroReg::virtualIntReg(2);
    constexpr MicroReg copy2  = MicroReg::virtualIntReg(3);
    constexpr MicroReg orphan = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);
    const auto         body  = builder.createLabel();
    const auto         setup = builder.createLabel();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, setup);
    builder.placeLabel(body);
    builder.emitLoadRegReg(copy1, source, MicroOpBits::B64);
    const auto firstCopy = builder.instructions().lastInstructionRef();
    builder.emitLoadRegReg(copy2, copy1, MicroOpBits::B64);
    const auto secondCopy = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, copy2, MicroOpBits::B64);
    const auto store = builder.instructions().lastInstructionRef();
    builder.emitRet();
    builder.placeLabel(setup);
    builder.emitLoadRegImm(source, ApInt(42, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, body);
    // This separate root must not inherit the definition from the first one.
    builder.emitLoadRegReg(orphan, source, MicroOpBits::B64);
    const auto orphanCopy = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(MicroReg::intReg(2), 8, orphan, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));
    for (const auto ref : {firstCopy, secondCopy})
    {
        const auto* inst = builder.instructions().ptr(ref);
        if (!inst || inst->op != MicroInstrOpcode::LoadRegImm || inst->ops(builder.operands())[2].valueU64 != 42)
            return Result::Error;
    }
    if (builder.instructions().ptr(store)->ops(builder.operands())[1].reg != copy2)
        return Result::Error;
    const auto* unresolved = builder.instructions().ptr(orphanCopy);
    if (!unresolved || unresolved->op != MicroInstrOpcode::LoadRegReg || unresolved->ops(builder.operands())[1].reg != source)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantFolding_LazyAddressesKeepFilteredRelocationOrder)
{
    enum class Case
    {
        KnownAddress,
        RejectedRelocations,
        NoRelocations,
    };
    std::array<std::byte, 16> source{};
    source[0] = std::byte{0x11};
    source[4] = std::byte{0x80};
    source[5] = std::byte{0x12};
    source[6] = std::byte{0x34};
    source[7] = std::byte{0x56};
    source[8] = std::byte{0x22};
    std::array           dims{source.size()};
    const TypeRef        arrayType    = ctx.typeMgr().addType(TypeInfo::makeArray(std::span<uint64_t>{dims}, ctx.typeMgr().typeU8()));
    const ConstantRef    constantRef  = ctx.cstMgr().addConstant(ctx, ConstantValue::makeArrayBorrowed(ctx, arrayType, std::span{source.data(), source.size()}));
    const ConstantValue& constant     = ctx.cstMgr().get(constantRef);
    const uint64_t       addressValue = reinterpret_cast<uint64_t>(constant.getArray().data());
    constexpr MicroReg   address      = MicroReg::virtualIntReg(1);

    for (const Case test : {Case::KnownAddress, Case::RejectedRelocations, Case::NoRelocations})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadRegImm(MicroReg::virtualIntReg(10), ApInt(42, 64), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(11), MicroReg::virtualIntReg(10), MicroOpBits::B64);
        const auto copy = builder.instructions().lastInstructionRef();
        builder.emitLoadRegPtrReloc(address, addressValue, constantRef);
        MicroRelocation relocation = builder.codeRelocations().back();
        relocation.targetAddress += 4;
        relocation.constantOffset += 4;
        builder.addRelocation(relocation);
        // Later entries rejected by the collector must not replace offset 4.
        relocation.targetAddress += 4;
        relocation.constantOffset += 4;
        relocation.form = MicroRelocation::Form::Relative32;
        builder.addRelocation(relocation);
        relocation.form          = MicroRelocation::Form::Absolute64;
        relocation.targetAddress = 0;
        builder.addRelocation(relocation);
        if (test == Case::RejectedRelocations)
        {
            for (auto& entry : builder.codeRelocations())
                entry.form = MicroRelocation::Form::Relative32;
        }
        else if (test == Case::NoRelocations)
            builder.codeRelocations().clear();

        builder.emitLoadRegMem(MicroReg::virtualFloatReg(1), address, 0, MicroOpBits::B128);
        const auto packed = builder.instructions().lastInstructionRef();
        // The first admissible load has no constant address. Later loads must
        // still see the table initialized at this failed candidate.
        builder.emitLoadRegMem(MicroReg::virtualIntReg(12), MicroReg::intReg(2), 0, MicroOpBits::B32);
        const auto unknown = builder.instructions().lastInstructionRef();
        builder.emitLoadRegMem(MicroReg::virtualIntReg(2), address, 0, MicroOpBits::B8);
        const auto byte = builder.instructions().lastInstructionRef();
        builder.emitLoadRegMem(MicroReg::virtualIntReg(3), address, 0, MicroOpBits::B32);
        const auto dword = builder.instructions().lastInstructionRef();
        builder.emitLoadSignedExtendRegMem(MicroReg::virtualIntReg(4), address, 0, MicroOpBits::B64, MicroOpBits::B8);
        const auto signedByte = builder.instructions().lastInstructionRef();
        builder.emitLoadZeroExtendRegMem(MicroReg::virtualIntReg(5), address, 0, MicroOpBits::B32, MicroOpBits::B8);
        const auto unsignedByte = builder.instructions().lastInstructionRef();
        builder.emitRet();

        // Duplicate and absent relocations deliberately exercise the collector;
        // they do not satisfy the full pipeline's one-relocation invariant.
        MicroPassContext passContext;
        passContext.taskContext  = &ctx;
        passContext.builder      = &builder;
        passContext.instructions = &builder.instructions();
        passContext.operands     = &builder.operands();
        passContext.callConvKind = CallConvKind::Swag;
        MicroConstantFoldingPass pass;
        SWC_RESULT(pass.run(passContext));
        const auto* copyInst = builder.instructions().ptr(copy);
        if (!copyInst || copyInst->op != MicroInstrOpcode::LoadRegImm || copyInst->ops(builder.operands())[2].valueU64 != 42)
            return Result::Error;
        const auto* packedInst  = builder.instructions().ptr(packed);
        const auto* unknownInst = builder.instructions().ptr(unknown);
        if (!packedInst || packedInst->op != MicroInstrOpcode::LoadRegMem || packedInst->ops(builder.operands())[2].opBits != MicroOpBits::B128 ||
            !unknownInst || unknownInst->op != MicroInstrOpcode::LoadRegMem)
            return Result::Error;

        const std::array              refs{byte, dword, signedByte, unsignedByte};
        const std::array              widths{MicroOpBits::B8, MicroOpBits::B32, MicroOpBits::B64, MicroOpBits::B32};
        const std::array<uint64_t, 4> expected{0x80, 0x56341280, 0xFFFFFFFFFFFFFF80, 0x80};
        const std::array              originalOps{MicroInstrOpcode::LoadRegMem, MicroInstrOpcode::LoadRegMem, MicroInstrOpcode::LoadSignedExtRegMem, MicroInstrOpcode::LoadZeroExtRegMem};
        for (size_t i = 0; i < refs.size(); ++i)
        {
            const auto* inst = builder.instructions().ptr(refs[i]);
            if (!inst)
                return Result::Error;
            if (test == Case::KnownAddress)
            {
                const auto* ops = inst->ops(builder.operands());
                if (inst->op != MicroInstrOpcode::LoadRegImm || ops[1].opBits != widths[i] || ops[2].valueU64 != expected[i])
                    return Result::Error;
            }
            else if (inst->op != originalOps[i])
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
