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
        const size_t           index = findInstanceIndexNoLock(&instance);
        if (index == K_NOT_FOUND)
            return false;

        outArgs = genericInstances_[index].args;
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

        if (const size_t existing = findInstanceIndexNoLock(instance); existing != K_NOT_FOUND)
            return genericInstances_[existing].symbol;

        const size_t index = genericInstances_.size();
        if (genericInstanceIndices_)
            genericInstanceIndices_->emplace(instance, index);

        GenericInstanceEntry& entry = genericInstances_.emplace_back();
        entry.symbol                = instance;
        entry.args.assign(args.begin(), args.end());

        if (genericArgumentIndices_)
            genericArgumentIndices_->emplace(hashArgs(genericInstances_[index].args.span()), index);
        else if (genericInstances_.size() > LINEAR_LOOKUP_LIMIT)
        {
            // Most generic roots have only a few instances. Keep their lookup allocation-free;
            // large families need an argument index to avoid quadratic instantiation searches.
            genericArgumentIndices_ = std::make_unique<ArgumentIndices>();
            genericArgumentIndices_->reserve(genericInstances_.size() * 2);
            genericInstanceIndices_ = std::make_unique<InstanceIndices>();
            genericInstanceIndices_->reserve(genericInstances_.size() * 2);
            for (size_t i = 0; i < genericInstances_.size(); ++i)
            {
                genericArgumentIndices_->emplace(hashArgs(genericInstances_[i].args.span()), i);
                genericInstanceIndices_->emplace(genericInstances_[i].symbol, i);
            }
        }
        return instance;
    }

private:
    static constexpr size_t K_NOT_FOUND = std::numeric_limits<size_t>::max();

    // An instance appears once in the list, so the first match is the only one, as the index
    // would find it. Like the argument index, this one exists only past the linear limit.
    size_t findInstanceIndexNoLock(const Symbol* instance) const
    {
        if (genericInstanceIndices_)
        {
            const auto it = genericInstanceIndices_->find(instance);
            return it == genericInstanceIndices_->end() ? K_NOT_FOUND : it->second;
        }

        for (size_t i = 0; i < genericInstances_.size(); ++i)
        {
            if (genericInstances_[i].symbol == instance)
                return i;
        }

        return K_NOT_FOUND;
    }

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
    using ArgumentIndices                       = std::unordered_multimap<uint32_t, size_t>;
    using InstanceIndices                       = std::unordered_map<const Symbol*, size_t>;

    mutable std::shared_mutex         genericMutex_;
    std::vector<GenericInstanceEntry> genericInstances_;
    std::unique_ptr<InstanceIndices>  genericInstanceIndices_;
    std::unique_ptr<ArgumentIndices>  genericArgumentIndices_;
};

SWC_END_NAMESPACE();
