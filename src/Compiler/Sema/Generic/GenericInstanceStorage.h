#pragma once
#include "Compiler/Sema/Generic/GenericInstanceKey.h"
#include "Support/Core/SmallVector.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

class Symbol;

struct GenericInstanceEntry
{
    SmallVector<GenericInstanceKey> args;
    Symbol*                         symbol = nullptr;
};

class GenericInstanceStorage
{
public:
    Symbol* find(std::span<const GenericInstanceKey> args) const
    {
        const std::shared_lock lock(genericMutex_);
        return findNoLock(args);
    }

    Symbol* add(std::span<const GenericInstanceKey> args, Symbol* instance)
    {
        const std::unique_lock lock(genericMutex_);
        return addNoLock(args, instance);
    }

    bool tryGetArgs(const Symbol& instance, SmallVector<GenericInstanceKey>& outArgs) const
    {
        const std::shared_lock lock(genericMutex_);
        const auto             it = genericInstanceIndices_.find(&instance);
        if (it == genericInstanceIndices_.end())
            return false;

        outArgs = genericInstances_[it->second].args;
        return true;
    }

    std::shared_mutex& getMutex() const noexcept { return genericMutex_; }

    Symbol* findNoLock(std::span<const GenericInstanceKey> args) const
    {
        if (!genericArgumentIndices_)
        {
            for (const auto& entry : genericInstances_)
            {
                if (sameArgs(entry.args.span(), args))
                    return entry.symbol;
            }
            return nullptr;
        }

        const auto [begin, end] = genericArgumentIndices_->equal_range(hashArgs(args));
        for (auto it = begin; it != end; ++it)
        {
            const auto& entry = genericInstances_[it->second];
            if (sameArgs(entry.args.span(), args))
                return entry.symbol;
        }
        return nullptr;
    }

    Symbol* addNoLock(std::span<const GenericInstanceKey> args, Symbol* instance)
    {
        if (auto* existing = findNoLock(args))
            return existing;

        const auto it = genericInstanceIndices_.find(instance);
        if (it != genericInstanceIndices_.end())
            return genericInstances_[it->second].symbol;

        GenericInstanceEntry entry;
        entry.symbol = instance;
        entry.args.assign(args.begin(), args.end());
        const size_t index = genericInstances_.size();
        genericInstanceIndices_[instance] = index;
        genericInstances_.push_back(std::move(entry));

        if (genericArgumentIndices_)
            genericArgumentIndices_->emplace(hashArgs(genericInstances_[index].args.span()), index);
        else if (genericInstances_.size() > LINEAR_LOOKUP_LIMIT)
        {
            // Most generic roots have only a few instances. Keep their lookup allocation-free;
            // large families need an argument index to avoid quadratic instantiation searches.
            genericArgumentIndices_ = std::make_unique<ArgumentIndices>();
            genericArgumentIndices_->reserve(genericInstances_.size() * 2);
            for (size_t i = 0; i < genericInstances_.size(); ++i)
                genericArgumentIndices_->emplace(hashArgs(genericInstances_[i].args.span()), i);
        }
        return instance;
    }

private:
    static bool sameArgs(std::span<const GenericInstanceKey> lhs, std::span<const GenericInstanceKey> rhs) noexcept
    {
        return std::ranges::equal(lhs, rhs);
    }

    static uint32_t hashArgs(std::span<const GenericInstanceKey> args) noexcept
    {
        uint32_t hash = static_cast<uint32_t>(args.size());
        for (const GenericInstanceKey& arg : args)
        {
            hash = Math::hashCombine(hash, arg.typeRef.get());
            hash = Math::hashCombine(hash, arg.cstRef.get());
        }
        return Math::hash(hash);
    }

    static constexpr size_t LINEAR_LOOKUP_LIMIT = 8;
    using ArgumentIndices = std::unordered_multimap<uint32_t, size_t>;

    mutable std::shared_mutex                 genericMutex_;
    std::vector<GenericInstanceEntry>         genericInstances_;
    std::unordered_map<const Symbol*, size_t> genericInstanceIndices_;
    std::unique_ptr<ArgumentIndices>          genericArgumentIndices_;
};

SWC_END_NAMESPACE();
