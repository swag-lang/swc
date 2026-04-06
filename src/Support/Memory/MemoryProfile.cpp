#include "pch.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Memory/mimalloc/include/mimalloc.h"

#if SWC_HAS_STATS
#include "Main/Stats.h"
#endif

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AllocationHeader
    {
        void*    rawPtr        = nullptr;
        size_t   trackedBytes  = 0;
        uint32_t categoryIndex = std::numeric_limits<uint32_t>::max();
        uint32_t flags         = 0;
    };

    [[nodiscard]] uintptr_t alignUpAddress(const uintptr_t value, const size_t alignment)
    {
        SWC_ASSERT(alignment != 0);
        const uintptr_t mask = static_cast<uintptr_t>(alignment - 1);
        return (value + mask) & ~mask;
    }

#if SWC_HAS_STATS
    constexpr uint32_t K_EXTERNAL_CAPACITY       = 16 * 1024;
    constexpr uint32_t K_INVALID_CATEGORY        = MemoryProfile::INVALID_CATEGORY;
    constexpr uint32_t K_ALLOCATION_FLAG_TRACKED  = 1u << 0;

    struct ExternalEntry
    {
        const void* ptr           = nullptr;
        size_t      trackedBytes  = 0;
        uint32_t    categoryIndex = K_INVALID_CATEGORY;
        bool        used          = false;
    };

    struct MemoryProfileState
    {
        std::atomic<bool>                                              detailedTrackingEnabled = false;
        std::array<MemoryProfile::CategoryInfo, MemoryProfile::MAX_CATEGORIES> categories{};
        std::atomic<uint32_t>                                          categoryCount = 0;
        std::mutex                                                     registrationMutex;
        std::mutex                                                     externalMutex;
        std::array<ExternalEntry, K_EXTERNAL_CAPACITY>                 externals{};
    };

    thread_local uint32_t g_SuppressDepth    = 0;
    thread_local uint32_t g_CurrentCategory  = K_INVALID_CATEGORY;

    MemoryProfileState& memoryProfileState()
    {
        static MemoryProfileState state;
        return state;
    }

    [[nodiscard]] bool isTrackingSuppressed()
    {
        return g_SuppressDepth != 0;
    }

    [[nodiscard]] bool shouldTrack()
    {
        return !isTrackingSuppressed();
    }

    [[nodiscard]] bool isDetailedTrackingEnabled()
    {
        return shouldTrack() && memoryProfileState().detailedTrackingEnabled.load(std::memory_order_relaxed);
    }

    uint32_t findOrRegisterCategory(const char* name, const char* file, const uint32_t line)
    {
        MemoryProfileState& state = memoryProfileState();
        const uint32_t      count = state.categoryCount.load(std::memory_order_acquire);

        // Search existing categories (lock-free read of immutable fields)
        for (uint32_t i = 0; i < count; ++i)
        {
            if (state.categories[i].name == name)
                return i;
        }

        // Register new category under lock
        const std::scoped_lock lock(state.registrationMutex);

        // Re-check after acquiring lock
        const uint32_t countAfterLock = state.categoryCount.load(std::memory_order_relaxed);
        for (uint32_t i = count; i < countAfterLock; ++i)
        {
            if (state.categories[i].name == name)
                return i;
        }

        SWC_ASSERT(countAfterLock < MemoryProfile::MAX_CATEGORIES);
        if (countAfterLock >= MemoryProfile::MAX_CATEGORIES)
            return K_INVALID_CATEGORY;

        const uint32_t newIndex = countAfterLock;
        auto&          cat      = state.categories[newIndex];
        cat.name = name;
        cat.file = file;
        cat.line = line;
        state.categoryCount.store(newIndex + 1, std::memory_order_release);
        return newIndex;
    }

    void applyCategoryAlloc(const uint32_t categoryIndex, const size_t trackedBytes)
    {
        if (categoryIndex == K_INVALID_CATEGORY)
            return;

        auto& cat = memoryProfileState().categories[categoryIndex];
        const size_t newCurrent = cat.currentBytes.fetch_add(trackedBytes, std::memory_order_relaxed) + trackedBytes;
        cat.totalBytes.fetch_add(trackedBytes, std::memory_order_relaxed);
        cat.allocCount.fetch_add(1, std::memory_order_relaxed);

        // Update peak with CAS loop
        size_t prevPeak = cat.peakBytes.load(std::memory_order_relaxed);
        while (newCurrent > prevPeak && !cat.peakBytes.compare_exchange_weak(prevPeak, newCurrent, std::memory_order_relaxed))
        {
        }
    }

    void applyCategoryFree(const uint32_t categoryIndex, const size_t trackedBytes)
    {
        if (categoryIndex == K_INVALID_CATEGORY)
            return;

        auto& cat = memoryProfileState().categories[categoryIndex];
        cat.currentBytes.fetch_sub(trackedBytes, std::memory_order_relaxed);
        cat.freeCount.fetch_add(1, std::memory_order_relaxed);
    }

    void applyGlobalAlloc(const size_t trackedBytes)
    {
        Stats& stats = Stats::get();
        stats.memAllocated.fetch_add(trackedBytes, std::memory_order_relaxed);
        Stats::setMax(stats.memAllocated, stats.memMaxAllocated);
    }

    void applyGlobalFree(const size_t trackedBytes)
    {
        Stats::get().memAllocated.fetch_sub(trackedBytes, std::memory_order_relaxed);
    }

    uint32_t findExternalSlotLocked(const void* ptr)
    {
        MemoryProfileState& state = memoryProfileState();
        const auto          hash  = static_cast<uintptr_t>(reinterpret_cast<uintptr_t>(ptr) >> 4);
        const uint32_t      start = static_cast<uint32_t>(hash % K_EXTERNAL_CAPACITY);
        uint32_t            firstFree = K_EXTERNAL_CAPACITY;
        for (uint32_t probe = 0; probe < K_EXTERNAL_CAPACITY; ++probe)
        {
            const uint32_t   slot  = (start + probe) % K_EXTERNAL_CAPACITY;
            ExternalEntry& entry = state.externals[slot];
            if (entry.used)
            {
                if (entry.ptr == ptr)
                    return slot;
                continue;
            }

            if (firstFree == K_EXTERNAL_CAPACITY)
                firstFree = slot;
        }

        return firstFree;
    }

    void releaseExternalEntryLocked(ExternalEntry& entry)
    {
        if (!entry.used)
            return;

        applyCategoryFree(entry.categoryIndex, entry.trackedBytes);
        applyGlobalFree(entry.trackedBytes);
        entry = {};
    }
