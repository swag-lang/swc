#include "pch.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Memory/mimalloc/include/mimalloc.h"

#if SWC_HAS_STATS
#include "Main/Stats.h"
#endif

#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AllocationHeader
    {
        void*    rawPtr        = nullptr;
        size_t   trackedBytes  = 0;
        uint32_t signatureSlot = std::numeric_limits<uint32_t>::max();
        uint32_t flags         = 0;
    };

    [[nodiscard]] uintptr_t alignUpAddress(const uintptr_t value, const size_t alignment)
    {
        SWC_ASSERT(alignment != 0);
        const uintptr_t mask = static_cast<uintptr_t>(alignment - 1);
        return (value + mask) & ~mask;
    }

#if SWC_HAS_STATS
    constexpr uint32_t K_OVERFLOW_SLOT          = 0;
    constexpr uint32_t K_SIGNATURE_CAPACITY     = 16 * 1024;
    constexpr uint32_t K_EXTERNAL_CAPACITY      = 16 * 1024;
    constexpr uint32_t K_INVALID_SIGNATURE_SLOT = std::numeric_limits<uint32_t>::max();
    constexpr uint32_t K_CAPTURE_SKIP_FRAMES    = 3;
    constexpr uint32_t K_ALLOCATION_FLAG_TRACKED = 1u << 0;

    struct SignatureEntry
    {
        std::array<uintptr_t, MemoryProfile::MAX_CALLSTACK_FRAMES> frames{};
        uint64_t                                                   hash         = 0;
        size_t                                                     currentBytes = 0;
        size_t                                                     peakBytes    = 0;
        size_t                                                     totalBytes   = 0;
        size_t                                                     allocCount   = 0;
        size_t                                                     freeCount    = 0;
        size_t                                                     liveCount    = 0;
        uint32_t                                                   frameCount   = 0;
        bool                                                       used         = false;
    };

    struct ExternalEntry
    {
        const void* ptr           = nullptr;
        size_t      trackedBytes  = 0;
        uint32_t    signatureSlot = K_INVALID_SIGNATURE_SLOT;
        bool        used          = false;
    };

    struct MemoryProfileState
    {
        std::atomic<bool>                              detailedTrackingEnabled = false;
        std::mutex                                  mutex;
        std::array<SignatureEntry, K_SIGNATURE_CAPACITY> signatures{};
        std::array<ExternalEntry, K_EXTERNAL_CAPACITY>   externals{};
    };

    thread_local uint32_t g_SuppressDepth = 0;

    MemoryProfileState& memoryProfileState()
    {
        static MemoryProfileState state;
        static const bool         initialized = [] {
            state.signatures[K_OVERFLOW_SLOT].used = true;
            return true;
        }();
        SWC_UNUSED(initialized);
        return state;
    }

    [[nodiscard]] bool isTrackingSuppressed()
    {
        return g_SuppressDepth != 0;
    }

    [[nodiscard]] bool shouldTrackTotals()
    {
        return !isTrackingSuppressed();
    }

    [[nodiscard]] bool isDetailedTrackingEnabled()
    {
        return shouldTrackTotals() && memoryProfileState().detailedTrackingEnabled.load(std::memory_order_relaxed);
    }

    [[nodiscard]] uint64_t hashFrames(const std::array<uintptr_t, MemoryProfile::MAX_CALLSTACK_FRAMES>& frames, const uint32_t frameCount)
    {
        uint64_t hash = 1469598103934665603ull;
        for (uint32_t i = 0; i < frameCount; ++i)
        {
            hash ^= static_cast<uint64_t>(frames[i]);
            hash *= 1099511628211ull;
        }

        hash ^= frameCount;
        hash *= 1099511628211ull;
        return hash;
    }

    [[nodiscard]] uint32_t captureFrames(std::array<uintptr_t, MemoryProfile::MAX_CALLSTACK_FRAMES>& outFrames, const uint32_t skipFrames)
    {
        outFrames.fill(0);
        return Os::captureCallStack(std::span(outFrames), skipFrames + 1);
    }

    uint32_t findOrCreateSignatureSlotLocked(const std::array<uintptr_t, MemoryProfile::MAX_CALLSTACK_FRAMES>& frames, const uint32_t frameCount)
    {
        MemoryProfileState& state = memoryProfileState();
        if (!frameCount)
            return K_OVERFLOW_SLOT;

        const uint64_t hash  = hashFrames(frames, frameCount);
        const uint32_t start = 1 + static_cast<uint32_t>(hash % (K_SIGNATURE_CAPACITY - 1));

        for (uint32_t probe = 0; probe < K_SIGNATURE_CAPACITY - 1; ++probe)
        {
            const uint32_t    slot  = 1 + ((start - 1 + probe) % (K_SIGNATURE_CAPACITY - 1));
            SignatureEntry& entry = state.signatures[slot];
            if (!entry.used)
            {
                entry.used       = true;
                entry.hash       = hash;
                entry.frameCount = frameCount;
                entry.frames     = frames;
                return slot;
            }

            if (entry.hash != hash || entry.frameCount != frameCount)
                continue;

            bool sameFrames = true;
            for (uint32_t i = 0; i < frameCount; ++i)
            {
                if (entry.frames[i] != frames[i])
                {
                    sameFrames = false;
                    break;
                }
            }

            if (sameFrames)
                return slot;
        }

        return K_OVERFLOW_SLOT;
    }

    void applyAllocLocked(const uint32_t signatureSlot, const size_t trackedBytes)
    {
        SWC_ASSERT(signatureSlot < K_SIGNATURE_CAPACITY);
        SignatureEntry& entry = memoryProfileState().signatures[signatureSlot];
        entry.currentBytes += trackedBytes;
        entry.totalBytes += trackedBytes;
        entry.allocCount += 1;
        entry.liveCount += 1;
        if (entry.currentBytes > entry.peakBytes)
            entry.peakBytes = entry.currentBytes;
    }

    void applyFreeLocked(const uint32_t signatureSlot, const size_t trackedBytes)
    {
        SWC_ASSERT(signatureSlot < K_SIGNATURE_CAPACITY);
        SignatureEntry& entry = memoryProfileState().signatures[signatureSlot];
        SWC_ASSERT(entry.currentBytes >= trackedBytes);
        SWC_ASSERT(entry.liveCount > 0);
        entry.currentBytes -= trackedBytes;
        entry.freeCount += 1;
        entry.liveCount -= 1;
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

    void releaseExternalEntryLocked(ExternalEntry& entry)
    {
        if (!entry.used)
            return;

        if (entry.signatureSlot != K_INVALID_SIGNATURE_SLOT)
            applyFreeLocked(entry.signatureSlot, entry.trackedBytes);

        applyGlobalFree(entry.trackedBytes);
        entry = {};
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

    [[nodiscard]] bool isNoiseSymbol(const std::string_view symbolName)
    {
        return symbolName.contains("swc::MemoryProfile::") ||
               symbolName.contains("operator new") ||
               symbolName.contains("operator delete") ||
               symbolName.contains("mi_") ||
               symbolName.contains("malloc") ||
               symbolName.contains("free") ||
               symbolName.contains("std::") ||
               symbolName.contains("swc::Os::allocExecutableMemory") ||
               symbolName.contains("swc::Os::captureCallStack");
    }

    [[nodiscard]] bool isProjectFrame(const Os::ResolvedAddress& address)
    {
        return address.sourceLocation.contains("src\\") || address.sourceLocation.contains("src/");
    }

    [[nodiscard]] bool isAllocationWrapperSymbol(const std::string_view symbolName)
    {
        return symbolName.contains("swc::CompilerInstance::allocate") ||
               symbolName.contains("swc::CompilerInstance::allocateArray") ||
               symbolName.contains("swc::Arena::allocate") ||
               symbolName.contains("swc::DataSegment::reserveBytes") ||
               symbolName.contains("swc::DataSegment::addSpan") ||
               symbolName.contains("swc::DataSegment::addString") ||
               symbolName.contains("swc::PagedStore::pushBack") ||
               symbolName.contains("swc::PagedStore::pushCopySpan") ||
               symbolName.contains("swc::PagedStore::reserveRange");
    }

    [[nodiscard]] bool isAllocationSiteSymbol(const std::string_view symbolName)
    {
        return symbolName.contains("swc::Arena::addBlock") ||
               symbolName.contains("swc::PagedStore::newPage") ||
               symbolName.contains("swc::PagedStore::Page::Page") ||
               symbolName.contains("swc::PagedStore::allocate") ||
               symbolName.contains("swc::DataSegment::allocateStorageLocked") ||
               symbolName.contains("swc::Os::allocExecutableMemory");
    }

    [[nodiscard]] bool isGenericProjectSymbol(const std::string_view symbolName)
    {
        return symbolName.contains("swc::Command::") ||
               symbolName.contains("swc::CompilerInstance::processCommand") ||
               symbolName.contains("swc::CompilerInstance::run") ||
               symbolName.contains("swc::NativeBackendBuilder::run");
    }

    [[nodiscard]] Utf8 formatResolvedFrameLabel(const Os::ResolvedAddress& resolved, const uintptr_t address)
    {
        Utf8 label;
        if (!resolved.symbolName.empty())
            label = resolved.symbolName;
        else if (!resolved.moduleName.empty())
            label = resolved.moduleName;
        else
            label = std::format("0x{:016X}", address);

        if (!resolved.sourceLocation.empty())
        {
            label += " @ ";
            label += resolved.sourceLocation;
        }

        return label;
    }

    void selectTopHotspots(std::vector<MemoryProfile::Hotspot>& outHotspots,
                           std::vector<MemoryProfile::Hotspot>  allHotspots,
                           const size_t                         topN,
                           const size_t                         minPeakBytes,
                           const size_t                         minTotalBytes,
                           const auto&                          comparator)
    {
        std::ranges::sort(allHotspots, comparator);

        const auto appendFiltered = [&](const bool allowFallback) {
            for (const auto& hotspot : allHotspots)
            {
                const bool relevant = hotspot.peakBytes >= minPeakBytes || hotspot.totalBytes >= minTotalBytes;
                if (!allowFallback && !relevant)
                    continue;

                outHotspots.push_back(hotspot);
                if (outHotspots.size() >= topN)
                    return;
            }
        };

        appendFiltered(false);
        if (outHotspots.empty())
            appendFiltered(true);
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
        header->signatureSlot = K_INVALID_SIGNATURE_SLOT;
        header->flags         = 0;

        if (shouldTrackTotals())
        {
            header->flags = K_ALLOCATION_FLAG_TRACKED;
            if (isDetailedTrackingEnabled())
            {
                std::array<uintptr_t, MAX_CALLSTACK_FRAMES> frames{};
                const uint32_t frameCount = captureFrames(frames, K_CAPTURE_SKIP_FRAMES);

                const std::scoped_lock lock(memoryProfileState().mutex);
                header->signatureSlot = findOrCreateSignatureSlotLocked(frames, frameCount);
                applyAllocLocked(header->signatureSlot, header->trackedBytes);
                applyGlobalAlloc(header->trackedBytes);
            }
            else
            {
                applyGlobalAlloc(header->trackedBytes);
            }
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
            if (header->signatureSlot != K_INVALID_SIGNATURE_SLOT)
            {
                const std::scoped_lock lock(memoryProfileState().mutex);
                applyFreeLocked(header->signatureSlot, header->trackedBytes);
            }

            applyGlobalFree(header->trackedBytes);
        }

        mi_free(header->rawPtr);
#else
        mi_free(block);
#endif
    }

    void trackExternalAlloc(const void* ptr, const size_t size, const uint32_t skipFrames)
    {
#if SWC_HAS_STATS
        if (!ptr || size == 0 || isTrackingSuppressed())
            return;

        std::array<uintptr_t, MAX_CALLSTACK_FRAMES> frames{};
        uint32_t                                    frameCount     = 0;
        const bool                                  trackDetailed  = isDetailedTrackingEnabled();
        if (trackDetailed)
            frameCount = captureFrames(frames, K_CAPTURE_SKIP_FRAMES + skipFrames);

        const std::scoped_lock lock(memoryProfileState().mutex);
        const uint32_t         externalSlot  = findExternalSlotLocked(ptr);
        SWC_ASSERT(externalSlot != K_EXTERNAL_CAPACITY);
        if (externalSlot == K_EXTERNAL_CAPACITY)
            return;

        ExternalEntry& entry = memoryProfileState().externals[externalSlot];
        if (entry.used)
            releaseExternalEntryLocked(entry);

        entry.used          = true;
        entry.ptr           = ptr;
        entry.trackedBytes  = size;
        entry.signatureSlot = K_INVALID_SIGNATURE_SLOT;

        if (trackDetailed)
        {
            entry.signatureSlot = findOrCreateSignatureSlotLocked(frames, frameCount);
            applyAllocLocked(entry.signatureSlot, size);
        }

        applyGlobalAlloc(size);
#else
        SWC_UNUSED(ptr);
        SWC_UNUSED(size);
        SWC_UNUSED(skipFrames);
#endif
    }

    void trackExternalFree(const void* ptr) noexcept
    {
#if SWC_HAS_STATS
        if (!ptr)
            return;

        const std::scoped_lock lock(memoryProfileState().mutex);
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
    void buildSummary(Summary& outSummary, const size_t topN, const size_t minPeakBytes, const size_t minTotalBytes)
    {
        ScopedSuppress suppress;
        outSummary = {};

        std::vector<Hotspot> allHotspots;
        {
            const std::scoped_lock lock(memoryProfileState().mutex);
            outSummary.totalCurrentBytes = Stats::get().memAllocated.load(std::memory_order_relaxed);
            outSummary.totalPeakBytes    = Stats::get().memMaxAllocated.load(std::memory_order_relaxed);

            for (const SignatureEntry& entry : memoryProfileState().signatures)
            {
                if (!entry.used)
                    continue;
                if (!entry.currentBytes && !entry.totalBytes && !entry.allocCount)
                    continue;

                Hotspot hotspot;
                hotspot.frames       = entry.frames;
                hotspot.currentBytes = entry.currentBytes;
                hotspot.peakBytes    = entry.peakBytes;
                hotspot.totalBytes   = entry.totalBytes;
                hotspot.allocCount   = entry.allocCount;
                hotspot.freeCount    = entry.freeCount;
                hotspot.liveCount    = entry.liveCount;
                hotspot.frameCount   = entry.frameCount;
                allHotspots.push_back(std::move(hotspot));
            }
        }

        selectTopHotspots(outSummary.peakHotspots, std::vector<Hotspot>(allHotspots), topN, minPeakBytes, minTotalBytes, [](const Hotspot& lhs, const Hotspot& rhs) {
            if (lhs.peakBytes != rhs.peakBytes)
                return lhs.peakBytes > rhs.peakBytes;
            if (lhs.totalBytes != rhs.totalBytes)
                return lhs.totalBytes > rhs.totalBytes;
            return lhs.allocCount > rhs.allocCount;
        });

        selectTopHotspots(outSummary.totalHotspots, std::move(allHotspots), topN, minPeakBytes, minTotalBytes, [](const Hotspot& lhs, const Hotspot& rhs) {
            if (lhs.totalBytes != rhs.totalBytes)
                return lhs.totalBytes > rhs.totalBytes;
            if (lhs.peakBytes != rhs.peakBytes)
                return lhs.peakBytes > rhs.peakBytes;
            return lhs.allocCount > rhs.allocCount;
        });
    }

    HotspotLocation formatHotspotLocation(const TaskContext* ctx, const Hotspot& hotspot)
    {
        ScopedSuppress suppress;
        HotspotLocation result;

        if (!hotspot.frameCount)
        {
            result.allocationSite = "<overflow>";
            return result;
        }

        Utf8 fallback;
        struct ResolvedFrame
        {
            Utf8                label;
            Os::ResolvedAddress resolved;
        };

        std::vector<ResolvedFrame> resolvedFrames;
        resolvedFrames.reserve(hotspot.frameCount);

        for (uint32_t i = 0; i < hotspot.frameCount; ++i)
        {
            Os::ResolvedAddress resolved;
            if (!Os::resolveAddress(resolved, hotspot.frames[i], ctx))
            {
                if (fallback.empty())
                    fallback = std::format("0x{:016X}", hotspot.frames[i]);
                continue;
            }

            Utf8 label = formatResolvedFrameLabel(resolved, hotspot.frames[i]);
            if (fallback.empty())
                fallback = label;

            if (isNoiseSymbol(resolved.symbolName))
                continue;

            resolvedFrames.push_back({
                .label    = std::move(label),
                .resolved = std::move(resolved),
            });
        }

        size_t allocationIndex = std::numeric_limits<size_t>::max();
        for (size_t i = 0; i < resolvedFrames.size(); ++i)
        {
            const auto& frame = resolvedFrames[i];
            if (!isAllocationSiteSymbol(frame.resolved.symbolName))
                continue;

            result.allocationSite = frame.label;
            allocationIndex       = i;
            break;
        }

        if (result.allocationSite.empty())
        {
            for (size_t i = 0; i < resolvedFrames.size(); ++i)
            {
                const auto& frame = resolvedFrames[i];
                if (!isProjectFrame(frame.resolved))
                    continue;
                if (isAllocationWrapperSymbol(frame.resolved.symbolName))
                    continue;
                if (isGenericProjectSymbol(frame.resolved.symbolName))
                    continue;

                result.allocationSite = frame.label;
                allocationIndex       = i;
                break;
            }
        }

        if (result.allocationSite.empty())
        {
            for (size_t i = 0; i < resolvedFrames.size(); ++i)
            {
                const auto& frame = resolvedFrames[i];
                if (!isProjectFrame(frame.resolved))
                    continue;

                result.allocationSite = frame.label;
                allocationIndex       = i;
                break;
            }
        }

        if (result.allocationSite.empty() && !resolvedFrames.empty())
        {
            result.allocationSite = resolvedFrames.front().label;
            allocationIndex       = 0;
        }

        if (result.allocationSite.empty())
        {
            if (!fallback.empty())
                result.allocationSite = fallback;
            else
                result.allocationSite = std::format("0x{:016X}", hotspot.frames[0]);
            return result;
        }

        if (allocationIndex < resolvedFrames.size() &&
            isAllocationSiteSymbol(resolvedFrames[allocationIndex].resolved.symbolName))
        {
            for (size_t i = allocationIndex + 1; i < resolvedFrames.size(); ++i)
            {
                const auto& frame = resolvedFrames[i];
                if (!isProjectFrame(frame.resolved))
                    continue;
                if (isAllocationWrapperSymbol(frame.resolved.symbolName))
                    continue;
                if (isGenericProjectSymbol(frame.resolved.symbolName))
                    continue;

                result.callerSite = frame.label;
                break;
            }
        }

        return result;
    }
#endif
}

SWC_END_NAMESPACE();
