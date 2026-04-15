#pragma once
SWC_BEGIN_NAMESPACE();

class TaskContext;

struct Stats
{
    std::atomic<uint64_t> timeTotal   = 0;
    std::atomic<size_t>   numErrors   = 0;
    std::atomic<size_t>   numWarnings = 0;
    std::atomic<size_t>   numFiles    = 0;
    std::atomic<size_t>   numTokens   = 0;

#if SWC_HAS_STATS
    std::atomic<uint64_t> timeLoadFile   = 0;
    std::atomic<uint64_t> timeLexer      = 0;
    std::atomic<uint64_t> timeParser     = 0;
    std::atomic<uint64_t> timeSema       = 0;
    std::atomic<uint64_t> timeCodeGen    = 0;
    std::atomic<uint64_t> timeMicroLower = 0;

    std::atomic<size_t> memAllocated    = 0;
    std::atomic<size_t> memMaxAllocated = 0;

    std::atomic<size_t> numAstNodes                   = 0;
    std::atomic<size_t> numVisitedAstNodes            = 0;
    std::atomic<size_t> numConstants                  = 0;
    std::atomic<size_t> numConstantBuiltinFastHits    = 0;
    std::atomic<size_t> numConstantSmallScalarCacheHits   = 0;
    std::atomic<size_t> numConstantSmallScalarCacheMisses = 0;
    std::atomic<size_t> numConstantSlowPathCalls          = 0;
    std::atomic<size_t> numTypes                      = 0;
    std::atomic<size_t> numIdentifiers                = 0;
    std::atomic<size_t> numSymbols                    = 0;
    std::atomic<size_t> numMicroInstrInitial          = 0;
    std::atomic<size_t> numMicroInstrAfterStart       = 0;
    std::atomic<size_t> numMicroInstrAfterPreRaOptim  = 0;
    std::atomic<size_t> numMicroInstrAfterRa          = 0;
    std::atomic<size_t> numMicroInstrAfterPostRaSetup = 0;
    std::atomic<size_t> numMicroInstrAfterPostRaOptim = 0;
    std::atomic<size_t> numMicroInstrFinal            = 0;
    std::atomic<size_t> numCodeGenFunctions           = 0;
#endif // SWC_HAS_STATS

    static Stats& get()
    {
        static Stats stats;
        return stats;
    }

    static size_t getNumErrors()
    {
        return get().numErrors.load(std::memory_order_relaxed);
    }

    static bool hasError()
    {
        return get().numErrors.load(std::memory_order_relaxed) > 0;
    }

    static void addError()
    {
        get().numErrors.fetch_add(1, std::memory_order_relaxed);
    }

    static void setMax(const std::atomic<size_t>& valCur, std::atomic<size_t>& valMax)
    {
        const size_t current = valCur.load(std::memory_order_relaxed);
        size_t       prevMax = valMax.load(std::memory_order_relaxed);
        while (current > prevMax && !valMax.compare_exchange_weak(prevMax, current, std::memory_order_relaxed))
        {
        }
    }

    void print(const TaskContext& ctx) const;
};

SWC_END_NAMESPACE();
