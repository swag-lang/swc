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
        const std::scoped_lock lock(genericMutex_);
        return findNoLock(args);
    }

    Symbol* add(std::span<const GenericInstanceKey> args, Symbol* instance)
    {
        const std::scoped_lock lock(genericMutex_);
        return addNoLock(args, instance);
    }

    bool tryGetArgs(const Symbol& instance, SmallVector<GenericInstanceKey>& outArgs) const
    {
        const std::scoped_lock lock(genericMutex_);
        for (const auto& entry : genericInstances_)
        {
            if (entry.symbol != &instance)
                continue;

            outArgs = entry.args;
            return true;
        }

        return false;
    }

    std::mutex& getMutex() const noexcept { return genericMutex_; }

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

        for (const auto& entry : genericInstances_)
        {
            if (entry.symbol == instance)
                return entry.symbol;
        }

        GenericInstanceEntry entry;
        entry.symbol = instance;
        entry.args.assign(args.begin(), args.end());
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

    mutable std::mutex                genericMutex_;
    std::vector<GenericInstanceEntry> genericInstances_;
};

SWC_END_NAMESPACE();
