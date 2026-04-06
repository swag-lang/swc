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
    void                 trackExternalAlloc(const void* ptr, size_t size, const char* category = nullptr, const char* file = nullptr, uint32_t line = 0);
    void                 trackExternalFree(const void* ptr) noexcept;

#if SWC_HAS_STATS
    inline constexpr uint32_t MAX_CATEGORIES    = 512;
    inline constexpr uint32_t INVALID_CATEGORY  = std::numeric_limits<uint32_t>::max();

    struct CategoryInfo
    {
        const char*         name = nullptr;
        const char*         file = nullptr;
        uint32_t            line = 0;
        std::atomic<size_t> currentBytes{0};
        std::atomic<size_t> peakBytes{0};
        std::atomic<size_t> totalBytes{0};
        std::atomic<size_t> allocCount{0};
        std::atomic<size_t> freeCount{0};
    };

    // Scoped category tag — sets the active category for all allocations within the scope.
    class ScopedCategory
    {
    public:
        ScopedCategory(const char* category, const char* file, uint32_t line);
        ~ScopedCategory();

        ScopedCategory(const ScopedCategory&)            = delete;
        ScopedCategory& operator=(const ScopedCategory&) = delete;

    private:
        uint32_t prevIndex_;
    };

    struct CategorySnapshot
    {
        const char* name         = nullptr;
        const char* file         = nullptr;
        uint32_t    line         = 0;
        size_t      currentBytes = 0;
        size_t      peakBytes    = 0;
        size_t      totalBytes   = 0;
        size_t      allocCount   = 0;
        size_t      freeCount    = 0;
    };

    struct Summary
    {
        size_t                        totalCurrentBytes = 0;
        size_t                        totalPeakBytes    = 0;
        std::vector<CategorySnapshot> categories;
    };

    void buildSummary(Summary& outSummary);
#endif
}

#if SWC_HAS_STATS
#define SWC_MEM_CONCAT_IMPL(a, b) a##b
#define SWC_MEM_CONCAT(a, b)      SWC_MEM_CONCAT_IMPL(a, b)
#define SWC_MEM_SCOPE(category)   ::swc::MemoryProfile::ScopedCategory SWC_MEM_CONCAT(_swc_mem_, __LINE__)(category, __FILE__, __LINE__)
#else
#define SWC_MEM_SCOPE(category) ((void) 0)
#endif

SWC_END_NAMESPACE();
