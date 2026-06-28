#pragma once
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

template<typename T, uint32_t CHUNK_BITS = 8>
class LookupTable
{
public:
    // Single-writer, multi-reader pointer table. Readers only need ref->pointer
    // lookup, so publish append-only slots and keep ownership elsewhere.
    static_assert(CHUNK_BITS < 31, "CHUNK_BITS must keep chunk size within uint32_t range");

    static constexpr uint32_t CHUNK_SIZE = 1u << CHUNK_BITS;
    static constexpr uint32_t CHUNK_MASK = CHUNK_SIZE - 1;
    using Chunk                          = std::array<std::atomic<T*>, CHUNK_SIZE>;

    LookupTable()
    {
        publishChunkSnapshot();
    }

    uint32_t size() const
    {
        return size_.load(std::memory_order_acquire);
    }

    void pushBack(T* value)
    {
        SWC_ASSERT(value != nullptr);

        const uint32_t index      = size_.load(std::memory_order_relaxed);
        const uint32_t chunkIndex = index >> CHUNK_BITS;
        const uint32_t chunkSlot  = index & CHUNK_MASK;
        if (chunkIndex == chunks_.size())
        {
            auto chunk = std::make_unique<Chunk>();
            for (std::atomic<T*>& slot : *chunk)
                slot.store(nullptr, std::memory_order_relaxed);
            chunks_.push_back(std::move(chunk));
            publishChunkSnapshot();
        }

        chunks_[chunkIndex]->at(chunkSlot).store(value, std::memory_order_release);
        size_.store(index + 1, std::memory_order_release);
    }

    T* at(uint32_t index) const
    {
        const uint32_t publishedSize = size_.load(std::memory_order_acquire);
        SWC_ASSERT(index < publishedSize);

        const auto* chunks = publishedChunks_.load(std::memory_order_acquire);
        SWC_ASSERT(chunks != nullptr);

        const uint32_t chunkIndex = index >> CHUNK_BITS;
        const uint32_t chunkSlot  = index & CHUNK_MASK;
        SWC_ASSERT(chunkIndex < chunks->size());

        T* value = (*chunks)[chunkIndex]->at(chunkSlot).load(std::memory_order_acquire);
        SWC_ASSERT(value != nullptr);
        return value;
    }

private:
    void publishChunkSnapshot()
    {
        auto chunkSnapshot = std::make_unique<std::vector<Chunk*>>();
        chunkSnapshot->reserve(chunks_.size());
        for (const auto& chunk : chunks_)
            chunkSnapshot->push_back(chunk.get());

        const auto* published = chunkSnapshot.get();
        publishedChunkStorage_.push_back(std::move(chunkSnapshot));
        publishedChunks_.store(published, std::memory_order_release);
    }

    std::vector<std::unique_ptr<Chunk>>                     chunks_;
    std::vector<std::unique_ptr<const std::vector<Chunk*>>> publishedChunkStorage_;
    std::atomic<const std::vector<Chunk*>*>                 publishedChunks_{nullptr};
    std::atomic<uint32_t>                                   size_{0};
};

SWC_END_NAMESPACE();
