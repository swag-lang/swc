#include "pch.h"
#include "Backend/Micro/Passes/Pass.FrameCompact.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Core/SmallVector.h"
#include "Support/Math/ApInt.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_FRAME_ALIGNMENT = 16;
    constexpr uint32_t K_ABOVE_FRAME     = std::numeric_limits<uint32_t>::max();
    constexpr uint8_t  K_NO_OPERAND      = std::numeric_limits<uint8_t>::max();

    // One piece of the frame partition: a known object, or the space between two.
    struct FrameRegion
    {
        uint64_t offset    = 0;
        uint64_t size      = 0;
        uint64_t newOffset = 0;
        uint32_t alignment = 1;
        bool     known     = false;
        bool     live      = false;
        // Reached through a plain copy of a frame register: no displacement carries
        // the object offset, so the object can only stay where it is.
        bool pinned = false;
    };

    // A displacement to rewrite once its region has moved.
    struct FrameReference
    {
        MicroInstrRef ref;
        uint32_t      region       = 0;
        uint8_t       operandIndex = K_NO_OPERAND;
        // An ApInt immediate rather than a raw memory displacement.
        bool immediate = false;
    };

    // A register the body derived from a frame register with a constant displacement.
    struct AddressReg
    {
        uint64_t      offset    = 0;
        MicroInstrRef defRef    = MicroInstrRef::invalid();
        MicroInstrRef adjustRef = MicroInstrRef::invalid();
    };

    // The alignment an offset proves for a region whose type is unknown.
    uint32_t alignmentOfOffset(const uint64_t offset)
    {
        if (!offset)
            return K_FRAME_ALIGNMENT;
        return static_cast<uint32_t>(std::min<uint64_t>(K_FRAME_ALIGNMENT, offset & (0 - offset)));
    }

    bool isStackAdjust(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg stackPointer, const MicroOp op, uint64_t& outValue)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm || !ops || ops[0].reg != stackPointer || ops[1].opBits != MicroOpBits::B64 ||
            ops[2].microOp != op || ops[3].hasWideImmediateValue())
            return false;
        outValue = ops[3].valueU64;
        return true;
    }

    // The bytes a memory-form instruction touches: its narrowest operand width, since an
    // extending load names both the memory width and the wider destination.
    uint64_t memoryAccessBytes(const MicroInstrDef& info, const MicroInstrOperand* ops)
    {
        uint64_t bytes = 0;
        for (uint8_t i = 0; i < 8; ++i)
        {
            if (!(info.opBitsMask & (1u << i)))
                continue;
            const uint64_t width = getNumBytes(ops[i].opBits);
            if (width && (!bytes || width < bytes))
                bytes = width;
        }
        return bytes;
    }
}

