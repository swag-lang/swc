#pragma once

SWC_BEGIN_NAMESPACE();

class TaskContext;

// Profiling is opt-in in both compiler configurations. Workers collect locally;
// only completed function profiles enter the compiler-owned, synchronized totals.
struct MicroOptimizerPassStats
{
    std::string name;
    uint64_t    calls              = 0;
    uint64_t    changed            = 0;
    uint64_t    errors             = 0;
    uint64_t    elapsedNs          = 0;
    uint64_t    inputInstructions  = 0;
    uint64_t    outputInstructions = 0;
    uint64_t    cfgBuilds          = 0;
    uint64_t    ssaQueries         = 0;
    uint64_t    ssaBuilds          = 0;
    uint64_t    treeCalls          = 0;
    uint64_t    treeMemoHits       = 0;
    uint64_t    seeds              = 0;
    uint64_t    failedSeeds        = 0;
    uint64_t    intervalAttempts   = 0;
    uint64_t    intervalFallbacks  = 0;
};

struct MicroOptimizerBudgetStats
{
    std::string name;
    uint64_t    observations = 0;
    uint64_t    stopped      = 0;
    uint64_t    peakWork     = 0;
    uint64_t    minLimit     = UINT64_MAX;
    uint64_t    maxLimit     = 0;
};

struct MicroOptimizerFunctionStats
{
    std::vector<MicroOptimizerPassStats>   passes;
    std::vector<MicroOptimizerBudgetStats> budgets;
    MicroOptimizerPassStats*               activePass = nullptr;

    MicroOptimizerPassStats& pass(std::string_view name);
    // A stop means this check refused work (or a changing sweep exhausted its
    // cap), not merely that a counter equalled a limit before converging.
    void observeBudget(std::string_view name, uint64_t work, uint64_t limit, bool stopped);
};

class MicroOptimizerStats
{
public:
    void merge(const MicroOptimizerFunctionStats& function);
    void print(const TaskContext& ctx) const;

    // Snapshot after merging, for deterministic tests and command reporting.
    MicroOptimizerFunctionStats snapshot() const;
    uint64_t                    functions() const;

private:
    mutable std::mutex          mutex_;
    MicroOptimizerFunctionStats totals_;
    uint64_t                    functions_ = 0;
};

SWC_END_NAMESPACE();
