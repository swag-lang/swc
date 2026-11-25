#pragma once

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

// Some compiler-owned allocations (in particular runtime type descriptors) refer
// back to each other. Start with those targets in one class and refine until the
// outgoing relocation edges agree. Other edges retain their exact symbol identity.
template<typename Name, typename Hash, typename Equal, typename Fold>
void foldCyclicContentGraph(const size_t count, Name name, Hash hash, Equal equal, Fold fold)
{
    std::vector<size_t>                          members;
    std::unordered_map<std::string_view, size_t> byName;
    for (size_t index = 0; index < count; ++index)
    {
        const auto symbol = name(index);
        if (symbol.empty())
            continue;
        byName.emplace(symbol, members.size());
        members.push_back(index);
    }
    if (members.size() < 2)
        return;

    std::vector<size_t>                               classes(members.size());
    std::vector<size_t>                               refined(members.size());
    std::unordered_map<uint32_t, std::vector<size_t>> buckets;
    const auto                                        classify = [&](const std::pair<bool, std::string_view> target, const std::string_view layout = {}) -> std::pair<size_t, std::string_view> {
        if (!layout.empty())
            return {2, layout};
        if (target.first)
            return {1, {}};
        const auto found = byName.find(target.second);
        if (found != byName.end())
            return {classes[found->second] + 3, {}};
        return {0, target.second};
    };
    // Each class is named by its first member. Since refinement only splits
    // classes, stable class numbers also mean stable relocation targets.
    for (;;)
    {
        buckets.clear();
        for (size_t index = 0; index < members.size(); ++index)
        {
            auto&      bucket = buckets[hash(members[index], classify)];
            const auto other  = std::ranges::find_if(bucket, [&](const size_t candidate) {
                return classes[index] == classes[candidate] && equal(members[index], members[candidate], classify);
            });
            if (other != bucket.end())
                refined[index] = *other;
            else
            {
                refined[index] = index;
                bucket.push_back(index);
            }
        }
        if (refined == classes)
            break;
        classes.swap(refined);
    }
    for (size_t index = 0; index < members.size(); ++index)
        if (classes[index] != index)
            fold(members[index], members[classes[index]]);
}

SWC_END_NAMESPACE();
