#pragma once
#include "Backend/Micro/MicroReg.h"

SWC_BEGIN_NAMESPACE();

class MicroDenseRegIndex
{
public:
    static constexpr uint32_t K_INVALID_INDEX = std::numeric_limits<uint32_t>::max();

    void clear()
    {
        regToIndex_.clear();
        regs_.clear();
    }

    void reserve(const size_t regCountHint)
    {
        regToIndex_.reserve(regCountHint);
        regs_.reserve(regCountHint);
    }

    uint32_t ensure(const MicroReg reg)
    {
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
        const auto it = regToIndex_.find(reg);
        if (it == regToIndex_.end())
            return K_INVALID_INDEX;
        return it->second;
    }

    bool contains(const MicroReg reg) const
    {
        return regToIndex_.contains(reg);
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
    std::unordered_map<MicroReg, uint32_t> regToIndex_;
    std::vector<MicroReg>                  regs_;
};

SWC_END_NAMESPACE();
