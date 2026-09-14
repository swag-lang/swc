#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.Sanity.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class ReturnAddressKind
    {
        Stack,
        NonStack,
    };

    Result runStackEscapeSanity(TaskContext& ctx, TypeRef returnTypeRef, ReturnAddressKind addressKind)
    {
        SymbolFunction function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        function.setReturnTypeRef(returnTypeRef);

        const CallConv& callConv  = CallConv::get(CallConvKind::Swag);
        const MicroReg  stackBase = MicroReg::virtualIntReg(1);
        MicroBuilder    builder(ctx);

        if (addressKind == ReturnAddressKind::Stack)
            builder.emitLoadAddressRegMem(callConv.intReturn, stackBase, 16, MicroOpBits::B64);
        else
            builder.emitLoadRegImm(callConv.intReturn, ApInt(1, 64), MicroOpBits::B64);
        builder.emitRet();

        MicroSanityPass  pass;
        MicroPassManager passManager;
        passManager.addPreRaAnalysisPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind             = CallConvKind::Swag;
        passContext.debugStackBaseVirtualReg = stackBase;
        passContext.sanitizerFunction        = &function;
        passContext.sanitizerSafetyMask      = static_cast<uint16_t>(Runtime::SafetyWhat::Memory);
        return builder.runPasses(passManager, nullptr, passContext);
    }

    Result runGuardedMoveSanity(TaskContext& ctx, bool replacePointer, bool guardIsEqual)
    {
        const MicroReg stackBase = MicroReg::virtualIntReg(1);
        const MicroReg address   = MicroReg::virtualIntReg(2);
        const MicroReg pointer   = MicroReg::virtualIntReg(3);
        const MicroReg reloaded  = MicroReg::virtualIntReg(4);
        const MicroReg value     = MicroReg::virtualIntReg(5);
        MicroBuilder   builder(ctx);

        builder.emitLoadAddressRegMem(address, stackBase, 16, MicroOpBits::B64);
        builder.emitLoadMemReg(stackBase, 0, address, MicroOpBits::B64);
        builder.emitSanityInvalidate(address, 8);
        builder.emitLoadRegMem(pointer, stackBase, 0, MicroOpBits::B64);
        builder.emitCmpRegImm(pointer, ApInt(0, 64), MicroOpBits::B64);
        const MicroLabelRef done = builder.createLabel();
        builder.emitJumpToLabel(guardIsEqual ? MicroCond::Equal : MicroCond::NotEqual, MicroOpBits::B32, done);
        if (replacePointer)
        {
            builder.emitLoadAddressRegMem(address, stackBase, 32, MicroOpBits::B64);
            builder.emitLoadMemReg(stackBase, 0, address, MicroOpBits::B64);
        }
        builder.emitLoadRegMem(reloaded, stackBase, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(value, reloaded, 0, MicroOpBits::B32);
        builder.placeLabel(done);
        builder.emitRet();

        MicroSanityPass  pass;
        MicroPassManager passManager;
        passManager.addPreRaAnalysisPass(pass);
        MicroPassContext passContext;
        passContext.callConvKind             = CallConvKind::Swag;
        passContext.debugStackBaseVirtualReg = stackBase;
        passContext.sanitizerSafetyMask      = static_cast<uint16_t>(Runtime::SafetyWhat::Lifecycle);
        return builder.runPasses(passManager, nullptr, passContext);
    }

    enum class WideCopyCase
    {
        Plain,
        Vector,
        IndexedStore,
        SelfCopy,
        SourceOverwritten,
        RegisterOverwritten,
        ScalarRegisterOverwrite,
        DestinationOverwritten,
        PartialDestinationWrite,
        NarrowSource,
        SameAcrossBranches,
        DifferentAcrossBranches,
        ZeroRegister,
        DenseFrameCopy,
        DenseFramePartialWrite,
        BooleanZeroGuard,
    };

    Result runWideCopySanity(TaskContext& ctx, WideCopyCase scenario)
    {
        const MicroReg stackBase = MicroReg::virtualIntReg(1);
        const MicroReg address   = MicroReg::virtualIntReg(2);
        const MicroReg other     = MicroReg::virtualIntReg(3);
        const MicroReg pointer   = MicroReg::virtualIntReg(4);
        const MicroReg value     = MicroReg::virtualIntReg(5);
        const MicroReg loaded    = MicroReg::virtualFloatReg(1);
        const MicroReg copied    = MicroReg::virtualFloatReg(2);
        MicroBuilder   builder(ctx);

        builder.emitLoadAddressRegMem(address, stackBase, 64, MicroOpBits::B64);
        builder.emitLoadAddressRegMem(other, stackBase, 80, MicroOpBits::B64);
        if (scenario == WideCopyCase::DenseFrameCopy || scenario == WideCopyCase::DenseFramePartialWrite)
        {
            for (uint64_t i = 0; i < 40; ++i)
                builder.emitLoadMemImm(stackBase, 128 + i * 8, ApInt(1, 64), MicroOpBits::B64);
        }
        if (scenario == WideCopyCase::NarrowSource)
        {
            // The whole upper lane is nonzero, although its low four bytes are zero.
            builder.emitLoadMemImm(stackBase, 8, ApInt(0, 32), MicroOpBits::B32);
            builder.emitLoadMemImm(stackBase, 12, ApInt(1, 32), MicroOpBits::B32);
        }
        else if (scenario == WideCopyCase::BooleanZeroGuard)
            builder.emitLoadMemImm(stackBase, 8, ApInt(0, 64), MicroOpBits::B64);
        else
            builder.emitLoadMemReg(stackBase, 8, address, MicroOpBits::B64);
        MicroLabelRef guardDone = MicroLabelRef::invalid();
        if (scenario == WideCopyCase::BooleanZeroGuard)
        {
            builder.emitLoadRegMem(pointer, stackBase, 8, MicroOpBits::B64);
            builder.emitCmpRegImm(pointer, ApInt(0, 64), MicroOpBits::B64);
            builder.emitSetCondReg(value, MicroCond::Equal);
            builder.emitCmpRegImm(value, ApInt(0, 8), MicroOpBits::B8);
            guardDone = builder.createLabel();
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, guardDone);
        }
        if (scenario == WideCopyCase::Vector)
            builder.emitLoadVecRegMem(loaded, stackBase, 0, MicroOpBits::B128);
        else
            builder.emitLoadRegMem(loaded, stackBase, 0, MicroOpBits::B128);
        if (scenario == WideCopyCase::SourceOverwritten)
            builder.emitLoadMemReg(stackBase, 8, other, MicroOpBits::B64);
        builder.emitLoadRegReg(copied, loaded, MicroOpBits::B128);
        if (scenario == WideCopyCase::SelfCopy)
            builder.emitLoadRegReg(copied, copied, MicroOpBits::B128);
        if (scenario == WideCopyCase::RegisterOverwritten)
            builder.emitLoadRegReg(copied, MicroReg::floatReg(0), MicroOpBits::B128);
        else if (scenario == WideCopyCase::ScalarRegisterOverwrite)
            builder.emitLoadRegReg(copied, MicroReg::floatReg(0), MicroOpBits::B64);
        else if (scenario == WideCopyCase::ZeroRegister)
            builder.emitClearReg(copied, MicroOpBits::B128);
        if (scenario == WideCopyCase::SameAcrossBranches || scenario == WideCopyCase::DifferentAcrossBranches)
        {
            const MicroLabelRef done = builder.createLabel();
            builder.emitCmpRegImm(CallConv::get(CallConvKind::Swag).intArgRegs[0], ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, done);
            if (scenario == WideCopyCase::DifferentAcrossBranches)
                builder.emitLoadMemReg(stackBase, 8, other, MicroOpBits::B64);
            builder.emitLoadRegMem(copied, stackBase, 0, MicroOpBits::B128);
            builder.placeLabel(done);
        }
        if (scenario == WideCopyCase::Vector)
            builder.emitStoreVecMemReg(stackBase, 16, copied, MicroOpBits::B128);
        else if (scenario == WideCopyCase::IndexedStore)
        {
            builder.emitLoadRegImm(value, ApInt(2, 64), MicroOpBits::B64);
            builder.emitLoadAmcMemReg(stackBase, value, 8, 0, MicroOpBits::B64, copied, MicroOpBits::B128);
        }
        else
            builder.emitLoadMemReg(stackBase, 16, copied, MicroOpBits::B128);
        if (scenario == WideCopyCase::DestinationOverwritten)
            builder.emitLoadMemReg(stackBase, 24, other, MicroOpBits::B64);
        else if (scenario == WideCopyCase::PartialDestinationWrite || scenario == WideCopyCase::DenseFramePartialWrite)
            builder.emitLoadMemImm(stackBase, 28, ApInt(1, 32), MicroOpBits::B32);
        builder.emitSanityInvalidate(address, 8);
        builder.emitLoadRegMem(pointer, stackBase, 24, MicroOpBits::B64);
        builder.emitLoadRegMem(value, pointer, 0, MicroOpBits::B32);
        if (guardDone.isValid())
            builder.placeLabel(guardDone);
        builder.emitRet();

        MicroSanityPass  pass;
        MicroPassManager passManager;
        passManager.addPreRaAnalysisPass(pass);
        MicroPassContext passContext;
        passContext.callConvKind             = CallConvKind::Swag;
        passContext.debugStackBaseVirtualReg = stackBase;
        passContext.sanitizerSafetyMask      = static_cast<uint16_t>(Runtime::SafetyWhat::Lifecycle) | static_cast<uint16_t>(Runtime::SafetyWhat::Null);
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

SWC_TEST_BEGIN(MicroSanity_RejectsStackAddressReturnedAsPointer)
{
    if (runStackEscapeSanity(ctx, ctx.typeMgr().typeValuePtrU8(), ReturnAddressKind::Stack) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_AllowsKnownNonStackPointer)
{
    SWC_RESULT(runStackEscapeSanity(ctx, ctx.typeMgr().typeValuePtrU8(), ReturnAddressKind::NonStack));
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_IgnoresStackAddressReturnedAsInteger)
{
    SWC_RESULT(runStackEscapeSanity(ctx, ctx.typeMgr().typeU64(), ReturnAddressKind::Stack));
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_RejectsMovedAddressReloadedAfterNullGuard)
{
    if (runGuardedMoveSanity(ctx, false, true) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_AllowsGuardedPointerReplacement)
{
    SWC_RESULT(runGuardedMoveSanity(ctx, true, true));
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_IgnoresInfeasibleNullGuardBranch)
{
    SWC_RESULT(runGuardedMoveSanity(ctx, false, false));
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_TracksUpperPointerLaneThroughWideCopies)
{
    if (runWideCopySanity(ctx, WideCopyCase::Plain) != Result::Error)
        return Result::Error;
    if (runWideCopySanity(ctx, WideCopyCase::Vector) != Result::Error)
        return Result::Error;
    if (runWideCopySanity(ctx, WideCopyCase::IndexedStore) != Result::Error)
        return Result::Error;
    if (runWideCopySanity(ctx, WideCopyCase::SelfCopy) != Result::Error)
        return Result::Error;
    if (runWideCopySanity(ctx, WideCopyCase::SourceOverwritten) != Result::Error)
        return Result::Error;
    if (runWideCopySanity(ctx, WideCopyCase::SameAcrossBranches) != Result::Error)
        return Result::Error;
    if (runWideCopySanity(ctx, WideCopyCase::DenseFrameCopy) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_ForgetsOverwrittenWideCopyFacts)
{
    SWC_RESULT(runWideCopySanity(ctx, WideCopyCase::RegisterOverwritten));
    SWC_RESULT(runWideCopySanity(ctx, WideCopyCase::ScalarRegisterOverwrite));
    SWC_RESULT(runWideCopySanity(ctx, WideCopyCase::DestinationOverwritten));
    SWC_RESULT(runWideCopySanity(ctx, WideCopyCase::PartialDestinationWrite));
    SWC_RESULT(runWideCopySanity(ctx, WideCopyCase::DifferentAcrossBranches));
    SWC_RESULT(runWideCopySanity(ctx, WideCopyCase::DenseFramePartialWrite));
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_DoesNotPromoteNarrowMemoryFactsIntoWideLanes)
{
    SWC_RESULT(runWideCopySanity(ctx, WideCopyCase::NarrowSource));
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_TracksZeroedUpperLane)
{
    if (runWideCopySanity(ctx, WideCopyCase::ZeroRegister) != Result::Error)
        return Result::Error;
    if (runWideCopySanity(ctx, WideCopyCase::BooleanZeroGuard) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
