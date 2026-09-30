#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.ColdBlockLayout.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runColdBlockLayoutPass(MicroBuilder& builder, MicroPassContext& passContext)
    {
        MicroColdBlockLayoutPass pass;
        MicroPassManager         passManager;
        passManager.addStartPass(pass);

        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    SymbolFunction makeCallee(TaskContext& ctx, const bool isReport)
    {
        const IdentifierRef idRef = isReport ? ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SafetyPanic) : IdentifierRef::invalid();
        return SymbolFunction(nullptr, TokenRef::invalid(), idRef, SymbolFlagsE::Zero);
    }

    std::vector<MicroInstrRef> listing(const MicroBuilder& builder)
    {
        std::vector<MicroInstrRef> order;
        for (auto it = builder.instructions().view().begin(), endIt = builder.instructions().view().end(); it != endIt; ++it)
            order.push_back(it.current);
        return order;
    }

    uint32_t positionOf(const std::vector<MicroInstrRef>& order, const MicroInstrRef ref)
    {
        return static_cast<uint32_t>(std::ranges::find(order, ref) - order.begin());
    }
}

// A guard that jumps over its report keeps the test and takes the inverted jump
// to the report, which now sits behind the return and comes back by a jump.
SWC_TEST_BEGIN(ColdBlockLayout_MovesSkippedReportBehindReturn)
{
    constexpr MicroReg value = MicroReg::intReg(0);
    for (const bool isReport : {true, false})
    {
        SymbolFunction      callee = makeCallee(ctx, isReport);
        MicroBuilder        builder(ctx);
        const MicroLabelRef passed = builder.createLabel();
        builder.emitOpBinaryRegImm(value, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, passed);
        const MicroInstrRef guardRef = builder.instructions().lastInstructionRef();
        builder.emitCallLocal(&callee, CallConvKind::Swag);
        const MicroInstrRef callRef = builder.instructions().lastInstructionRef();
        builder.placeLabel(passed);
        builder.emitOpBinaryRegImm(value, ApInt(2, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitRet();
        const MicroInstrRef retRef = builder.instructions().lastInstructionRef();

        MicroPassContext passContext;
        SWC_RESULT(runColdBlockLayoutPass(builder, passContext));

        const auto order = listing(builder);
        const auto guard = builder.instructions().ptr(guardRef)->ops(builder.operands());
        if (!isReport)
        {
            if (order.size() != 6 || positionOf(order, callRef) > positionOf(order, retRef) ||
                guard[0].cpuCond != MicroCond::AboveOrEqual || passContext.coldTailRef.isValid())
                return Result::Error;
            continue;
        }

        // add, jb cold, passed:, add, ret, cold:, call, jmp passed
        if (order.size() != 8 || positionOf(order, callRef) != 6 || positionOf(order, retRef) != 4)
            return Result::Error;
        const MicroInstr* coldLabel = builder.instructions().ptr(order[5]);
        const MicroInstr* back      = builder.instructions().ptr(order[7]);
        if (coldLabel->op != MicroInstrOpcode::Label || back->op != MicroInstrOpcode::JumpCond || passContext.coldTailRef != order[5])
            return Result::Error;
        const auto backOps = back->ops(builder.operands());
        if (guard[0].cpuCond != MicroCond::Below || guard[2].valueU64 != coldLabel->ops(builder.operands())[0].valueU64 ||
            backOps[0].cpuCond != MicroCond::Unconditional || backOps[2].valueU64 != passed.get())
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// A report several tests branch to moves with its label, and the jump the
// passing path took over it disappears.
SWC_TEST_BEGIN(ColdBlockLayout_MovesLabeledReportAndDropsJumpOver)
{
    constexpr MicroReg  value  = MicroReg::intReg(0);
    SymbolFunction      callee = makeCallee(ctx, true);
    MicroBuilder        builder(ctx);
    const MicroLabelRef fail   = builder.createLabel();
    const MicroLabelRef done   = builder.createLabel();
    builder.emitCmpRegImm(value, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, fail);
    builder.emitCmpRegImm(value, ApInt(255, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Greater, MicroOpBits::B32, fail);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
    const MicroInstrRef overRef = builder.instructions().lastInstructionRef();
    builder.placeLabel(fail);
    builder.emitCallLocal(&callee, CallConvKind::Swag);
    const MicroInstrRef callRef = builder.instructions().lastInstructionRef();
    builder.placeLabel(done);
    builder.emitRet();
    const MicroInstrRef retRef = builder.instructions().lastInstructionRef();

    MicroPassContext passContext;
    SWC_RESULT(runColdBlockLayoutPass(builder, passContext));

    // cmp, jl fail, cmp, jg fail, done:, ret, fail:, call, jmp done
    const auto order = listing(builder);
    if (order.size() != 9 || builder.instructions().ptr(overRef) != nullptr ||
        positionOf(order, retRef) != 5 || positionOf(order, callRef) != 7)
        return Result::Error;
    const MicroInstr* failLabel = builder.instructions().ptr(order[6]);
    const MicroInstr* back      = builder.instructions().ptr(order[8]);
    if (failLabel->op != MicroInstrOpcode::Label || failLabel->ops(builder.operands())[0].valueU64 != fail.get() ||
        back->op != MicroInstrOpcode::JumpCond || back->ops(builder.operands())[2].valueU64 != done.get())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A report that ends with its own jump keeps it; one that holds a second way
// out, or that the function could fall into, stays where it is.
SWC_TEST_BEGIN(ColdBlockLayout_KeepsOwnJumpAndRejectsUnsafeShapes)
{
    constexpr MicroReg value = MicroReg::intReg(0);
    for (uint32_t mode = 0; mode < 3; ++mode)
    {
        SymbolFunction      callee  = makeCallee(ctx, true);
        MicroBuilder        builder(ctx);
        const MicroLabelRef nonZero = builder.createLabel();
        const MicroLabelRef done    = builder.createLabel();
        builder.emitCmpRegImm(value, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, nonZero);
        builder.emitCallLocal(&callee, CallConvKind::Swag);
        const MicroInstrRef callRef = builder.instructions().lastInstructionRef();
        if (mode == 1)
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, done);
        builder.emitClearReg(value, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
        builder.placeLabel(nonZero);
        builder.emitOpBinaryRegImm(value, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.placeLabel(done);
        if (mode != 2)
            builder.emitRet();
        const uint32_t countBefore = builder.instructions().count();

        MicroPassContext passContext;
        SWC_RESULT(runColdBlockLayoutPass(builder, passContext));

        const auto order = listing(builder);
        const bool moved = positionOf(order, callRef) + 3 == order.size();
        if (moved != (mode == 0) || passContext.coldTailRef.isValid() != moved)
            return Result::Error;
        // Only the label of the moved block is added: its own jump already leaves it.
        if (builder.instructions().count() != countBefore + (moved ? 1u : 0u) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != (mode == 1 ? 3u : 2u))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
