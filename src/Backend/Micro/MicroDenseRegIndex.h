#pragma once
#include <array>
#include "Backend/Micro/MicroReg.h"

SWC_BEGIN_NAMESPACE();

class MicroDenseRegIndex
{
public:
    static constexpr uint32_t K_INVALID_INDEX = std::numeric_limits<uint32_t>::max();

    void clear()
    {
        regToIndex_.clear();
        for (auto& indices : directRegToIndex_)
            indices.clear();
        regs_.clear();
    }

    void reserve(const size_t regCountHint)
    {
        regToIndex_.reserve(regCountHint);
        regs_.reserve(regCountHint);
    }

    uint32_t ensure(const MicroReg reg)
    {
        if (uint32_t* const directIndex = directIndexSlot(reg))
        {
            if (*directIndex != K_INVALID_INDEX)
                return *directIndex;

            const uint32_t newIndex = static_cast<uint32_t>(regs_.size());
            *directIndex            = newIndex;
            regs_.push_back(reg);
            return newIndex;
        }

        const auto it = regToIndex_.find(reg);
        if (it != regToIndex_.end())
            return it->second;

        const uint32_t newIndex = static_cast<uint32_t>(regs_.size());
        regToIndex_.emplace(reg, newIndex);
        regs_.push_back(reg);
        return newIndex;
    }

    uint32_t find(const MicroReg reg) const
    {
        if (const uint32_t* const directIndex = directIndexSlot(reg))
            return *directIndex;

        const auto it = regToIndex_.find(reg);
        if (it == regToIndex_.end())
            return K_INVALID_INDEX;
        return it->second;
    }

    bool contains(const MicroReg reg) const
    {
        return find(reg) != K_INVALID_INDEX;
    }

    uint32_t wordCount() const
    {
        return static_cast<uint32_t>((regs_.size() + 63ull) / 64ull);
    }

    const std::vector<MicroReg>& regs() const
    {
        return regs_;
    }

private:
    static constexpr uint32_t K_DIRECT_KIND_COUNT = static_cast<uint32_t>(MicroRegKind::VirtualFloat) + 1;
    static constexpr uint32_t K_MAX_DIRECT_INDEX  = 1u << 20;

    uint32_t* directIndexSlot(const MicroReg reg)
    {
        const uint32_t kind = static_cast<uint32_t>(reg.kind());
        const uint32_t index = reg.index();
        if (kind >= K_DIRECT_KIND_COUNT || index > K_MAX_DIRECT_INDEX)
            return nullptr;

        auto& indices = directRegToIndex_[kind];
        if (index >= indices.size())
            indices.resize(index + 1, K_INVALID_INDEX);

        return &indices[index];
    }

    const uint32_t* directIndexSlot(const MicroReg reg) const
    {
        const uint32_t kind  = static_cast<uint32_t>(reg.kind());
        const uint32_t index = reg.index();
        if (kind >= K_DIRECT_KIND_COUNT || index >= directRegToIndex_[kind].size())
            return nullptr;

        return &directRegToIndex_[kind][index];
    }

    std::array<std::vector<uint32_t>, K_DIRECT_KIND_COUNT> directRegToIndex_;
    std::unordered_map<MicroReg, uint32_t> regToIndex_;
    std::vector<MicroReg>                  regs_;
};

SWC_END_NAMESPACE();
