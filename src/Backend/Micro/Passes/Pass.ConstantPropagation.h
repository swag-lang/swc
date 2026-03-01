#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

struct KnownConstant
{
    uint64_t value = 0;
};

struct KnownConstantPointer
{
    uint64_t pointer = 0;
    uint64_t offset  = 0;
};

struct CompareState
{
    bool        valid  = false;
    uint64_t    lhs    = 0;
    uint64_t    rhs    = 0;
    MicroOpBits opBits = MicroOpBits::B64;
};

struct StackSlotKey
{
    uint64_t    offset = 0;
    MicroOpBits opBits = MicroOpBits::Zero;

    bool operator==(const StackSlotKey&) const = default;
};

struct StackSlotKeyHash
{
    size_t operator()(const StackSlotKey& key) const
    {
        size_t hash = std::hash<uint64_t>{}(key.offset);
        hash ^= std::hash<uint32_t>{}(static_cast<uint32_t>(key.opBits) + 0x9e3779b9u);
        return hash;
    }
};

using KnownRegMap             = std::unordered_map<uint32_t, KnownConstant>;
using KnownStackSlotMap       = std::unordered_map<StackSlotKey, KnownConstant, StackSlotKeyHash>;
using KnownAddressMap         = std::unordered_map<uint32_t, uint64_t>;
using KnownStackAddressMap    = std::unordered_map<uint64_t, uint64_t>;
using KnownConstantPointerMap = std::unordered_map<uint32_t, KnownConstantPointer>;

struct MicroRelocation;

class MicroConstantPropagationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "const-prop"; }
    Result           run(MicroPassContext& context) override;

private:
    void clearState();

    KnownRegMap                                               known_;
    KnownStackSlotMap                                         knownStackSlots_;
    KnownAddressMap                                           knownAddresses_;
    KnownStackAddressMap                                      knownStackAddresses_;
    KnownConstantPointerMap                                   knownConstantPointers_;
    CompareState                                              compareState_;
    std::unordered_map<MicroInstrRef, const MicroRelocation*> relocationByInstructionRef_;
    std::unordered_set<MicroLabelRef>                         referencedLabels_;
};

SWC_END_NAMESPACE();
