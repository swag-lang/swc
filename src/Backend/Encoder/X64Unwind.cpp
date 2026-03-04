#include "pch.h"
#include "Backend/Encoder/X64Unwind.h"
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::array<uint8_t, 16> K_WINDOWS_UNWIND_REG_FROM_INT_REG_INDEX = {
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

    constexpr uint8_t K_UWOP_PUSH_NONVOL     = 0;
    constexpr uint8_t K_UWOP_ALLOC_LARGE     = 1;
    constexpr uint8_t K_UWOP_ALLOC_SMALL     = 2;
    constexpr uint8_t K_UWOP_SET_FPREG       = 3;
    constexpr uint8_t K_UWOP_SAVE_NONVOL     = 4;
    constexpr uint8_t K_UWOP_SAVE_NONVOL_FAR = 5;

    bool isX64NonVolatileRegWindows(const uint8_t reg)
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

    bool tryMapUnwindRegWindows(uint8_t& outReg, const MicroReg reg)
    {
        outReg = 0;
        if (!reg.isInt() || reg.isVirtual())
            return false;

        const size_t regIndex = reg.index();
        if (regIndex >= K_WINDOWS_UNWIND_REG_FROM_INT_REG_INDEX.size())
            return false;

        outReg = K_WINDOWS_UNWIND_REG_FROM_INT_REG_INDEX[regIndex];
        return true;
    }

    uint16_t packUnwindCodeSlot(const uint8_t codeOffset, const uint8_t unwindOp, const uint8_t opInfo)
    {
        const uint8_t  opByte = static_cast<uint8_t>(((opInfo & 0x0F) << 4) | (unwindOp & 0x0F));
        const uint16_t value  = static_cast<uint16_t>(static_cast<uint16_t>(codeOffset) | (static_cast<uint16_t>(opByte) << 8));
        return value;
    }
}

const X64Unwind::UnwindComputer& X64Unwind::unwindComputerForOs(const Runtime::TargetOs targetOs)
{
    static const UnwindComputer K_WINDOWS = {
        &X64Unwind::buildInfoWindows,
        &X64Unwind::onInstructionEncodedWindows,
    };

    static const UnwindComputer K_UNSUPPORTED = {
        &X64Unwind::buildInfoUnsupported,
        nullptr,
    };

    switch (targetOs)
    {
        case Runtime::TargetOs::Windows:
            return K_WINDOWS;

        case Runtime::TargetOs::Linux:
            return K_UNSUPPORTED;

        default:
            return K_UNSUPPORTED;
    }
}

void X64Unwind::buildInfo(std::vector<std::byte>& outUnwindInfo, const uint32_t codeSize) const
{
    SWC_ASSERT(codeSize != 0);
    SWC_ASSERT(!unwindPrologInvalid_);

    const UnwindComputer& unwindComputer = unwindComputerForOs(targetOs_);
    SWC_ASSERT(unwindComputer.buildInfo);
    (this->*unwindComputer.buildInfo)(outUnwindInfo, codeSize);
}

void X64Unwind::buildInfoUnsupported(std::vector<std::byte>& outUnwindInfo, const uint32_t codeSize) const
{
    SWC_UNUSED(codeSize);
    outUnwindInfo.clear();
    SWC_FORCE_ASSERT(false && "X64 unwind info is not implemented for this target OS");
}

void X64Unwind::buildInfoWindows(std::vector<std::byte>& outUnwindInfo, const uint32_t codeSize) const
{
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

            case UnwindOpKind::SaveNonVol:
            {
                SWC_ASSERT((op.stackOffset % 8) == 0);
                const uint32_t stackOffsetInSlots = op.stackOffset / 8;
                if (stackOffsetInSlots <= std::numeric_limits<uint16_t>::max())
                {
                    unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_SAVE_NONVOL, op.reg));
                    unwindSlots.push_back(static_cast<uint16_t>(stackOffsetInSlots));
                    break;
                }

                unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_SAVE_NONVOL_FAR, op.reg));
                unwindSlots.push_back(static_cast<uint16_t>(op.stackOffset & 0xFFFF));
                unwindSlots.push_back(static_cast<uint16_t>((op.stackOffset >> 16) & 0xFFFF));
                break;
            }

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

