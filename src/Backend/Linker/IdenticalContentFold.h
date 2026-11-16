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

SWC_END_NAMESPACE();
