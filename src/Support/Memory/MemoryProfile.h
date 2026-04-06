#pragma once

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace MemoryProfile
{
    class ScopedSuppress
    {
    public:
        ScopedSuppress();
        ~ScopedSuppress();

        ScopedSuppress(const ScopedSuppress&)            = delete;
        ScopedSuppress& operator=(const ScopedSuppress&) = delete;
    };

    void                 setDetailedTrackingEnabled(bool enabled);
    [[nodiscard]] void* allocateHeap(size_t size, size_t alignment, bool throwOnFailure);
    void                 freeHeap(void* block) noexcept;
    void                 trackExternalAlloc(const void* ptr, size_t size, uint32_t skipFrames = 0);
    void                 trackExternalFree(const void* ptr) noexcept;

#if SWC_HAS_STATS
    inline constexpr uint32_t MAX_CALLSTACK_FRAMES = 12;

    struct Hotspot
    {
        std::array<uintptr_t, MAX_CALLSTACK_FRAMES> frames{};
        size_t                                      currentBytes = 0;
        size_t                                      peakBytes    = 0;
        size_t                                      totalBytes   = 0;
        size_t                                      allocCount   = 0;
        size_t                                      freeCount    = 0;
        size_t                                      liveCount    = 0;
        uint32_t                                    frameCount   = 0;
    };

    struct Summary
    {
        size_t               totalCurrentBytes = 0;
        size_t               totalPeakBytes    = 0;
        std::vector<Hotspot> peakHotspots;
        std::vector<Hotspot> totalHotspots;
    };

    struct HotspotLocation
    {
        Utf8 allocationSite;
        Utf8 callerSite;
    };

    void buildSummary(Summary& outSummary, size_t topN = 10, size_t minPeakBytes = 256 * 1024, size_t minTotalBytes = 1024 * 1024);
    HotspotLocation formatHotspotLocation(const TaskContext* ctx, const Hotspot& hotspot);
#endif
}

SWC_END_NAMESPACE();
