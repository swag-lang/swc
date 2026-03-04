#include "pch.h"
#include "Backend/Encoder/X64Unwind.Windows.h"
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::array<uint8_t, 16> K_UNWIND_REG_FROM_INT_REG_INDEX = {
        0,
        3,
        1,
        2,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
    };

    constexpr uint8_t K_UWOP_PUSH_NONVOL = 0;
    constexpr uint8_t K_UWOP_ALLOC_LARGE = 1;
    constexpr uint8_t K_UWOP_ALLOC_SMALL = 2;
    constexpr uint8_t K_UWOP_SET_FPREG   = 3;

    bool isX64NonVolatileReg(const uint8_t reg)
    {
        switch (reg)
        {
            case 3:
            case 5:
            case 6:
            case 7:
            case 12:
            case 13:
            case 14:
            case 15:
                return true;
            default:
                return false;
        }
    }

    bool tryMapUnwindReg(uint8_t& outReg, const MicroReg reg)
    {
        outReg = 0;
        if (!reg.isInt() || reg.isVirtual())
            return false;

        const size_t regIndex = reg.index();
        if (regIndex >= K_UNWIND_REG_FROM_INT_REG_INDEX.size())
            return false;

        outReg = K_UNWIND_REG_FROM_INT_REG_INDEX[regIndex];
        return true;
    }

    uint16_t packUnwindCodeSlot(const uint8_t codeOffset, const uint8_t unwindOp, const uint8_t opInfo)
    {
        const uint8_t  opByte = static_cast<uint8_t>(((opInfo & 0x0F) << 4) | (unwindOp & 0x0F));
        const uint16_t value  = static_cast<uint16_t>(static_cast<uint16_t>(codeOffset) | (static_cast<uint16_t>(opByte) << 8));
        return value;
    }
}

void X64UnwindWindows::buildInfo(std::vector<std::byte>& outUnwindInfo, const uint32_t codeSize) const
{
    SWC_ASSERT(codeSize != 0);

    SWC_UNUSED(codeSize);
    outUnwindInfo.clear();

    std::vector<UnwindOp> unwindOps = unwindOps_;
    std::ranges::sort(unwindOps, [](const UnwindOp& left, const UnwindOp& right) {
        return left.codeOffset > right.codeOffset;
    });

    std::vector<uint16_t> unwindSlots;
    unwindSlots.reserve(unwindOps.size() * 3 + 4);
    for (const UnwindOp& op : unwindOps)
    {
        switch (op.kind)
        {
            case UnwindOpKind::PushNonVol:
                unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_PUSH_NONVOL, op.reg));
                break;

            case UnwindOpKind::AllocateStack:
            {
                if (op.stackSize >= 8 && op.stackSize <= 128 && (op.stackSize % 8) == 0)
                {
                    const uint8_t opInfo = static_cast<uint8_t>(op.stackSize / 8 - 1);
                    unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_ALLOC_SMALL, opInfo));
                    break;
                }

                if ((op.stackSize % 8) == 0 && op.stackSize / 8 <= std::numeric_limits<uint16_t>::max())
                {
                    unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_ALLOC_LARGE, 0));
                    unwindSlots.push_back(static_cast<uint16_t>(op.stackSize / 8));
                    break;
                }

                unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_ALLOC_LARGE, 1));
                unwindSlots.push_back(static_cast<uint16_t>(op.stackSize & 0xFFFF));
                unwindSlots.push_back(static_cast<uint16_t>((op.stackSize >> 16) & 0xFFFF));
                break;
            }

            case UnwindOpKind::SetFramePointer:
                unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_SET_FPREG, 0));
                break;

            default:
                SWC_UNREACHABLE();
        }
    }

    const uint32_t unwindSlotCount        = static_cast<uint32_t>(unwindSlots.size());
    const uint32_t unwindSlotCountAligned = (unwindSlotCount + 1u) & ~1u;

    outUnwindInfo.resize(4 + unwindSlotCountAligned * sizeof(uint16_t));
    auto* const outBytes = reinterpret_cast<uint8_t*>(outUnwindInfo.data());
    outBytes[0]          = 1;
    outBytes[1]          = unwindPrologSize_;
    outBytes[2]          = static_cast<uint8_t>(unwindSlotCount);
    outBytes[3]          = unwindHasFrameRegister_ ? static_cast<uint8_t>(((unwindFrameOffsetInSlots_ & 0x0F) << 4) | (unwindFrameRegister_ & 0x0F)) : 0;

    for (uint32_t i = 0; i < unwindSlotCountAligned; ++i)
    {
        const uint16_t value    = i < unwindSlotCount ? unwindSlots[i] : 0;
        outBytes[4 + i * 2 + 0] = static_cast<uint8_t>(value & 0xFF);
        outBytes[4 + i * 2 + 1] = static_cast<uint8_t>((value >> 8) & 0xFF);
    }
}