#else
    thread_local uint32_t g_SuppressDepth = 0;
#endif
}

namespace MemoryProfile
{
    ScopedSuppress::ScopedSuppress()
    {
        ++g_SuppressDepth;
    }

    ScopedSuppress::~ScopedSuppress()
    {
        SWC_ASSERT(g_SuppressDepth > 0);
        --g_SuppressDepth;
    }

    void setDetailedTrackingEnabled(const bool enabled)
    {
#if SWC_HAS_STATS
        memoryProfileState().detailedTrackingEnabled.store(enabled, std::memory_order_relaxed);
#else
        SWC_UNUSED(enabled);
#endif
    }

    void* allocateHeap(size_t size, size_t alignment, const bool throwOnFailure)
    {
        if (size == 0)
            size = 1;

#if SWC_HAS_STATS
        const size_t effectiveAlignment = std::max(alignment, alignof(AllocationHeader));
        const size_t requestSize        = size + effectiveAlignment + sizeof(AllocationHeader);

        void* rawPtr = mi_malloc(requestSize);
        if (!rawPtr)
        {
            if (throwOnFailure)
                throw std::bad_alloc();
            return nullptr;
        }

        const auto  rawAddress  = reinterpret_cast<uintptr_t>(rawPtr);
        const auto  userAddress = alignUpAddress(rawAddress + sizeof(AllocationHeader), effectiveAlignment);
        auto* const header      = reinterpret_cast<AllocationHeader*>(userAddress - sizeof(AllocationHeader));
        const size_t usableSize = mi_usable_size(rawPtr);
        const size_t userOffset = static_cast<size_t>(userAddress - rawAddress);

        header->rawPtr        = rawPtr;
        header->trackedBytes  = usableSize > userOffset ? usableSize - userOffset : size;
        header->categoryIndex = K_INVALID_CATEGORY;
        header->flags         = 0;

        if (shouldTrack())
        {
            header->flags = K_ALLOCATION_FLAG_TRACKED;

            if (isDetailedTrackingEnabled())
            {
                header->categoryIndex = g_CurrentCategory;
                applyCategoryAlloc(header->categoryIndex, header->trackedBytes);
            }

            applyGlobalAlloc(header->trackedBytes);
        }

        return reinterpret_cast<void*>(userAddress);
#else
        void* ptr = mi_malloc_aligned(size, alignment);
        if (!ptr && throwOnFailure)
            throw std::bad_alloc();
        return ptr;
#endif
    }

