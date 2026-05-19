#pragma once
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class Symbol;

struct GenericInstanceKey
{
    TypeRef     typeRef = TypeRef::invalid();
    ConstantRef cstRef  = ConstantRef::invalid();

    bool operator==(const GenericInstanceKey& other) const noexcept
    {
        return typeRef == other.typeRef && cstRef == other.cstRef;
    }
};

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
        for (const auto& entry : genericInstances_)
        {
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
        genericInstanceIndices_[instance] = genericInstances_.size();
        genericInstances_.push_back(std::move(entry));
        return instance;
    }

private:
    static bool sameArgs(std::span<const GenericInstanceKey> lhs, std::span<const GenericInstanceKey> rhs) noexcept
    {
        if (lhs.size() != rhs.size())
            return false;

        for (size_t i = 0; i < lhs.size(); ++i)
        {
            if (lhs[i] != rhs[i])
                return false;
        }

        return true;
    }

    mutable std::shared_mutex                 genericMutex_;
    std::vector<GenericInstanceEntry>         genericInstances_;
    std::unordered_map<const Symbol*, size_t> genericInstanceIndices_;
};

SWC_END_NAMESPACE();
