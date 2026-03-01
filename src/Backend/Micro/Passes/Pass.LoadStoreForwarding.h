#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;

class MicroLoadStoreForwardingPass final : public MicroPass
{
public:
    std::string_view name() const override { return "load-store-forward"; }
    Result           run(MicroPassContext& context) override;

private:
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

    void        initRunState(MicroPassContext& context);
    bool        getStackSlotKey(StackSlotKey& outKey, const MicroInstr& inst, const MicroInstrOperand* ops) const;
    static void invalidateOverlappingSlots(StackSlotMap& slots, const StackSlotKey& targetKey);
    static void invalidateSlotsUsingRegister(StackSlotMap& slots, MicroReg reg);
    static bool isSameMemoryAddress(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps);
    static bool isSameMemoryAddressForImmediateStore(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps);
    bool        canCrossInstruction(const MicroInstr& store, const MicroInstrOperand* storeOps, const MicroInstr& scanInst) const;
    bool        runForwardStoreToLoad();
    bool        promoteStackSlotLoads();

    MicroPassContext*    context_  = nullptr;
    MicroStorage*        storage_  = nullptr;
    MicroOperandStorage* operands_ = nullptr;
};

SWC_END_NAMESPACE();