Result MicroFrameCompactPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    if (!context.builder || !context.sanitizerFunction || context.keepLocalStackBase)
        return Result::Continue;

    MicroStorage&        storage      = *context.instructions;
    MicroOperandStorage& operands     = *context.operands;
    const CallConv&      conv         = CallConv::get(context.callConvKind);
    const MicroReg       stackPointer = conv.stackPointer;
    if (!stackPointer.isValid())
        return Result::Continue;

    MicroInstrRef  frameBaseDefRef   = MicroInstrRef::invalid();
    uint64_t       frameBaseSpOffset = 0;
    const MicroReg frameBase         = MicroPassHelpers::detectFrameBase(storage, operands, stackPointer, context.debugStackBaseVirtualReg, frameBaseDefRef, frameBaseSpOffset);
    if (!frameBase.isValid() || frameBaseDefRef.isInvalid())
        return Result::Continue;
    if (context.debugStackBaseVirtualReg.isValid() && context.debugStackBaseVirtualReg != frameBase)
        return Result::Continue;

    // The region the code generator laid its locals in, above the frame base.
    const uint64_t localRegion = context.sanitizerFunction->debugStackFrameSize();
    if (!localRegion || localRegion % K_FRAME_ALIGNMENT)
        return Result::Continue;

    // The partition: known objects in offset order, and the space between them as
    // regions of their own, since a compiler temporary the symbols do not list may live there.
    const std::span<const MicroFrameObject> objects = MicroPassHelpers::frameObjects(context);
    if (objects.empty())
        return Result::Continue;
    SmallVector<FrameRegion> regions;
    uint64_t                 cursor = 0;
    for (const MicroFrameObject& object : objects)
    {
        if (!object.size || object.offset < cursor || object.offset + object.size > localRegion)
            return Result::Continue;
        if (object.offset > cursor)
            regions.push_back({.offset = cursor, .size = object.offset - cursor, .alignment = alignmentOfOffset(cursor)});
        regions.push_back({.offset = object.offset, .size = object.size, .alignment = object.alignment, .known = true});
        cursor = object.offset + object.size;
    }
    if (cursor < localRegion)
        regions.push_back({.offset = cursor, .size = localRegion - cursor, .alignment = alignmentOfOffset(cursor)});

    // The regions tile the local area in offset order, none of them empty: the one holding an
    // offset is the last that starts at or before it.
    const auto regionAt = [&](const uint64_t offset) -> uint32_t {
        const auto after = std::ranges::upper_bound(regions, offset, {}, &FrameRegion::offset);
        SWC_ASSERT(after != regions.begin());
        const auto index = static_cast<uint32_t>(after - regions.begin() - 1);
        SWC_ASSERT(offset < regions[index].offset + regions[index].size);
        return index;
    };

    // The entry subtract sits right before the base definition and covers the locals
    // and whatever the base is displaced by.
    MicroInstrRef entryRef  = MicroInstrRef::invalid();
    uint64_t      frameSize = 0;
    {
        const auto             beginIt = storage.view().begin();
        MicroStorage::Iterator it{&storage, frameBaseDefRef};
        while (it != beginIt)
        {
            --it;
            if (it->op == MicroInstrOpcode::Nop || it->op == MicroInstrOpcode::Label)
                continue;
            if (isStackAdjust(*it, it->ops(operands), stackPointer, MicroOp::Subtract, frameSize))
                entryRef = it.current;
            break;
        }
    }
    if (entryRef.isInvalid() || frameSize != frameBaseSpOffset + localRegion)
        return Result::Continue;

    // Every release of the frame precedes its return directly; any other stack-pointer
    // write is a call frame the displacement analysis below accounts for.
    SmallVector<MicroInstrRef> releaseRefs;
    uint32_t                   numRets = 0;
    bool                       spMoved = false;
    for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
    {
        const MicroInstr& inst = *it;
        if (inst.op == MicroInstrOpcode::Ret)
        {
            ++numRets;
            continue;
        }
        if (inst.op == MicroInstrOpcode::Push || inst.op == MicroInstrOpcode::Pop)
            return Result::Continue;
        if (it.current == entryRef || it.current == frameBaseDefRef)
            continue;

        const MicroInstrOperand* ops   = inst.ops(operands);
        uint64_t                 value = 0;
        if (isStackAdjust(inst, ops, stackPointer, MicroOp::Add, value) && value == frameSize)
        {
            // A release precedes its return directly; a call frame of the same size is
            // released anywhere else.
            auto next = it;
            ++next;
            while (next.current.isValid() && next->op == MicroInstrOpcode::Nop)
                ++next;
            if (next.current.isValid() && next->op == MicroInstrOpcode::Ret)
            {
                releaseRefs.push_back(it.current);
                continue;
            }
        }
        if (isStackAdjust(inst, ops, stackPointer, MicroOp::Add, value) || isStackAdjust(inst, ops, stackPointer, MicroOp::Subtract, value))
        {
            spMoved = true;
            continue;
        }
        if (!ops)
            continue;
        const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
        for (size_t i = 0; i < modes.size(); ++i)
        {
            if ((modes[i] == MicroInstrRegMode::Def || modes[i] == MicroInstrRegMode::UseDef) && (ops[i].reg == stackPointer || ops[i].reg == frameBase))
                return Result::Continue;
        }
    }
    if (!numRets || releaseRefs.size() != numRets)
        return Result::Continue;

    std::optional<FlatKeyMap<uint64_t>> stackPointerOffsets;
    if (spMoved)
        stackPointerOffsets = MicroPassHelpers::collectStackPointerOffsets(context, frameBaseDefRef, frameBaseSpOffset);
    const auto isFrameRegister = [&](const MicroReg reg) {
        return reg == frameBase || reg == stackPointer;
    };
    // The displacement of a frame register from the frame base at 'ref'.
    const auto frameRegisterOffset = [&](uint64_t& outOffset, const MicroReg reg, const MicroInstrRef ref) {
        if (reg == frameBase)
        {
            outOffset = 0;
            return true;
        }
        if (!spMoved)
        {
            outOffset = 0 - frameBaseSpOffset;
            return true;
        }
        const uint64_t* found = stackPointerOffsets->find(ref.get());
        if (!found)
            return false;
        outOffset = *found;
        return true;
    };

    // Pass 1: the registers that hold a frame address: `lea ar, [fb + off]`, its spelling
    // `mov ar, fb` for an object at the base, and the adjacent immediate adjustment the
    // front end emits when live flags keep the pair from folding.
    FlatKeyMap<AddressReg> addressRegs;
    FlatKeySet             adjustRefs;
    for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
    {
        if (it.current == frameBaseDefRef)
            continue;
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops || (inst.op != MicroInstrOpcode::LoadAddrRegMem && inst.op != MicroInstrOpcode::LoadRegReg) || ops[2].opBits != MicroOpBits::B64 ||
            !isFrameRegister(ops[1].reg))
            continue;
        uint64_t sourceOffset = 0;
        if (!frameRegisterOffset(sourceOffset, ops[1].reg, it.current))
            return Result::Continue;
        const MicroReg addressReg = ops[0].reg;
        if (!addressReg.isVirtualInt() || addressReg == frameBase || addressRegs.find(addressReg.packed))
            return Result::Continue;

        AddressReg info{.offset = sourceOffset + (inst.op == MicroInstrOpcode::LoadAddrRegMem ? ops[3].valueU64 : 0), .defRef = it.current};
        auto       next = it;
        ++next;
        if (next.current.isValid() && next->op == MicroInstrOpcode::OpBinaryRegImm)
        {
            const MicroInstrOperand* nextOps = next->ops(operands);
            if (nextOps[0].reg == addressReg && nextOps[1].opBits == MicroOpBits::B64 && !nextOps[3].hasWideImmediateValue() &&
                (nextOps[2].microOp == MicroOp::Add || nextOps[2].microOp == MicroOp::Subtract))
            {
                info.offset += nextOps[2].microOp == MicroOp::Add ? nextOps[3].valueU64 : 0 - nextOps[3].valueU64;
                info.adjustRef = next.current;
                adjustRefs.insert(next.current.get());
            }
        }
        addressRegs.emplace(addressReg.packed, info);
    }

    // Pass 2: every frame reference, by region. An access the partition cannot explain
    // keeps the frame as lowered.
    SmallVector<FrameReference> references;
    // Regions an address was formed at the start of. Such an address may as well be the
    // one-past-the-end pointer of the region before: when that one survives too, the two
    // must keep their spacing, which the packing below does not promise.
    SmallVector<uint32_t> boundaryRegions;
    const auto            markReference = [&](const MicroInstrRef ref, const uint8_t operandIndex, const bool immediate, const uint64_t offset, const uint64_t bytes, const bool formsAddress) {
        // Below the base: call-area staging through the stack pointer, which the frame
        // size does not move.
        if (static_cast<int64_t>(offset) < 0)
            return true;
        if (offset >= localRegion)
        {
            // Above the locals: an incoming argument. Its displacement follows the frame size.
            if (operandIndex == K_NO_OPERAND)
                return false;
            references.push_back({.ref = ref, .region = K_ABOVE_FRAME, .operandIndex = operandIndex, .immediate = immediate});
            return true;
        }
        const uint32_t index  = regionAt(offset);
        FrameRegion&   region = regions[index];
        if (bytes && offset + bytes > region.offset + region.size)
            return false;
        region.live = true;
        if (formsAddress && index && offset == region.offset)
            boundaryRegions.push_back(index);
        if (operandIndex == K_NO_OPERAND)
            region.pinned = true;
        else
            references.push_back({.ref = ref, .region = index, .operandIndex = operandIndex, .immediate = immediate});
        return true;
    };

    for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
    {
        const MicroInstrRef ref = it.current;
        if (ref == entryRef || ref == frameBaseDefRef || adjustRefs.contains(ref.get()))
            continue;
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops)
            continue;
        // The releases and the call frames move the stack pointer without naming an object.
        uint64_t adjust = 0;
        if (isStackAdjust(inst, ops, stackPointer, MicroOp::Add, adjust) || isStackAdjust(inst, ops, stackPointer, MicroOp::Subtract, adjust))
            continue;
        const MicroInstrDef& info  = MicroInstr::info(inst.op);
        const auto           modes = info.resolvedRegModes(ops);

        // A frame address definition: the displacement that names its object is the
        // adjacent adjustment when there is one, else the lea's own; a plain copy has none.
        if (const AddressReg* tracked = addressRegs.find(ops[0].reg.packed); tracked && tracked->defRef == ref)
        {
            if (tracked->adjustRef.isValid())
            {
                if (!markReference(tracked->adjustRef, 3, true, tracked->offset, 0, true))
                    return Result::Continue;
            }
            else if (inst.op == MicroInstrOpcode::LoadAddrRegMem)
            {
                if (!markReference(ref, 3, false, tracked->offset, 0, true))
                    return Result::Continue;
            }
            else if (!markReference(ref, K_NO_OPERAND, false, tracked->offset, 0, true))
                return Result::Continue;
            continue;
        }

        MicroPassHelpers::AmcLayout amcLayout;
        const bool                  amc     = MicroPassHelpers::amcLayoutFor(amcLayout, inst.op);
        const uint8_t               amcBase = amcLayout.baseIdx;
        const uint8_t               amcDisp = amcLayout.addIdx;
        const bool                  memForm = info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands);
        for (size_t i = 0; i < modes.size(); ++i)
        {
            if (modes[i] == MicroInstrRegMode::None)
                continue;
            const MicroReg reg = ops[i].reg;
            if (const AddressReg* tracked = addressRegs.find(reg.packed))
            {
                // Redefined by anything but its own definition: it no longer names its offset.
                if (modes[i] != MicroInstrRegMode::Use)
                    return Result::Continue;
                // As a base, the access stays inside the object the register was given.
                const bool isBase = (memForm && i == info.memBaseOperandIndex) || (amc && i == amcBase);
                if (isBase && tracked->offset < localRegion)
                {
                    const uint64_t target = tracked->offset + ops[memForm ? info.memOffsetOperandIndex : amcDisp].valueU64;
                    if (target >= localRegion || regionAt(target) != regionAt(tracked->offset))
                        return Result::Continue;
                }
                continue;
            }
            if (!isFrameRegister(reg))
                continue;
            uint64_t base = 0;
            if (!frameRegisterOffset(base, reg, ref))
                return Result::Continue;
            if (memForm && i == info.memBaseOperandIndex)
            {
                // An address computation forms a pointer; every other form reads or writes.
                const bool formsAddress = inst.op == MicroInstrOpcode::LoadAddrRegMem;
                if (!markReference(ref, info.memOffsetOperandIndex, false, base + ops[info.memOffsetOperandIndex].valueU64, formsAddress ? 0 : memoryAccessBytes(info, ops), formsAddress))
                    return Result::Continue;
            }
            else if (amc && i == amcBase)
            {
                if (!markReference(ref, amcDisp, false, base + ops[amcDisp].valueU64, 0, inst.op == MicroInstrOpcode::LoadAddrAmcRegMem))
                    return Result::Continue;
            }
            else if (!markReference(ref, K_NO_OPERAND, false, base, 0, true))
                return Result::Continue;
        }
    }

    // A pointer formed at a boundary may belong to either side; both sides surviving would
    // have to keep their spacing.
    for (const uint32_t index : boundaryRegions)
    {
        if (regions[index - 1].live)
            return Result::Continue;
    }

    // The new layout: live regions packed in their original order.
    cursor = 0;
    for (FrameRegion& region : regions)
    {
        if (!region.live)
            continue;
        region.newOffset = Math::alignUpU64(cursor, region.alignment);
        if (region.pinned && region.newOffset != region.offset)
            return Result::Continue;
        cursor = region.newOffset + region.size;
    }
    const uint64_t newRegion = Math::alignUpU64(cursor, K_FRAME_ALIGNMENT);
    if (newRegion >= localRegion)
        return Result::Continue;
    const uint64_t shrink = localRegion - newRegion;

    for (const FrameReference& reference : references)
    {
        const uint64_t delta = reference.region == K_ABOVE_FRAME ? 0 - shrink : regions[reference.region].newOffset - regions[reference.region].offset;
        if (!delta)
            continue;
        MicroInstrOperand& operand = storage.ptr(reference.ref)->ops(operands)[reference.operandIndex];
        if (reference.immediate)
            operand.setImmediateValue(ApInt(operand.valueU64 + delta, 64));
        else
            operand.valueU64 += delta;
    }
    const ApInt newFrameSize(frameSize - shrink, 64);
    storage.ptr(entryRef)->ops(operands)[3].setImmediateValue(newFrameSize);
    for (const MicroInstrRef releaseRef : releaseRefs)
        storage.ptr(releaseRef)->ops(operands)[3].setImmediateValue(newFrameSize);

    // Publish the layout the later passes read.
    context.frameObjects.clear();
    for (const FrameRegion& region : regions)
    {
        if (region.live && region.known)
            context.frameObjects.push_back({.offset = region.newOffset, .size = region.size, .alignment = region.alignment});
    }
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
