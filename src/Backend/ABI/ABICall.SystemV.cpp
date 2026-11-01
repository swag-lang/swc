#include "pch.h"
#include "Backend/ABI/ABICall.SystemV.h"
#include "Backend/ABI/SystemVAbi.h"
#include "Backend/Micro/MicroBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using SystemVAbi::Class;
    using SystemVAbi::Classification;

    Classification packedType(const bool isFloat, const uint8_t numBits)
    {
        const uint32_t size = numBits ? numBits / 8 : 8;
        SWC_ASSERT(size && size <= 16);
        Classification result{{isFloat ? Class::Sse : Class::Integer, Class::None}, size, std::min(size, 16u)};
        if (size > 8)
            result.classes[1] = isFloat ? Class::SseUp : Class::Integer;
        return result;
    }

    uint32_t chunkBytes(const uint32_t remaining)
    {
        return remaining >= 8 ? 8 : remaining >= 4 ? 4 : remaining >= 2 ? 2 : 1;
    }

    void loadIntegerPart(MicroBuilder& builder, const MicroReg destination, const MicroReg address, const uint32_t offset, const uint32_t size)
    {
        // Read exactly the object's bytes, including a three-, five- or seven-byte
        // final piece. Rounding to an eightbyte can cross an allocation or guard page.
        const MicroReg scratch = CallConv::get(CallConvKind::SystemVAMD64).intReturn;
        SWC_ASSERT(destination != scratch && address != scratch);
        uint32_t cursor = 0;
        while (cursor < size)
        {
            const uint32_t bytes = chunkBytes(size - cursor);
            const MicroReg target = cursor ? scratch : destination;
            ABICall::loadCanonicalIntFromMemToReg(builder, target, address, offset + cursor, static_cast<uint8_t>(bytes * 8), false);
            if (cursor)
            {
                builder.emitOpBinaryRegImm(scratch, ApInt(cursor * 8, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
                builder.emitOpBinaryRegReg(destination, scratch, MicroOp::Or, MicroOpBits::B64);
            }
            cursor += bytes;
        }
    }

    void storeIntegerPart(MicroBuilder& builder, const MicroReg address, const MicroReg source, const uint32_t offset, const uint32_t size, const MicroReg scratch)
    {
        // Keep every return register intact until its own part has been stored.
        builder.emitLoadRegReg(scratch, source, MicroOpBits::B64);
        uint32_t cursor = 0;
        while (cursor < size)
        {
            const uint32_t bytes = chunkBytes(size - cursor);
            builder.emitLoadMemReg(address, offset + cursor, scratch, microOpBitsFromBitWidth(bytes * 8));
            cursor += bytes;
            if (cursor < size)
                builder.emitOpBinaryRegImm(scratch, ApInt(bytes * 8, 64), MicroOp::ShiftRight, MicroOpBits::B64);
        }
    }

    uint32_t vectorPartBytes(const Classification& type, const uint32_t part)
    {
        if (!part && type.classes[1] == Class::SseUp)
            return 16;
        const uint32_t bytes = std::min(8u, type.size - part * 8);
        SWC_ASSERT(bytes == 4 || bytes == 8);
        return bytes;
    }

    void storeResult(MicroBuilder& builder, const ABICall::Return& ret, const MicroReg address, const MicroReg scratch)
    {
        if (ret.isVoid || ret.isIndirect || (ret.systemVType && ret.systemVType->memory()))
            return;
        SWC_ASSERT(ret.valuePtr && !ret.isIndirect);
        const Classification type = ret.systemVType ? *ret.systemVType : packedType(ret.isFloat, ret.numBits);
        builder.emitLoadRegPtrImm(address, reinterpret_cast<uint64_t>(ret.valuePtr));
        const std::array integerReturns{MicroReg::intReg(0), MicroReg::intReg(3)};
        uint32_t integer = 0;
        uint32_t vector = 0;
        for (uint32_t part = 0; part < 2; ++part)
        {
            if (type.classes[part] == Class::Integer)
                storeIntegerPart(builder, address, integerReturns[integer++], part * 8, std::min(8u, type.size - part * 8), scratch);
            else if (type.classes[part] == Class::Sse)
                builder.emitLoadMemReg(address, part * 8, MicroReg::floatReg(vector++), microOpBitsFromBitWidth(vectorPartBytes(type, part) * 8));
        }
    }
}

void ABICall::callSystemVAddress(MicroBuilder& builder, const CallConvKind callConvKind, const uint64_t targetAddress, const std::span<const Arg> args, const Return& ret)
{
    const CallConv& conv = CallConv::get(callConvKind);
    SWC_ASSERT(conv.isSystemVAMD64);
    SystemVAbi::ArgumentAllocator allocator;
    const bool hiddenReturn = !ret.isVoid && ret.systemVType && ret.systemVType->memory();
    if (hiddenReturn)
    {
        SWC_ASSERT(ret.valuePtr);
        allocator.next({{Class::Integer, Class::None}, 8, 8});
    }
    SmallVector<SystemVAbi::ArgumentLocation> locations;
    locations.reserve(args.size());
    for (const Arg& arg : args)
        locations.push_back(allocator.next(arg.systemVType ? *arg.systemVType : packedType(arg.isFloat, arg.numBits)));
    // Over-aligned stack values require dynamic stack realignment, which is not
    // exposed by the source-level System V convention yet.
    SWC_FORCE_ASSERT(allocator.stackAlignment() <= conv.stackAlignment);
    const uint64_t stackBytes = allocator.stackSize();
    const uint64_t adjustment = stackBytes + (conv.stackAlignment + sizeof(void*) - stackBytes % conv.stackAlignment) % conv.stackAlignment;
    SWC_ASSERT(adjustment <= UINT32_MAX);
    builder.emitOpBinaryRegImm(conv.stackPointer, ApInt(adjustment, 64), MicroOp::Subtract, MicroOpBits::B64);

    MicroReg base, address;
    SWC_INTERNAL_CHECK(conv.tryPickIntScratchRegs(base, address));
    const MicroReg scratch = conv.intReturn;
    builder.emitLoadRegPtrImm(base, reinterpret_cast<uint64_t>(args.data()));

    // Copy stack values before filling argument registers. Aggregate arguments are
    // values here; the source address never becomes an implicit pointer argument.
    for (uint32_t index = 0; index < args.size(); ++index)
    {
        const auto& location = locations[index];
        if (!location.onStack)
            continue;
        const Arg& arg = args[index];
        const Classification type = arg.systemVType ? *arg.systemVType : packedType(arg.isFloat, arg.numBits);
        const uint64_t entry = static_cast<uint64_t>(index) * sizeof(Arg);
        if (arg.systemVType)
            builder.emitLoadRegMem(address, base, entry + offsetof(Arg, value), MicroOpBits::B64);
        else
            builder.emitLoadAddressRegMem(address, base, entry + offsetof(Arg, value), MicroOpBits::B64);
        for (uint32_t offset = 0; offset < type.size;)
        {
            const uint32_t bytes = type.size - offset >= 16 ? 16 : chunkBytes(type.size - offset);
            const MicroOpBits bits = microOpBitsFromBitWidth(bytes * 8);
            const MicroReg temporary = bytes == 16 ? conv.floatReturn : scratch;
            builder.emitLoadRegMem(temporary, address, offset, bits);
            builder.emitLoadMemReg(conv.stackPointer, location.stackOffset + offset, temporary, bits);
            offset += bytes;
        }
    }

    uint8_t integers = hiddenReturn ? 1 : 0;
    CallFloatArgs floats;
    for (uint32_t index = 0; index < args.size(); ++index)
    {
        const auto& location = locations[index];
        if (location.onStack)
            continue;
        const Arg& arg = args[index];
        const Classification type = arg.systemVType ? *arg.systemVType : packedType(arg.isFloat, arg.numBits);
        const uint64_t entry = static_cast<uint64_t>(index) * sizeof(Arg);
        if (arg.systemVType)
            builder.emitLoadRegMem(address, base, entry + offsetof(Arg, value), MicroOpBits::B64);
        else
            builder.emitLoadAddressRegMem(address, base, entry + offsetof(Arg, value), MicroOpBits::B64);
        for (uint32_t part = 0; part < 2; ++part)
        {
            const uint32_t lane = location.registers[part];
            if (type.classes[part] == Class::Integer)
            {
                loadIntegerPart(builder, conv.intArgRegs[lane], address, part * 8, std::min(8u, type.size - part * 8));
                integers |= static_cast<uint8_t>(1u << lane);
            }
            else if (type.classes[part] == Class::Sse)
            {
                const uint32_t bits = vectorPartBytes(type, part) * 8;
                builder.emitLoadRegMem(conv.floatArgRegs[lane], address, part * 8, microOpBitsFromBitWidth(bits));
                floats.setWidth(lane, static_cast<uint8_t>(bits));
            }
        }
    }
    if (hiddenReturn)
        builder.emitLoadRegPtrImm(conv.intArgRegs[0], reinterpret_cast<uint64_t>(ret.valuePtr));
    // Use the shared call helper for AL setup, the call's use/def masks and stack restoration.
    PreparedCall prepared;
    prepared.stackAdjust = static_cast<uint32_t>(adjustment);
    prepared.stackAlreadyAdjusted = true;
    prepared.intArgMask = integers;
    prepared.floatArgMask = floats;
    builder.emitLoadRegPtrImm(address, targetAddress);
    callReg(builder, callConvKind, address, prepared);
    storeResult(builder, ret, base, address);
}

SWC_END_NAMESPACE();
