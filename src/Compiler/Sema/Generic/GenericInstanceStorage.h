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

namespace GenericInstanceStorage
{
    inline bool sameArgs(std::span<const GenericInstanceKey> lhs, std::span<const GenericInstanceKey> rhs) noexcept
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

    inline Symbol* find(std::span<const GenericInstanceEntry> entries, std::span<const GenericInstanceKey> args)
    {
        for (const auto& entry : entries)
        {
            if (sameArgs(entry.args.span(), args))
                return entry.symbol;
        }

        return nullptr;
    }

    inline Symbol* add(std::vector<GenericInstanceEntry>& entries, std::span<const GenericInstanceKey> args, Symbol* instance)
    {
        if (auto* existing = find(entries, args))
            return existing;

        for (const auto& entry : entries)
        {
            if (entry.symbol == instance)
                return entry.symbol;
        }

        GenericInstanceEntry entry;
        entry.symbol = instance;
        entry.args.assign(args.begin(), args.end());
        entries.push_back(std::move(entry));
        return instance;
    }

    inline bool tryGetArgs(std::span<const GenericInstanceEntry> entries, const Symbol& instance, SmallVector<GenericInstanceKey>& outArgs)
    {
        for (const auto& entry : entries)
        {
            if (entry.symbol != &instance)
                continue;

            outArgs = entry.args;
            return true;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