void X64UnwindWindows::onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, const uint32_t codeStartOffset, const uint32_t codeEndOffset)
{
    if (codeEndOffset <= codeStartOffset)
        return;

    if (unwindPrologClosed_)
        return;

    if (!canTrackInstruction(codeEndOffset))
        return;

    bool didTrack = false;
    switch (inst.op)
    {
        case MicroInstrOpcode::Push:
            didTrack = tryTrackPush(ops, codeEndOffset);
            break;

        case MicroInstrOpcode::LoadRegReg:
        case MicroInstrOpcode::LoadAddrRegMem:
            didTrack = tryTrackSetFramePointer(inst, ops, codeEndOffset);
            break;

        case MicroInstrOpcode::OpBinaryRegImm:
            didTrack = tryTrackAllocateStack(ops, codeEndOffset);
            break;

        default:
            didTrack = false;
            break;
    }

    if (didTrack)
    {
        unwindPrologSize_ = static_cast<uint8_t>(codeEndOffset);
        return;
    }

    closeProlog();
}

bool X64UnwindWindows::tryTrackPush(const MicroInstrOperand* ops, const uint32_t codeEndOffset)
{
    if (!ops)
        return false;
    if (unwindHasStackAllocation_)
        return false;

    uint8_t reg = 0;
    if (!tryMapUnwindReg(reg, ops[0].reg))
        return false;
    if (!isX64NonVolatileReg(reg))
        return false;
    const uint16_t regMask = static_cast<uint16_t>(1u << reg);
    if (unwindPushedRegMask_ & regMask)
        return false;

    unwindOps_.push_back({
        .kind       = UnwindOpKind::PushNonVol,
        .codeOffset = static_cast<uint8_t>(codeEndOffset),
        .reg        = reg,
    });
    unwindPushedRegMask_ |= regMask;
    return true;
}

bool X64UnwindWindows::tryTrackAllocateStack(const MicroInstrOperand* ops, const uint32_t codeEndOffset)
{
    if (!ops)
        return false;
    if (unwindHasStackAllocation_)
        return false;

    if (ops[0].reg != MicroReg::intReg(4))
        return false;
    if (ops[1].opBits != MicroOpBits::B64)
        return false;
    if (ops[2].microOp != MicroOp::Subtract)
        return false;
    if (!ops[3].valueU64 || ops[3].valueU64 > std::numeric_limits<uint32_t>::max())
        return false;

    unwindOps_.push_back({
        .kind       = UnwindOpKind::AllocateStack,
        .codeOffset = static_cast<uint8_t>(codeEndOffset),
        .stackSize  = static_cast<uint32_t>(ops[3].valueU64),
    });
    unwindHasStackAllocation_ = true;
    return true;
}

bool X64UnwindWindows::tryTrackSetFramePointer(const MicroInstr& inst, const MicroInstrOperand* ops, const uint32_t codeEndOffset)
{
    if (!ops)
        return false;
    if (unwindHasFrameRegister_)
        return false;

    MicroReg frameReg;
    uint64_t frameOffset = 0;
    if (inst.op == MicroInstrOpcode::LoadRegReg)
    {
        if (ops[2].opBits != MicroOpBits::B64)
            return false;
        if (ops[1].reg != MicroReg::intReg(4))
            return false;

        frameReg = ops[0].reg;
    }
    else if (inst.op == MicroInstrOpcode::LoadAddrRegMem)
    {
        if (ops[2].opBits != MicroOpBits::B64)
            return false;
        if (ops[1].reg != MicroReg::intReg(4))
            return false;
        if (ops[3].valueU64 > 240 || (ops[3].valueU64 % 16) != 0)
            return false;

        frameReg    = ops[0].reg;
        frameOffset = ops[3].valueU64;
    }
    else
    {
        return false;
    }

    uint8_t reg = 0;
    if (!tryMapUnwindReg(reg, frameReg))
        return false;
    if (!isX64NonVolatileReg(reg))
        return false;

    unwindHasFrameRegister_   = true;
    unwindFrameRegister_      = reg;
    unwindFrameOffsetInSlots_ = static_cast<uint8_t>(frameOffset / 16);
    unwindOps_.push_back({
        .kind       = UnwindOpKind::SetFramePointer,
        .codeOffset = static_cast<uint8_t>(codeEndOffset),
    });
    return true;
}

void X64UnwindWindows::closeProlog()
{
    unwindPrologClosed_ = true;
}

bool X64UnwindWindows::canTrackInstruction(const uint32_t codeEndOffset)
{
    if (codeEndOffset <= std::numeric_limits<uint8_t>::max())
        return true;

    closeProlog();
    return false;
}

SWC_END_NAMESPACE();
