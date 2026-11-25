#pragma once
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

// Folding a target changes the keys of its readers. Revisit only those readers,
// transferring them to the survivor so later folds propagate through the graph.
template<typename Hash, typename Equal, typename Fold>
void foldIdenticalContentGraph(std::vector<std::vector<size_t>>& readers, Hash hash, Equal equal, Fold fold)
{
    struct State
    {
        uint32_t hash       = 0;
        size_t   bucketSlot = SIZE_MAX;
        bool     queued     = true;
        bool     folded     = false;
    };
    std::vector<State>  states(readers.size());
    std::vector<size_t> pending;
    pending.reserve(states.size());
    for (size_t index = 0; index < states.size(); ++index)
        pending.push_back(index);
    std::unordered_map<uint32_t, std::vector<size_t>> buckets;
    for (size_t next = 0; next < pending.size(); ++next)
    {
        const size_t index = pending[next];
        State&       state = states[index];
        state.queued       = false;
        if (state.folded)
            continue;
        if (state.bucketSlot != SIZE_MAX)
        {
            auto& previous                     = buckets[state.hash];
            previous[state.bucketSlot]         = previous.back();
            states[previous.back()].bucketSlot = state.bucketSlot;
            previous.pop_back();
            state.bucketSlot = SIZE_MAX;
        }
        state.hash           = hash(index);
        auto&      bucket    = buckets[state.hash];
        const auto duplicate = std::ranges::find_if(bucket, [&](const size_t other) { return equal(index, other); });
        if (duplicate == bucket.end())
        {
            state.bucketSlot = bucket.size();
            bucket.push_back(index);
            continue;
        }
        const size_t canonical = *duplicate;
        fold(index, canonical);
        state.folded           = true;
        auto  affected         = std::move(readers[index]);
        auto& canonicalReaders = readers[canonical];
        for (const size_t reader : affected)
        {
            State& dependent = states[reader];
            if (dependent.folded)
                continue;
            canonicalReaders.push_back(reader);
            if (!dependent.queued)
            {
                dependent.queued = true;
                pending.push_back(reader);
            }
        }
    }
}

// Establish exact classes using immutable contents and relocation shapes, then
// split those classes on the destination classes of their recursive edges.
template<typename Name, typename Hash, typename Equal, typename Fold>
void foldCyclicContentGraph(const size_t count, Name name, Hash hash, Equal equal, Fold fold)
{
    struct Member
    {
        size_t candidate;
        size_t firstEdge = 0;
        size_t endEdge   = 0;
    };

    std::vector<Member>                          members;
    std::unordered_map<std::string_view, size_t> byName;
    for (size_t index = 0; index < count; ++index)
    {
        const auto symbol = name(index);
        if (symbol.empty())
            continue;
        byName.emplace(symbol, members.size());
        members.push_back({index});
    }
    if (members.size() < 2)
        return;

    std::vector<size_t>                               edges;
    std::vector<size_t>                               classes(members.size());
    std::vector<size_t>                               refined(members.size());
    std::vector<size_t>                               classSizes(members.size());
    std::unordered_map<uint32_t, std::vector<size_t>> buckets;
    const auto                                        classify = [&](const std::pair<bool, std::string_view> target, const std::string_view layout, const bool recordEdge) -> std::pair<size_t, std::string_view> {
        if (!layout.empty())
            return {2, layout};
        if (target.first)
            return {1, {}};
        const auto found = byName.find(target.second);
        if (found == byName.end())
            return {0, target.second};
        if (recordEdge)
            edges.push_back(found->second);
        return {3, {}};
    };
    const auto findClass = [&](const size_t index, const uint32_t key, const auto& matches) {
        auto&      bucket = buckets[key];
        const auto other  = std::ranges::find_if(bucket, matches);
        if (other != bucket.end())
            return *other;
        bucket.push_back(index);
        return index;
    };

    for (size_t index = 0; index < members.size(); ++index)
    {
        Member& member     = members[index];
        member.firstEdge   = edges.size();
        const uint32_t key = hash(member.candidate, [&](const auto target, const std::string_view layout = {}) {
            return classify(target, layout, true);
        });
        member.endEdge     = edges.size();
        classes[index]     = findClass(index, key, [&](const size_t other) {
            return equal(member.candidate, members[other].candidate, [&](const auto target, const std::string_view layout = {}) {
                return classify(target, layout, false);
            });
        });
        ++classSizes[classes[index]];
    }

    // Within a class, each recursive edge already occupies the same relocation
    // slot. Later rounds need only its numeric target class.
    const auto edgeClasses = [&](const Member& member) {
        return std::span(edges).subspan(member.firstEdge, member.endEdge - member.firstEdge) |
               std::views::transform([&](const size_t target) { return classes[target]; });
    };
    for (;;)
    {
        bool changed = false;
        buckets.clear();
        for (size_t index = 0; index < members.size(); ++index)
        {
            const Member& member     = members[index];
            const size_t  priorClass = classes[index];
            refined[index]           = priorClass;
            if (classSizes[priorClass] == 1 || member.firstEdge == member.endEdge)
                continue;
            uint32_t key = Math::hashCombine(0, priorClass);
            for (const size_t targetClass : edgeClasses(member))
                key = Math::hashCombine(key, targetClass);
            refined[index] = findClass(index, key, [&](const size_t other) {
                return priorClass == classes[other] && std::ranges::equal(edgeClasses(member), edgeClasses(members[other]));
            });
            changed |= refined[index] != priorClass;
        }
        if (!changed)
            break;
        classes.swap(refined);
        std::ranges::fill(classSizes, 0);
        for (const size_t group : classes)
            ++classSizes[group];
    }
    for (size_t index = 0; index < members.size(); ++index)
        if (classes[index] != index)
            fold(members[index].candidate, members[classes[index]].candidate);
}

SWC_END_NAMESPACE();