    void freeHeap(void* block) noexcept
    {
        if (!block)
            return;

#if SWC_HAS_STATS
        auto* const header = reinterpret_cast<AllocationHeader*>(block) - 1;

        if (header->flags & K_ALLOCATION_FLAG_TRACKED)
        {
            applyCategoryFree(header->categoryIndex, header->trackedBytes);
            applyGlobalFree(header->trackedBytes);
        }

        mi_free(header->rawPtr);
#else
        mi_free(block);
#endif
    }

    void trackExternalAlloc(const void* ptr, const size_t size, const char* category, const char* file, const uint32_t line)
    {
#if SWC_HAS_STATS
        if (!ptr || size == 0 || isTrackingSuppressed())
            return;

        const bool     trackDetailed = isDetailedTrackingEnabled();
        uint32_t       catIndex      = K_INVALID_CATEGORY;
        if (trackDetailed)
        {
            if (category)
                catIndex = findOrRegisterCategory(category, file, line);
            else
                catIndex = g_CurrentCategory;
        }

        const std::scoped_lock lock(memoryProfileState().externalMutex);
        const uint32_t         externalSlot = findExternalSlotLocked(ptr);
        SWC_ASSERT(externalSlot != K_EXTERNAL_CAPACITY);
        if (externalSlot == K_EXTERNAL_CAPACITY)
            return;

        ExternalEntry& entry = memoryProfileState().externals[externalSlot];
        if (entry.used)
            releaseExternalEntryLocked(entry);

        entry.used          = true;
        entry.ptr           = ptr;
        entry.trackedBytes  = size;
        entry.categoryIndex = catIndex;

        if (trackDetailed)
            applyCategoryAlloc(catIndex, size);

        applyGlobalAlloc(size);
#else
        SWC_UNUSED(ptr);
        SWC_UNUSED(size);
        SWC_UNUSED(category);
        SWC_UNUSED(file);
        SWC_UNUSED(line);
#endif
    }

    void trackExternalFree(const void* ptr) noexcept
    {
#if SWC_HAS_STATS
        if (!ptr)
            return;

        const std::scoped_lock lock(memoryProfileState().externalMutex);
        const uint32_t         externalSlot = findExternalSlotLocked(ptr);
        if (externalSlot == K_EXTERNAL_CAPACITY)
            return;

        ExternalEntry& entry = memoryProfileState().externals[externalSlot];
        if (!entry.used || entry.ptr != ptr)
            return;

        releaseExternalEntryLocked(entry);
#else
        SWC_UNUSED(ptr);
#endif
    }

#if SWC_HAS_STATS
    ScopedCategory::ScopedCategory(const char* category, const char* file, const uint32_t line)
    {
        prevIndex_       = g_CurrentCategory;
        g_CurrentCategory = findOrRegisterCategory(category, file, line);
    }

    ScopedCategory::~ScopedCategory()
    {
        g_CurrentCategory = prevIndex_;
    }

    void buildSummary(Summary& outSummary)
    {
        ScopedSuppress suppress;
        outSummary = {};

        MemoryProfileState& state = memoryProfileState();
        outSummary.totalCurrentBytes = Stats::get().memAllocated.load(std::memory_order_relaxed);
        outSummary.totalPeakBytes    = Stats::get().memMaxAllocated.load(std::memory_order_relaxed);

        const uint32_t count = state.categoryCount.load(std::memory_order_acquire);
        outSummary.categories.reserve(count);

        for (uint32_t i = 0; i < count; ++i)
        {
            const auto& cat = state.categories[i];
            if (!cat.allocCount.load(std::memory_order_relaxed))
                continue;

            CategorySnapshot snap;
            snap.name         = cat.name;
            snap.file         = cat.file;
            snap.line         = cat.line;
            snap.currentBytes = cat.currentBytes.load(std::memory_order_relaxed);
            snap.peakBytes    = cat.peakBytes.load(std::memory_order_relaxed);
            snap.totalBytes   = cat.totalBytes.load(std::memory_order_relaxed);
            snap.allocCount   = cat.allocCount.load(std::memory_order_relaxed);
            snap.freeCount    = cat.freeCount.load(std::memory_order_relaxed);
            outSummary.categories.push_back(snap);
        }
    }
#endif
}

SWC_END_NAMESPACE();
