#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.MemToReg.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runMemToRegPass(MicroBuilder& builder, const SymbolFunction* function = nullptr)
    {
        MicroMemToRegPass pass;
        MicroPassManager  passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind      = CallConvKind::Swag;
        passContext.sanitizerFunction = function;
        return builder.runPasses(passManager, nullptr, passContext);
    }

}

// A frame slot only ever reached as the constant-offset base of scalar
// accesses promotes to a virtual register: the immediate store becomes a
// register immediate, the load becomes a copy.
SWC_TEST_BEGIN(MemToReg_PlainSlot_Promotes)
{
    const MicroReg     sp   = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg vFb  = MicroReg::virtualIntReg(1);
    constexpr MicroReg vVal = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadAddressRegMem(vFb, sp, 0, MicroOpBits::B64);
    builder.emitLoadMemImm(vFb, 0x10, ApInt(42, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(vVal, vFb, 0x10, MicroOpBits::B64);
    builder.emitCmpRegImm(vVal, ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MemToReg_MixedSlotsKeepDistinctFreshRegisters)
{
    const MicroReg     sp    = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg frame = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);
    builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
    std::array<MicroInstrRef, 4> stores;
    std::array<MicroInstrRef, 4> loads;
    std::array<MicroReg, 4>      sources;
    for (uint32_t slot = 0; slot < stores.size(); ++slot)
    {
        const bool isFloat = slot % 2 != 0;
        sources[slot]      = isFloat ? MicroReg::virtualFloatReg(slot + 1) : MicroReg::virtualIntReg(slot + 2);
        builder.emitClearReg(sources[slot], MicroOpBits::B64);
        builder.emitLoadMemReg(frame, 0x10 + slot * 16, sources[slot], MicroOpBits::B64);
        stores[slot]   = builder.instructions().lastInstructionRef();
        const auto dst = isFloat ? MicroReg::virtualFloatReg(slot + 10) : MicroReg::virtualIntReg(slot + 10);
        builder.emitLoadRegMem(dst, frame, 0x10 + slot * 16, MicroOpBits::B64);
        loads[slot] = builder.instructions().lastInstructionRef();
    }
    // The register maxima are in the suffix, after all accesses to all slots.
    builder.emitLoadRegReg(MicroReg::virtualIntReg(1000), sources[0], MicroOpBits::B64);
    builder.emitLoadRegReg(MicroReg::virtualFloatReg(2000), sources[1], MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));
    std::unordered_set<MicroReg> promoted;
    for (uint32_t slot = 0; slot < stores.size(); ++slot)
    {
        const auto* store = builder.instructions().ptr(stores[slot]);
        const auto* load  = builder.instructions().ptr(loads[slot]);
        if (store->op != MicroInstrOpcode::LoadRegReg || load->op != MicroInstrOpcode::LoadRegReg)
            return Result::Error;
        const auto* storeOps = store->ops(builder.operands());
        const auto* loadOps  = load->ops(builder.operands());
        const auto  reg      = storeOps[0].reg;
        if (storeOps[1].reg != sources[slot] || loadOps[1].reg != reg || !promoted.insert(reg).second)
            return Result::Error;
        if (slot % 2 != 0)
        {
            if (!reg.isVirtualFloat() || reg.index() < 2001 || reg.index() > 2002)
                return Result::Error;
        }
        else if (!reg.isVirtualInt() || reg.index() < 1001 || reg.index() > 1002)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// F-028: an address register minted by `lea ar, [fb + off]` and then redefined
// by plain arithmetic no longer points at its recorded offset, so nothing may
// resolve through it. Without local-variable extents (none here) the whole
// function must bail: every access stays a memory access, in particular the
// unrelated slot at fb+0x30 whose promotion would otherwise swallow the store
// that goes through the moved pointer. The pass disqualifies the register in
// its collection pass, upstream of the extent information, so the same holds
// when extents allow per-variable poisoning.
SWC_TEST_BEGIN(MemToReg_RedefinedAddressRegister_BailsFunction)
{
    const MicroReg     sp   = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg vFb  = MicroReg::virtualIntReg(1);
    constexpr MicroReg vAr  = MicroReg::virtualIntReg(2);
    constexpr MicroReg vIdx = MicroReg::virtualIntReg(3);
    constexpr MicroReg vVal = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadAddressRegMem(vFb, sp, 0, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(vAr, vFb, 0x10, MicroOpBits::B64);
    builder.emitLoadMemImm(vAr, 0, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vIdx, ApInt(8, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(vAr, vIdx, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemImm(vAr, 0x20, ApInt(9, 64), MicroOpBits::B64);
    builder.emitLoadMemImm(vFb, 0x30, ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(vVal, vFb, 0x30, MicroOpBits::B64);
    builder.emitCmpRegImm(vVal, ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemImm) != 3)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MemToReg_UnwrittenWideAccess_BlocksOverlapButNotAdjacentSlot)
{
    const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg packed = MicroReg::virtualFloatReg(1);
    MicroBuilder       builder(ctx);
    builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
    builder.emitLoadRegMem(value, frame, 0x20, MicroOpBits::B8);
    builder.emitLoadVecRegMem(packed, frame, 0x20, MicroOpBits::B128);
    builder.emitLoadRegMem(value, frame, 0x20, MicroOpBits::B8);
    builder.emitLoadMemImm(frame, 0x28, ApInt(7, 64), MicroOpBits::B64);
    const MicroInstrRef overlappingStore = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(value, frame, 0x28, MicroOpBits::B64);
    builder.emitLoadMemImm(frame, 0x30, ApInt(9, 64), MicroOpBits::B64);
    const MicroInstrRef adjacentStore = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(value, frame, 0x30, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));
    if (builder.instructions().ptr(overlappingStore)->op != MicroInstrOpcode::LoadMemImm)
        return Result::Error;
    if (builder.instructions().ptr(adjacentStore)->op != MicroInstrOpcode::LoadRegImm)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MemToReg_WrappingWideAccess_KeepsNarrowOverlap)
{
    const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg packed = MicroReg::virtualFloatReg(1);
    constexpr uint64_t start  = std::numeric_limits<uint64_t>::max() - 7;
    MicroBuilder       builder(ctx);
    builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
    builder.emitLoadRegMem(value, frame, start, MicroOpBits::B32);
    builder.emitLoadVecRegMem(packed, frame, start, MicroOpBits::B128);
    builder.emitLoadMemImm(frame, start + 2, ApInt(7, 32), MicroOpBits::B32);
    const MicroInstrRef overlappingStore = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(value, frame, start + 2, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));
    // The widest access wraps its endpoint; the narrower one still overlaps.
    if (builder.instructions().ptr(overlappingStore)->op != MicroInstrOpcode::LoadMemImm)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MemToReg_WidestAccessRespectsEscapedVariableExtents)
{
    for (const bool unknownEscape : {false, true})
    {
        SymbolFunction function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        SymbolVariable boundary(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        SymbolVariable neighbor(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        boundary.setTypeRef(ctx.typeMgr().typeU64());
        neighbor.setTypeRef(ctx.typeMgr().typeU64());
        function.addLocalVariable(ctx, &boundary);
        function.addLocalVariable(ctx, &neighbor);
        boundary.addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
        neighbor.addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
        boundary.setOffset(unknownEscape ? 0x40 : 0x48);
        boundary.setCodeGenLocalSize(8);
        neighbor.setOffset(0x60);
        neighbor.setCodeGenLocalSize(8);

        const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
        constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
        constexpr MicroReg addr   = MicroReg::virtualIntReg(2);
        constexpr MicroReg value  = MicroReg::virtualIntReg(3);
        constexpr MicroReg packed = MicroReg::virtualFloatReg(1);
        MicroBuilder       builder(ctx);
        builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
        builder.emitLoadAddressRegMem(addr, frame, unknownEscape ? 0x80 : 0x48, MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::intReg(2), addr, MicroOpBits::B64);
        // Only the wide access reaches poisoned or unknown bytes. The narrow
        // read comes last, so a cached last endpoint would miss the rejection.
        builder.emitStoreVecMemReg(frame, 0x40, packed, MicroOpBits::B128);
        const MicroInstrRef wideStore = builder.instructions().lastInstructionRef();
        builder.emitLoadRegMem(value, frame, 0x40, MicroOpBits::B64);
        builder.emitLoadMemImm(frame, 0x60, ApInt(7, 64), MicroOpBits::B64);
        const MicroInstrRef neighborStore = builder.instructions().lastInstructionRef();
        builder.emitLoadRegMem(value, frame, 0x60, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runMemToRegPass(builder, &function));
        if (builder.instructions().ptr(wideStore)->op != MicroInstrOpcode::StoreVecMemReg)
            return Result::Error;
        if (builder.instructions().ptr(neighborStore)->op != MicroInstrOpcode::LoadRegImm)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
