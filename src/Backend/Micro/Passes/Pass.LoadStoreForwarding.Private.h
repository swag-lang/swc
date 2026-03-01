#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"

SWC_BEGIN_NAMESPACE();

namespace LoadStoreForwardingPass
{
    struct StackSlotKey
    {
        MicroReg    baseReg;
        uint64_t    offset = 0;
        MicroOpBits opBits = MicroOpBits::Zero;

        bool operator==(const StackSlotKey&) const = default;
    };

    struct StackSlotKeyHash
    {
        size_t operator()(const StackSlotKey& key) const
        {
            size_t hashValue = std::hash<MicroReg>{}(key.baseReg);
            hashValue ^= std::hash<uint64_t>{}(key.offset) + 0x9e3779b97f4a7c15ull + (hashValue << 6) + (hashValue >> 2);
            hashValue ^= std::hash<uint8_t>{}(static_cast<uint8_t>(key.opBits)) + 0x9e3779b97f4a7c15ull + (hashValue << 6) + (hashValue >> 2);
            return hashValue;
        }
    };

    enum class StackSlotValueKind : uint8_t
    {
        Unknown,
        Register,
        Immediate,
    };

    struct StackSlotValue
    {
        StackSlotValueKind kind      = StackSlotValueKind::Unknown;
        MicroReg           reg       = MicroReg::invalid();
        uint64_t           immediate = 0;
    };

    using StackSlotMap = std::unordered_map<StackSlotKey, StackSlotValue, StackSlotKeyHash>;

    bool getStackSlotKey(StackSlotKey& outKey, const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);
    void invalidateOverlappingSlots(StackSlotMap& slots, const StackSlotKey& targetKey);
    void invalidateSlotsUsingRegister(StackSlotMap& slots, MicroReg reg);
    bool isSameMemoryAddress(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps);
    bool isSameMemoryAddressForImmediateStore(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps);
    bool canCrossInstruction(const MicroPassContext& context, const MicroInstr& store, const MicroInstrOperand* storeOps, const MicroInstr& scanInst);
    bool runForwardStoreToLoad(MicroPassContext& context);
    bool promoteStackSlotLoads(MicroPassContext& context);
}

SWC_END_NAMESPACE();
