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

// Outgoing argument space moves SP around a call, but locals remain at stable
// frame-base offsets. An escaped local stored in that outgoing area poisons
// only its own object; an unrelated local still promotes.
SWC_TEST_BEGIN(MemToReg_MovingStackPointerKeepsFramePromotion)
{
    SymbolFunction function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    SymbolVariable escaped(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    SymbolVariable independent(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    for (SymbolVariable* local : {&escaped, &independent})
    {
        local->setTypeRef(ctx.typeMgr().typeU64());
        local->addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
        local->setCodeGenLocalSize(8);
        function.addLocalVariable(ctx, local);
    }
    escaped.setOffset(0x10);
    independent.setOffset(0x18);

    const MicroReg     sp    = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg frame = MicroReg::virtualIntReg(1);
    constexpr MicroReg addr  = MicroReg::virtualIntReg(2);
    constexpr MicroReg value = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
    builder.emitLoadMemImm(frame, 0x10, ApInt(1, 64), MicroOpBits::B64);
    const MicroInstrRef escapedStore = builder.instructions().lastInstructionRef();
    builder.emitLoadAddressRegMem(addr, frame, 0x10, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(sp, ApInt(0x28, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(sp, 0x20, addr, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(sp, ApInt(0x28, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegMem(value, frame, 0x10, MicroOpBits::B64);
    builder.emitLoadMemImm(frame, 0x18, ApInt(2, 64), MicroOpBits::B64);
    const MicroInstrRef independentStore = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(value, frame, 0x18, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder, &function));
    if (builder.instructions().ptr(escapedStore)->op != MicroInstrOpcode::LoadMemImm)
        return Result::Error;
    if (builder.instructions().ptr(independentStore)->op != MicroInstrOpcode::LoadRegImm)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// SP-derived local addresses use the displacement at their definition, even
// after SP is restored. Captured outgoing argument addresses remain memory.
SWC_TEST_BEGIN(MemToReg_CapturedStackAddressRespectsObjectExtent)
{
    for (uint32_t variant = 0; variant < 4; ++variant)
    {
        SymbolFunction function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        SymbolVariable local(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        local.setTypeRef(ctx.typeMgr().typeU64());
        local.addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
        local.setCodeGenLocalSize(16);
        local.setOffset(0x20);
        function.addLocalVariable(ctx, &local);

        const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
        constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
        constexpr MicroReg addr   = MicroReg::virtualIntReg(2);
        constexpr MicroReg copy   = MicroReg::virtualIntReg(3);
        constexpr MicroReg packed = MicroReg::virtualFloatReg(1);
        constexpr MicroReg value  = MicroReg::virtualFloatReg(2);
        MicroBuilder       builder(ctx);
        builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
        builder.emitClearReg(packed, MicroOpBits::B128);
        builder.emitOpBinaryRegImm(sp, ApInt(0x40, 64), MicroOp::Subtract, MicroOpBits::B64);
        // Variants 0/1 name the local, 2 names outgoing space, 3 crosses its end.
        const uint64_t displacement = variant == 2 ? 0x20 : variant == 3 ? 0x68
                                                                         : 0x60;
        builder.emitLoadAddressRegMem(addr, sp, displacement, MicroOpBits::B64);
        builder.emitLoadRegReg(copy, addr, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(sp, ApInt(0x40, 64), MicroOp::Add, MicroOpBits::B64);
        const MicroReg base = variant == 0 ? addr : copy;
        builder.emitStoreVecMemReg(base, 0, packed, MicroOpBits::B128);
        const MicroInstrRef store = builder.instructions().lastInstructionRef();
        builder.emitLoadVecRegMem(value, base, 0, MicroOpBits::B128);
        const MicroInstrRef load = builder.instructions().lastInstructionRef();
        builder.emitRet();

        SWC_RESULT(runMemToRegPass(builder, &function));
        const bool promote = variant < 2;
        if (builder.instructions().ptr(store)->op != (promote ? MicroInstrOpcode::LoadRegReg : MicroInstrOpcode::StoreVecMemReg))
            return Result::Error;
        if (builder.instructions().ptr(load)->op != (promote ? MicroInstrOpcode::LoadRegReg : MicroInstrOpcode::LoadVecRegMem))
            return Result::Error;
    }
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

SWC_TEST_BEGIN(MemToReg_OutgoingObjectEndingAtFrameBaseStaysInMemory)
{
    SymbolFunction function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    SymbolVariable local(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    local.setTypeRef(ctx.typeMgr().typeU64());
    local.addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
    local.setCodeGenLocalSize(8);
    function.addLocalVariable(ctx, &local);
    local.setOffset(0x40);

    const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
    constexpr MicroReg addr   = MicroReg::virtualIntReg(2);
    constexpr MicroReg copy   = MicroReg::virtualIntReg(3);
    constexpr MicroReg value  = MicroReg::virtualIntReg(4);
    constexpr MicroReg vector = MicroReg::virtualFloatReg(1);
    MicroBuilder       builder(ctx);
    builder.emitLoadAddressRegMem(frame, sp, 0x18, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(addr, sp, 8, MicroOpBits::B64);
    builder.emitLoadRegReg(copy, addr, MicroOpBits::B64);
    builder.emitLoadRegMem(vector, MicroReg::intReg(2), 0, MicroOpBits::B128);
    builder.emitLoadMemReg(copy, 0, vector, MicroOpBits::B128);
    const auto store = builder.instructions().lastInstructionRef();
    builder.emitLoadRegReg(MicroReg::intReg(1), addr, MicroOpBits::B64);
    builder.emitLoadMemImm(frame, 0x40, ApInt(42, 64), MicroOpBits::B64);
    const auto localStore = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(value, frame, 0x40, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder, &function));
    if (builder.instructions().ptr(store)->op != MicroInstrOpcode::LoadMemReg ||
        builder.instructions().ptr(localStore)->op != MicroInstrOpcode::LoadRegImm)
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

SWC_TEST_BEGIN(MemToReg_ModifiedFrameAddressCanReachAnotherLocal)
{
    SymbolFunction function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    SymbolVariable first(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    SymbolVariable second(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    for (SymbolVariable* local : {&first, &second})
    {
        local->setTypeRef(ctx.typeMgr().typeU64());
        local->addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
        local->setCodeGenLocalSize(8);
        function.addLocalVariable(ctx, local);
    }
    first.setOffset(0);
    second.setOffset(8);

    const MicroReg     sp    = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg frame = MicroReg::virtualIntReg(1);
    constexpr MicroReg addr  = MicroReg::virtualIntReg(2);
    constexpr MicroReg value = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
    builder.emitLoadMemImm(frame, 8, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(addr, frame, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(addr, ApInt(8, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemImm(addr, 0, ApInt(42, 64), MicroOpBits::B64);
    const MicroInstrRef store = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(value, frame, 8, MicroOpBits::B64);
    const MicroInstrRef load = builder.instructions().lastInstructionRef();
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder, &function));
    const MicroInstr* stored = builder.instructions().ptr(store);
    const MicroInstr* loaded = builder.instructions().ptr(load);
    if (stored->op != MicroInstrOpcode::LoadRegImm || loaded->op != MicroInstrOpcode::LoadRegReg)
        return Result::Error;
    if (stored->ops(builder.operands())[0].reg != loaded->ops(builder.operands())[1].reg)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MemToReg_AddressCopiesKeepLaneReadsPrivate)
{
    for (uint32_t variant = 0; variant < 8; ++variant)
    {
        const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
        constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
        constexpr MicroReg addr   = MicroReg::virtualIntReg(2);
        constexpr MicroReg copy   = MicroReg::virtualIntReg(3);
        constexpr MicroReg second = MicroReg::virtualIntReg(4);
        constexpr MicroReg value  = MicroReg::virtualIntReg(5);
        constexpr MicroReg vector = MicroReg::virtualFloatReg(1);
        MicroBuilder       builder(ctx);
        builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(vector, MicroReg::intReg(2), 0, MicroOpBits::B128);
        builder.emitLoadMemReg(frame, 0x20, vector, MicroOpBits::B128);
        const auto store = builder.instructions().lastInstructionRef();
        builder.emitLoadAddressRegMem(addr, frame, 0x20, MicroOpBits::B64);
        if (variant == 2)
            builder.emitLoadRegImm(addr, ApInt(0, 64), MicroOpBits::B64);
        if (variant == 3)
            builder.placeLabel(builder.createLabel());
        builder.emitLoadRegReg(copy, addr, variant == 4 ? MicroOpBits::B32 : MicroOpBits::B64);
        if (variant == 5)
            builder.emitLoadRegImm(copy, ApInt(0, 64), MicroOpBits::B64);
        if (variant == 6)
            builder.emitLoadMemReg(MicroReg::intReg(7), 0, copy, MicroOpBits::B64);
        if (variant == 7)
            builder.emitLoadRegReg(MicroReg::intReg(1), copy, MicroOpBits::B64);
        if (variant == 1)
            builder.emitLoadRegReg(second, copy, MicroOpBits::B64);
        builder.emitLoadRegMem(value, variant == 1 ? second : copy, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(value, frame, 0x28, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runMemToRegPass(builder));
        const bool promoted = builder.instructions().ptr(store)->op == MicroInstrOpcode::LoadRegReg;
        if (promoted != (variant < 2))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MemToReg_SplitZeroFillUsesFrameRelativeOffsets)
{
    const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
    constexpr MicroReg addr   = MicroReg::virtualIntReg(2);
    constexpr MicroReg copy   = MicroReg::virtualIntReg(3);
    constexpr MicroReg value  = MicroReg::virtualIntReg(4);
    constexpr MicroReg vector = MicroReg::virtualFloatReg(1);
    MicroBuilder       builder(ctx);
    builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(addr, frame, 0x20, MicroOpBits::B64);
    builder.emitLoadRegReg(copy, addr, MicroOpBits::B64);
    builder.emitClearReg(vector, MicroOpBits::B128);
    builder.emitLoadMemReg(copy, 0, vector, MicroOpBits::B128);
    builder.emitLoadRegMem(value, frame, 0x20, MicroOpBits::B64);
    builder.emitLoadRegMem(value, frame, 0x28, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));
    uint32_t stores = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op != MicroInstrOpcode::LoadMemImm)
            continue;
        const auto* ops = inst.ops(builder.operands());
        if (ops[0].reg != frame || ops[1].opBits != MicroOpBits::B64 ||
            (ops[2].valueU64 != 0x20 && ops[2].valueU64 != 0x28) || ops[3].valueU64 != 0)
            return Result::Error;
        ++stores;
    }
    return stores == 2 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MemToReg_VectorLaneReadsFollowEveryWrite)
{
    for (uint32_t variant = 0; variant < 4; ++variant)
    {
        const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
        constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
        constexpr MicroReg value  = MicroReg::virtualIntReg(2);
        constexpr MicroReg vector = MicroReg::virtualFloatReg(1);
        constexpr MicroReg whole  = MicroReg::virtualFloatReg(2);
        MicroBuilder       builder(ctx);
        builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(vector, MicroReg::intReg(2), 0, MicroOpBits::B128);
        std::array<MicroInstrRef, 2> stores;
        std::array<MicroInstrRef, 2> reads;
        for (uint32_t update = 0; update < 2; ++update)
        {
            builder.emitStoreVecMemReg(frame, 0x20, vector, MicroOpBits::B128);
            stores[update] = builder.instructions().lastInstructionRef();
            builder.placeLabel(builder.createLabel());
            if (variant == 2)
                builder.emitLoadMemImm(frame, 0x2C, ApInt(7, 32), MicroOpBits::B32);
            const MicroOpBits bits   = variant == 1 ? MicroOpBits::B64 : MicroOpBits::B32;
            const uint64_t    offset = variant == 1 ? 0x28 : variant == 3 ? 0x2A
                                                                          : 0x2C;
            builder.emitLoadRegMem(value, frame, offset, bits);
            reads[update] = builder.instructions().lastInstructionRef();
            builder.emitLoadVecRegMem(whole, frame, 0x20, MicroOpBits::B128);
        }
        builder.emitRet();
        SWC_RESULT(runMemToRegPass(builder));
        for (uint32_t update = 0; update < 2; ++update)
        {
            const bool promote = variant < 2;
            if (builder.instructions().ptr(stores[update])->op != (promote ? MicroInstrOpcode::LoadRegReg : MicroInstrOpcode::StoreVecMemReg))
                return Result::Error;
            if (builder.instructions().ptr(reads[update])->op != (promote ? MicroInstrOpcode::LoadRegReg : MicroInstrOpcode::LoadRegMem))
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

// A vector spilled once and read back lane by lane stays in a register: each lane comes out
// with a shuffle to lane zero and one move, and no frame access remains.
// General promotion also carries the vector across a label.
SWC_TEST_BEGIN(MemToReg_VectorReadByLanesSplits)
{
    for (const bool separated : {false, true})
    {
        const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
        constexpr MicroReg vFb    = MicroReg::virtualIntReg(1);
        constexpr MicroReg lane0  = MicroReg::virtualIntReg(2);
        constexpr MicroReg lane1  = MicroReg::virtualIntReg(3);
        constexpr MicroReg lane3  = MicroReg::virtualIntReg(4);
        constexpr MicroReg high   = MicroReg::virtualIntReg(5);
        constexpr MicroReg vector = MicroReg::virtualFloatReg(1);
        MicroBuilder       builder(ctx);
        const auto         label = builder.createLabel();

        builder.emitLoadAddressRegMem(vFb, sp, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(vector, MicroReg::intReg(2), 0, MicroOpBits::B128);
        builder.emitLoadMemReg(vFb, 0x20, vector, MicroOpBits::B128);
        if (separated)
            builder.placeLabel(label);
        builder.emitLoadRegMem(lane0, vFb, 0x20, MicroOpBits::B32);
        builder.emitLoadRegMem(lane1, vFb, 0x24, MicroOpBits::B32);
        builder.emitLoadRegMem(lane3, vFb, 0x2C, MicroOpBits::B32);
        builder.emitLoadRegMem(high, vFb, 0x28, MicroOpBits::B64);
        builder.emitLoadMemReg(MicroReg::intReg(3), 0, lane0, MicroOpBits::B32);
        builder.emitLoadMemReg(MicroReg::intReg(3), 4, lane1, MicroOpBits::B32);
        builder.emitLoadMemReg(MicroReg::intReg(3), 8, lane3, MicroOpBits::B32);
        builder.emitLoadMemReg(MicroReg::intReg(3), 16, high, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runMemToRegPass(builder));

        // The source load stays; the four lane reads through the frame go.
        const uint32_t frameLoads = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) - 1;
        const uint32_t shuffles   = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::VecShuffleRegRegImm);
        if (frameLoads != 0 || shuffles != 3)
            return Result::Error;
    }

    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // One 32-byte local at 0x20, the tile the dead-fill tests clear and overwrite.
    struct TileFunction
    {
        SymbolFunction function{nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero};
        SymbolVariable tile{nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero};

        explicit TileFunction(TaskContext& ctx)
        {
            tile.setTypeRef(ctx.typeMgr().typeU64());
            tile.addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
            tile.setCodeGenLocalSize(32);
            function.addLocalVariable(ctx, &tile);
            tile.setOffset(0x20);
        }
    };

    enum class TileCase : uint8_t
    {
        Overwritten,
        PartialOverwrite,
        ReadBeforeOverwrite,
        EscapeBeforeForeignRead,
        NotOnEntryLine,
        GlobalCopyInLoop,
        ConstantCopyInLoop,
        PointerConstantInLoop,
    };

    // Clears the tile with two vector stores, loads a row through a pointer the
    // frame analysis does not track, writes the tile's rows through its
    // address, then hands that address out. Returns the number of fill stores
    // left.
    Result runTileCase(TaskContext& ctx, const TileCase tileCase, uint32_t& outFillStores)
    {
        TileFunction       fn(ctx);
        const MicroReg     sp     = CallConv::get(CallConvKind::Swag).stackPointer;
        constexpr MicroReg frame  = MicroReg::virtualIntReg(1);
        constexpr MicroReg rows   = MicroReg::virtualIntReg(2);
        constexpr MicroReg source = MicroReg::virtualIntReg(3);
        constexpr MicroReg peek   = MicroReg::virtualIntReg(4);
        constexpr MicroReg zero   = MicroReg::virtualFloatReg(1);
        constexpr MicroReg row    = MicroReg::virtualFloatReg(2);
        MicroBuilder       builder(ctx);

        builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
        builder.emitLoadRegReg(source, MicroReg::intReg(2), MicroOpBits::B64);
        const bool relocatedRead = tileCase == TileCase::GlobalCopyInLoop ||
                                   tileCase == TileCase::ConstantCopyInLoop ||
                                   tileCase == TileCase::PointerConstantInLoop;
        if (tileCase == TileCase::NotOnEntryLine || relocatedRead)
        {
            MicroLabelRef label;
            builder.emitLabel(label);
        }
        builder.emitClearReg(zero, MicroOpBits::B128);
        builder.emitStoreVecMemReg(frame, 0x20, zero, MicroOpBits::B128);
        builder.emitStoreVecMemReg(frame, 0x30, zero, MicroOpBits::B128);
        builder.emitLoadAddressRegMem(rows, frame, 0x20, MicroOpBits::B64);
        if (tileCase == TileCase::ReadBeforeOverwrite)
            builder.emitLoadRegMem(peek, frame, 0x34, MicroOpBits::B32);
        if (tileCase == TileCase::EscapeBeforeForeignRead)
            builder.emitLoadRegReg(MicroReg::intReg(1), rows, MicroOpBits::B64);
        if (relocatedRead)
            builder.emitLoadRegMem(row, MicroReg::instructionPointer(), 0, MicroOpBits::B128);
        else
            builder.emitLoadVecRegMem(row, source, 0, MicroOpBits::B128);
        if (relocatedRead)
        {
            MicroRelocation relocation;
            relocation.kind           = tileCase == TileCase::GlobalCopyInLoop ? MicroRelocation::Kind::GlobalInitAddress : MicroRelocation::Kind::ConstantAddress;
            relocation.form           = MicroRelocation::Form::Relative32;
            relocation.instructionRef = builder.instructions().findPreviousInstructionRef(MicroInstrRef::invalid());
            if (relocation.kind == MicroRelocation::Kind::ConstantAddress)
                relocation.constantRef = ConstantRef(0);
            if (tileCase == TileCase::ConstantCopyInLoop)
            {
                relocation.constantShard  = 0;
                relocation.constantOffset = 0;
            }
            builder.addRelocation(relocation);
        }
        builder.emitStoreVecMemReg(rows, 0, row, MicroOpBits::B128);
        if (tileCase == TileCase::PartialOverwrite)
            builder.emitLoadMemReg(rows, 0x10, source, MicroOpBits::B64);
        else
            builder.emitStoreVecMemReg(rows, 0x10, row, MicroOpBits::B128);
        if (tileCase != TileCase::EscapeBeforeForeignRead)
            builder.emitLoadRegReg(MicroReg::intReg(1), rows, MicroOpBits::B64);
        builder.emitLoadRegMem(peek, frame, 0x38, MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::intReg(0), peek, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runMemToRegPass(builder, &fn.function));

        outFillStores = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::StoreVecMemReg && ops && ops[1].reg == zero)
                ++outFillStores;
        }
        return Result::Continue;
    }
}

// A local cleared at its declaration and then overwritten whole, before any
// read, loses its clear - even when its address is handed out afterwards and
// a pointer the analysis cannot follow is read in between.
SWC_TEST_BEGIN(MemToReg_DeadFillIsErased)
{
    uint32_t fillStores = 0;
    SWC_RESULT(runTileCase(ctx, TileCase::Overwritten, fillStores));
    if (fillStores != 0)
        return Result::Error;
    SWC_RESULT(runTileCase(ctx, TileCase::GlobalCopyInLoop, fillStores));
    if (fillStores != 0)
        return Result::Error;
    SWC_RESULT(runTileCase(ctx, TileCase::ConstantCopyInLoop, fillStores));
    if (fillStores != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The clear stays wherever it may still be read: the half the second row only
// partly overwrites, a byte read before the rows are written, an address
// handed out before a foreign pointer is read, and a fill off the entry line
// of an object whose address escapes, which an earlier pass through a loop
// may have handed out.
SWC_TEST_BEGIN(MemToReg_LiveFillIsKept)
{
    uint32_t fillStores = 0;
    SWC_RESULT(runTileCase(ctx, TileCase::PartialOverwrite, fillStores));
    if (fillStores != 1)
        return Result::Error;
    SWC_RESULT(runTileCase(ctx, TileCase::ReadBeforeOverwrite, fillStores));
    if (fillStores != 1)
        return Result::Error;
    SWC_RESULT(runTileCase(ctx, TileCase::EscapeBeforeForeignRead, fillStores));
    if (fillStores != 2)
        return Result::Error;
    SWC_RESULT(runTileCase(ctx, TileCase::NotOnEntryLine, fillStores));
    if (fillStores != 2)
        return Result::Error;
    SWC_RESULT(runTileCase(ctx, TileCase::PointerConstantInLoop, fillStores));
    if (fillStores != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    uint32_t countFrameAccesses(const MicroBuilder& builder, const MicroReg frame)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (!ops)
                continue;
            if ((inst.op == MicroInstrOpcode::LoadMemReg || inst.op == MicroInstrOpcode::LoadMemImm) && ops[0].reg == frame)
                ++count;
            if (inst.op == MicroInstrOpcode::LoadRegMem && ops[1].reg == frame)
                ++count;
        }
        return count;
    }

    uint32_t countBinaryImm(const MicroBuilder& builder, const MicroOp op)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops && ops[2].microOp == op)
                ++count;
        }
        return count;
    }
}

// A record returned in one register, given its zero default and then built
// field by field on two paths that each read it back whole, lives in one
// integer register: no frame access is left, no field needs clearing first
// since every one lands in bytes still zero, and the first field of each path
// is the whole word.
SWC_TEST_BEGIN(MemToReg_RecordBuiltOnEveryPathStaysInRegister)
{
    const MicroReg      sp     = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg  frame  = MicroReg::virtualIntReg(1);
    constexpr MicroReg  cond   = MicroReg::virtualIntReg(2);
    constexpr MicroReg  refIdx = MicroReg::virtualIntReg(3);
    constexpr MicroReg  mvX    = MicroReg::virtualIntReg(4);
    constexpr MicroReg  first  = MicroReg::virtualIntReg(5);
    constexpr MicroReg  second = MicroReg::virtualIntReg(6);
    MicroBuilder        builder(ctx);
    const MicroLabelRef intra = builder.createLabel();

    builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
    builder.emitLoadRegReg(cond, MicroReg::intReg(1), MicroOpBits::B64);
    builder.emitLoadRegReg(refIdx, MicroReg::intReg(2), MicroOpBits::B64);
    builder.emitLoadRegReg(mvX, MicroReg::intReg(8), MicroOpBits::B64);
    builder.emitLoadMemImm(frame, 0, ApInt(0, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(cond, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, intra);
    builder.emitLoadMemImm(frame, 0, ApInt(1, 8), MicroOpBits::B8);
    builder.emitLoadMemReg(frame, 2, refIdx, MicroOpBits::B8);
    builder.emitLoadMemReg(frame, 4, mvX, MicroOpBits::B16);
    builder.emitLoadRegMem(first, frame, 0, MicroOpBits::B64);
    builder.emitLoadRegReg(MicroReg::intReg(0), first, MicroOpBits::B64);
    builder.emitRet();
    builder.placeLabel(intra);
    builder.emitLoadMemImm(frame, 0, ApInt(1, 8), MicroOpBits::B8);
    builder.emitLoadMemImm(frame, 1, ApInt(1, 8), MicroOpBits::B8);
    builder.emitLoadMemImm(frame, 2, ApInt(0xFF, 8), MicroOpBits::B8);
    builder.emitLoadRegMem(second, frame, 0, MicroOpBits::B64);
    builder.emitLoadRegReg(MicroReg::intReg(0), second, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));

    if (countFrameAccesses(builder, frame) != 0)
        return Result::Error;
    if (countBinaryImm(builder, MicroOp::And) != 0 || countBinaryImm(builder, MicroOp::Or) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A field stored over a word whose bytes are not known zero clears them
// first; a record whose address escapes, or whose field is stored before the
// word has a value on every path, stays in the frame.
SWC_TEST_BEGIN(MemToReg_RecordFieldStoreClearsUnknownBytes)
{
    const MicroReg     sp    = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg frame = MicroReg::virtualIntReg(1);
    constexpr MicroReg word  = MicroReg::virtualIntReg(2);
    constexpr MicroReg field = MicroReg::virtualIntReg(3);
    constexpr MicroReg whole = MicroReg::virtualIntReg(4);

    enum class Shape : uint8_t
    {
        UnknownBytes,
        Escaped,
        Undefined,
    };
    for (const Shape shape : {Shape::UnknownBytes, Shape::Escaped, Shape::Undefined})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadAddressRegMem(frame, sp, 0, MicroOpBits::B64);
        builder.emitLoadRegReg(word, MicroReg::intReg(1), MicroOpBits::B64);
        builder.emitLoadRegReg(field, MicroReg::intReg(2), MicroOpBits::B64);
        if (shape != Shape::Undefined)
            builder.emitLoadMemReg(frame, 0x10, word, MicroOpBits::B64);
        if (shape == Shape::Escaped)
            builder.emitLoadRegReg(MicroReg::intReg(1), frame, MicroOpBits::B64);
        builder.emitLoadMemReg(frame, 0x12, field, MicroOpBits::B16);
        builder.emitLoadMemReg(frame, 0x14, field, MicroOpBits::B32);
        builder.emitLoadRegMem(whole, frame, 0x10, MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::intReg(0), whole, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runMemToRegPass(builder));

        const uint32_t frameAccesses = countFrameAccesses(builder, frame);
        if (shape == Shape::UnknownBytes && (frameAccesses != 0 || countBinaryImm(builder, MicroOp::And) != 2))
            return Result::Error;
        if (shape != Shape::UnknownBytes && frameAccesses == 0)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
