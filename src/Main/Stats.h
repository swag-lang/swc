#pragma once
SWC_BEGIN_NAMESPACE();

class TaskContext;

struct Stats
{
    std::atomic<uint64_t> timeTotal   = 0;
    std::atomic<size_t>   numErrors   = 0;
    std::atomic<size_t>   numWarnings = 0;

#if SWC_HAS_STATS
    std::atomic<uint64_t> timeLoadFile   = 0;
    std::atomic<uint64_t> timeLexer      = 0;
    std::atomic<uint64_t> timeParser     = 0;
    std::atomic<uint64_t> timeSema       = 0;
    std::atomic<uint64_t> timeCodeGen    = 0;
    std::atomic<uint64_t> timeMicroLower = 0;

    std::atomic<size_t> memAllocated               = 0;
    std::atomic<size_t> memMaxAllocated            = 0;
    std::atomic<size_t> memFrontendSource          = 0;
    std::atomic<size_t> memFrontendTokens          = 0;
    std::atomic<size_t> memFrontendLines           = 0;
    std::atomic<size_t> memFrontendTrivia          = 0;
    std::atomic<size_t> memFrontendIdentifiers     = 0;
    std::atomic<size_t> memFrontendAstReserved     = 0;
    std::atomic<size_t> memSemaNodePayloadReserved = 0;
    std::atomic<size_t> memSemaIdentifiersReserved = 0;
    std::atomic<size_t> memCompilerArenaReserved   = 0;
    std::atomic<size_t> memConstants               = 0;
    std::atomic<size_t> memConstantsReserved       = 0;
    std::atomic<size_t> memTypes                   = 0;
    std::atomic<size_t> memTypesReserved           = 0;
    std::atomic<size_t> memSymbols                 = 0;
    std::atomic<size_t> memSymbolMaps              = 0;
    std::atomic<size_t> memJitReserved             = 0;
    std::atomic<size_t> memMicroStorageFinal       = 0;
    std::atomic<size_t> memDataSegmentConstant     = 0;
    std::atomic<size_t> memDataSegmentGlobalZero   = 0;
    std::atomic<size_t> memDataSegmentGlobalInit   = 0;
    std::atomic<size_t> memDataSegmentCompiler     = 0;

    std::atomic<size_t> numFiles             = 0;
    std::atomic<size_t> numTokens            = 0;
    std::atomic<size_t> numAstNodes          = 0;
    std::atomic<size_t> numVisitedAstNodes   = 0;
    std::atomic<size_t> numConstants         = 0;
    std::atomic<size_t> numTypes             = 0;
    std::atomic<size_t> numIdentifiers       = 0;
    std::atomic<size_t> numSymbols           = 0;
    std::atomic<size_t> numMicroInstrNoOptim = 0;
    std::atomic<size_t> numMicroInstrFinal   = 0;
    std::atomic<size_t> numCodeGenFunctions  = 0;
#endif // SWC_HAS_STATS

    static Stats& get()
    {
        static Stats stats;
        return stats;
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
