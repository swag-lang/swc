#include "pch.h"
#include "Backend/ABI/ABICall.SystemV.h"
#include "Backend/ABI/SystemVAbi.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassHelpers.h"

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

    void loadIntegerPart(MicroBuilder& builder, const MicroReg destination, const MicroReg address, const uint32_t offset, const uint32_t size, const MicroReg scratch)
    {
        // Read exactly the object's bytes, including a three-, five- or seven-byte
        // final piece. Rounding to an eightbyte can cross an allocation or guard page.
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

    void emitArgument(MicroBuilder& builder, ABICall::PreparedCall& call, const Classification& type, const SystemVAbi::ArgumentLocation& location, const MicroReg address)
    {
        const CallConv& conv = CallConv::get(CallConvKind::SystemVAMD64);
        if (location.onStack)
        {
            for (uint32_t offset = 0; offset < type.size;)
            {
                const uint32_t bytes = type.size - offset >= 16 ? 16 : chunkBytes(type.size - offset);
                const MicroOpBits bits = microOpBitsFromBitWidth(bytes * 8);
                const MicroReg temporary = bytes == 16 ? conv.floatReturn : conv.intReturn;
                builder.emitLoadRegMem(temporary, address, offset, bits);
                builder.emitLoadMemReg(conv.stackPointer, location.stackOffset + offset, temporary, bits);
                offset += bytes;
            }
            return;
        }
        for (uint32_t part = 0; part < 2; ++part)
        {
            const uint32_t lane = location.registers[part];
            if (type.classes[part] == Class::Integer)
            {
                loadIntegerPart(builder, conv.intArgRegs[lane], address, part * 8, std::min(8u, type.size - part * 8), conv.intReturn);
                call.intArgMask |= static_cast<uint8_t>(1u << lane);
            }
            else if (type.classes[part] == Class::Sse)
            {
                const uint32_t bits = vectorPartBytes(type, part) * 8;
                builder.emitLoadRegMem(conv.floatArgRegs[lane], address, part * 8, microOpBitsFromBitWidth(bits));
                call.floatArgMask.setWidth(lane, static_cast<uint8_t>(bits));
            }
        }
    }

    uint32_t reserveCallStorage(MicroBuilder& builder, const CallConv& conv, const uint64_t size, const uint32_t alignment)
    {
        // Over-aligned stack values require dynamic stack realignment, which is not
        // exposed by the source-level System V convention yet.
        SWC_FORCE_ASSERT(alignment <= conv.stackAlignment);
        const uint64_t adjustment = size + (conv.stackAlignment + sizeof(void*) - size % conv.stackAlignment) % conv.stackAlignment;
        SWC_ASSERT(adjustment <= UINT32_MAX);
        builder.emitOpBinaryRegImm(conv.stackPointer, ApInt(adjustment, 64), MicroOp::Subtract, MicroOpBits::B64);
        return static_cast<uint32_t>(adjustment);
    }

    void storeReturnParts(MicroBuilder& builder, const Classification& type, const MicroReg address, const MicroReg scratch)
    {
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
    PreparedCall prepared;
    prepared.stackAdjust = reserveCallStorage(builder, conv, allocator.stackSize(), allocator.stackAlignment());
    prepared.stackAlreadyAdjusted = true;
    prepared.intArgMask = hiddenReturn ? 1 : 0;

    MicroReg base, address;
    SWC_INTERNAL_CHECK(conv.tryPickIntScratchRegs(base, address));
    builder.emitLoadRegPtrImm(base, reinterpret_cast<uint64_t>(args.data()));

    // Stack copies run first so their temporary vector register cannot overwrite
    // a register argument. The second traversal only fills committed ABI lanes.
    for (const bool onStack : {true, false})
    {
        for (uint32_t index = 0; index < args.size(); ++index)
        {
            const auto& location = locations[index];
            if (location.onStack != onStack)
                continue;
            const Arg& arg = args[index];
            const Classification type = arg.systemVType ? *arg.systemVType : packedType(arg.isFloat, arg.numBits);
            const uint64_t entry = static_cast<uint64_t>(index) * sizeof(Arg);
            if (arg.systemVType)
                builder.emitLoadRegMem(address, base, entry + offsetof(Arg, value), MicroOpBits::B64);
            else
                builder.emitLoadAddressRegMem(address, base, entry + offsetof(Arg, value), MicroOpBits::B64);
            emitArgument(builder, prepared, type, location, address);
        }
    }
    if (hiddenReturn)
        builder.emitLoadRegPtrImm(conv.intArgRegs[0], reinterpret_cast<uint64_t>(ret.valuePtr));
    // Use the shared call helper for AL setup, return storage and stack restoration.
    builder.emitLoadRegPtrImm(address, targetAddress);
    callReg(builder, callConvKind, address, prepared, ret);
}

void ABICall::storeSystemVReturn(MicroBuilder& builder, const Return& ret)
{
    if (ret.isVoid || ret.isIndirect || (ret.systemVType && ret.systemVType->memory()))
        return;
    SWC_ASSERT(ret.valuePtr);
    MicroReg address, scratch;
    SWC_INTERNAL_CHECK(CallConv::get(CallConvKind::SystemVAMD64).tryPickIntScratchRegs(address, scratch));
    const Classification type = ret.systemVType ? *ret.systemVType : packedType(ret.isFloat, ret.numBits);
    builder.emitLoadRegPtrImm(address, reinterpret_cast<uint64_t>(ret.valuePtr));
    storeReturnParts(builder, type, address, scratch);
}

void ABICall::storeSystemVReturn(MicroBuilder& builder, const MicroReg destination, const Classification& type)
{
    SWC_ASSERT(!type.memory());
    MicroReg address, scratch;
    SWC_INTERNAL_CHECK(CallConv::get(CallConvKind::SystemVAMD64).tryPickIntScratchRegs(address, scratch));
    builder.emitLoadRegReg(address, destination, MicroOpBits::B64);
    storeReturnParts(builder, type, address, scratch);
}

void ABICall::loadSystemVReturn(MicroBuilder& builder, const MicroReg source, const Classification& type)
{
    const CallConv& conv = CallConv::get(CallConvKind::SystemVAMD64);
    if (type.memory())
    {
        // The caller-provided buffer has already received the result. Its address
        // is also returned in RAX, as required by the System V memory-result rule.
        builder.emitLoadRegReg(conv.intReturn, source, MicroOpBits::B64);
        builder.setRetUsesAbiRegs(true, false);
        return;
    }
    MicroReg address, scratch;
    SWC_INTERNAL_CHECK(conv.tryPickIntScratchRegs(address, scratch));
    builder.emitLoadRegReg(address, source, MicroOpBits::B64);
    const std::array integerReturns{MicroReg::intReg(0), MicroReg::intReg(3)};
    uint32_t integer = 0;
    uint32_t vector = 0;
    for (uint32_t part = 0; part < 2; ++part)
    {
        if (type.classes[part] == Class::Integer)
            loadIntegerPart(builder, integerReturns[integer++], address, part * 8, std::min(8u, type.size - part * 8), scratch);
        else if (type.classes[part] == Class::Sse)
            builder.emitLoadRegMem(MicroReg::floatReg(vector++), address, part * 8, microOpBitsFromBitWidth(vectorPartBytes(type, part) * 8));
    }
    uint64_t extra = 0;
    if (integer > 1)
        extra |= MicroPassHelpers::MicroPhysLiveness::maskOf(integerReturns[1]);
    if (vector > 1)
        extra |= MicroPassHelpers::MicroPhysLiveness::maskOf(MicroReg::floatReg(1));
    builder.setRetUsesAbiRegs(integer != 0, vector != 0, extra);
}

ABICall::PreparedCall ABICall::prepareSystemVStorageArgs(MicroBuilder& builder, const CallConvKind callConvKind, const std::span<const PreparedArg> args)
{
    const CallConv& conv = CallConv::get(callConvKind);
    SWC_ASSERT(conv.isSystemVAMD64);
    SystemVAbi::ArgumentAllocator allocator;
    SmallVector<SystemVAbi::ArgumentLocation> locations;
    locations.reserve(args.size());
    for (const PreparedArg& arg : args)
        locations.push_back(allocator.next(arg.systemVType ? *arg.systemVType : packedType(arg.isFloat, arg.numBits)));

    // Snapshot sources before assigning any ABI lane. A physical source may itself
    // be an argument or scratch register, and one aggregate can claim two lanes.
    // Each home holds either a scalar (up to 128 bits) or an aggregate address.
    constexpr uint32_t K_SOURCE_HOME_SIZE = 16;
    const uint64_t homes = (allocator.stackSize() + K_SOURCE_HOME_SIZE - 1) / K_SOURCE_HOME_SIZE * K_SOURCE_HOME_SIZE;
    const uint64_t storage = homes + args.size() * K_SOURCE_HOME_SIZE;
    PreparedCall prepared;
    prepared.stackAdjust = reserveCallStorage(builder, conv, storage, allocator.stackAlignment());
    prepared.stackAlreadyAdjusted = true;
    for (uint32_t index = 0; index < args.size(); ++index)
    {
        const PreparedArg& arg = args[index];
        SWC_ASSERT(arg.srcReg != conv.stackPointer);
        const bool addressSource = arg.systemVType || arg.isAddressed || arg.kind == PreparedArgKind::InterfaceObject;
        const MicroOpBits bits = addressSource || !arg.isFloat ? MicroOpBits::B64 : valueBits(arg.numBits);
        builder.emitLoadMemReg(conv.stackPointer, homes + index * K_SOURCE_HOME_SIZE, arg.srcReg, bits);
    }

    MicroReg address, unused;
    SWC_INTERNAL_CHECK(conv.tryPickIntScratchRegs(address, unused));
    for (const bool onStack : {true, false})
    {
        for (uint32_t index = 0; index < args.size(); ++index)
        {
            const auto& location = locations[index];
            if (location.onStack != onStack)
                continue;
            const PreparedArg& arg = args[index];
            const Classification type = arg.systemVType ? *arg.systemVType : packedType(arg.isFloat, arg.numBits);
            const uint64_t home = homes + index * K_SOURCE_HOME_SIZE;
            if (arg.systemVType || arg.isAddressed || arg.kind == PreparedArgKind::InterfaceObject)
            {
                builder.emitLoadRegMem(address, conv.stackPointer, home, MicroOpBits::B64);
                if (arg.kind == PreparedArgKind::InterfaceObject)
                    builder.emitLoadAddressRegMem(address, address, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
            }
            else
                builder.emitLoadAddressRegMem(address, conv.stackPointer, home, MicroOpBits::B64);
            if (!onStack && !arg.systemVType && !arg.isFloat && arg.isSigned)
            {
                const uint32_t lane = location.registers[0];
                loadCanonicalIntFromMemToReg(builder, conv.intArgRegs[lane], address, 0, arg.numBits, true);
                prepared.intArgMask |= static_cast<uint8_t>(1u << lane);
            }
            else
                emitArgument(builder, prepared, type, location, address);
        }
    }
    return prepared;
}

SWC_END_NAMESPACE();