void X64Unwind::onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, const uint32_t codeStartOffset, const uint32_t codeEndOffset)
{
    const UnwindComputer& unwindComputer = unwindComputerForOs(targetOs_);
    if (!unwindComputer.trackInstruction)
        return;

    (this->*unwindComputer.trackInstruction)(inst, ops, codeStartOffset, codeEndOffset);
}

void X64Unwind::onInstructionEncodedWindows(const MicroInstr& inst, const MicroInstrOperand* ops, const uint32_t codeStartOffset, const uint32_t codeEndOffset)
{
    if (codeEndOffset <= codeStartOffset)
        return;

    if (unwindPrologClosed_ || unwindPrologInvalid_)
        return;

    if (!canTrackUnwindInstruction(codeEndOffset))
        return;

    bool didTrack = false;
    switch (inst.op)
    {
        case MicroInstrOpcode::Push:
            didTrack = tryTrackUnwindPushWindows(ops, codeEndOffset);
            break;

        case MicroInstrOpcode::LoadRegReg:
        case MicroInstrOpcode::LoadAddrRegMem:
            didTrack = tryTrackUnwindSetFramePointerWindows(inst, ops, codeEndOffset);
            break;

        case MicroInstrOpcode::LoadMemReg:
            didTrack = tryTrackUnwindSaveNonVolWindows(ops, codeEndOffset);
            break;

        case MicroInstrOpcode::OpBinaryRegImm:
            didTrack = tryTrackUnwindAllocateStackWindows(ops, codeEndOffset);
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

    closeUnwindProlog();
}

bool X64Unwind::tryTrackUnwindPushWindows(const MicroInstrOperand* ops, const uint32_t codeEndOffset)
{
    if (!ops)
        return false;

    uint8_t reg = 0;
    if (!tryMapUnwindRegWindows(reg, ops[0].reg))
        return false;
    if (!isX64NonVolatileRegWindows(reg))
        return false;

    unwindOps_.push_back({
        .kind       = UnwindOpKind::PushNonVol,
        .codeOffset = static_cast<uint8_t>(codeEndOffset),
        .reg        = reg,
    });
    return true;
}

bool X64Unwind::tryTrackUnwindAllocateStackWindows(const MicroInstrOperand* ops, const uint32_t codeEndOffset)
{
    if (!ops)
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
    return true;
}

bool X64Unwind::tryTrackUnwindSetFramePointerWindows(const MicroInstr& inst, const MicroInstrOperand* ops, const uint32_t codeEndOffset)
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
    if (!tryMapUnwindRegWindows(reg, frameReg))
        return false;
    if (!isX64NonVolatileRegWindows(reg))
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

bool X64Unwind::tryTrackUnwindSaveNonVolWindows(const MicroInstrOperand* ops, const uint32_t codeEndOffset)
{
    if (!ops)
        return false;

    if (ops[0].reg != MicroReg::intReg(4))
        return false;
    if (ops[2].opBits != MicroOpBits::B64)
        return false;
    if (ops[3].valueU64 > std::numeric_limits<uint32_t>::max())
        return false;

    uint8_t reg = 0;
    if (!tryMapUnwindRegWindows(reg, ops[1].reg))
        return false;
    if (!isX64NonVolatileRegWindows(reg))
        return false;

    unwindOps_.push_back({
        .kind        = UnwindOpKind::SaveNonVol,
        .codeOffset  = static_cast<uint8_t>(codeEndOffset),
        .reg         = reg,
        .stackOffset = static_cast<uint32_t>(ops[3].valueU64),
    });
    return true;
}

void X64Unwind::closeUnwindProlog()
{
    unwindPrologClosed_ = true;
}

bool X64Unwind::canTrackUnwindInstruction(const uint32_t codeEndOffset)
{
    if (codeEndOffset <= std::numeric_limits<uint8_t>::max())
        return true;

    unwindPrologInvalid_ = true;
    closeUnwindProlog();
    return false;
}

SWC_END_NAMESPACE();
