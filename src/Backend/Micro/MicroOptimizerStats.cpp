#include "pch.h"
#include "Backend/Micro/MicroOptimizerStats.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

MicroOptimizerPassStats& MicroOptimizerFunctionStats::pass(const std::string_view name)
{
    for (auto& entry : passes)
    {
        if (entry.name == name)
            return entry;
    }
    return passes.emplace_back(MicroOptimizerPassStats{.name = std::string{name}});
}

void MicroOptimizerFunctionStats::observeBudget(const std::string_view name, const uint64_t work, const uint64_t limit, const bool stopped)
{
    auto it = std::ranges::find(budgets, name, &MicroOptimizerBudgetStats::name);
    if (it == budgets.end())
        it = budgets.emplace(budgets.end(), MicroOptimizerBudgetStats{.name = std::string{name}});
    ++it->observations;
    it->stopped += stopped ? 1 : 0;
    it->peakWork = std::max(it->peakWork, work);
    it->minLimit = std::min(it->minLimit, limit);
    it->maxLimit = std::max(it->maxLimit, limit);
}

void MicroOptimizerStats::merge(const MicroOptimizerFunctionStats& function)
{
    const std::lock_guard lock(mutex_);
    ++functions_;
    for (const auto& source : function.passes)
    {
        auto& target = totals_.pass(source.name);
        target.calls += source.calls;
        target.changed += source.changed;
        target.errors += source.errors;
        target.elapsedNs += source.elapsedNs;
        target.inputInstructions += source.inputInstructions;
        target.outputInstructions += source.outputInstructions;
        target.cfgBuilds += source.cfgBuilds;
        target.ssaQueries += source.ssaQueries;
        target.ssaBuilds += source.ssaBuilds;
        target.treeCalls += source.treeCalls;
        target.treeMemoHits += source.treeMemoHits;
        target.seeds += source.seeds;
        target.failedSeeds += source.failedSeeds;
        target.intervalAttempts += source.intervalAttempts;
        target.intervalFallbacks += source.intervalFallbacks;
    }
    for (const auto& source : function.budgets)
    {
        auto it = std::ranges::find(totals_.budgets, source.name, &MicroOptimizerBudgetStats::name);
        if (it == totals_.budgets.end())
        {
            totals_.budgets.push_back(source);
            continue;
        }
        it->observations += source.observations;
        it->stopped += source.stopped;
        it->peakWork = std::max(it->peakWork, source.peakWork);
        it->minLimit = std::min(it->minLimit, source.minLimit);
        it->maxLimit = std::max(it->maxLimit, source.maxLimit);
    }
}

MicroOptimizerFunctionStats MicroOptimizerStats::snapshot() const
{
    const std::lock_guard lock(mutex_);
    return totals_;
}

uint64_t MicroOptimizerStats::functions() const
{
    const std::lock_guard lock(mutex_);
    return functions_;
}

void MicroOptimizerStats::print(const TaskContext& ctx) const
{
    MicroOptimizerFunctionStats totals;
    uint64_t                    functionCount;
    {
        const std::lock_guard lock(mutex_);
        totals        = totals_;
        functionCount = functions_;
    }
    std::ranges::sort(totals.passes, {}, &MicroOptimizerPassStats::name);
    std::ranges::sort(totals.budgets, {}, &MicroOptimizerBudgetStats::name);
    std::string text = std::format("\nOptimizer statistics: {} function pipelines\nPass time is cumulative elapsed worker time; instruction counts are summed across calls\n", functionCount);
    text += "pass,calls,changed,errors,time_ms,input_instr,output_instr,cfg_builds,ssa_queries,ssa_builds,tree_calls,tree_memo_hits,seeds,failed_seeds,interval_attempts,interval_fallbacks\n";
    for (const auto& pass : totals.passes)
        text += std::format("{},{},{},{},{:.3f},{},{},{},{},{},{},{},{},{},{},{}\n", pass.name, pass.calls, pass.changed, pass.errors, static_cast<double>(pass.elapsedNs) / 1'000'000, pass.inputInstructions, pass.outputInstructions, pass.cfgBuilds, pass.ssaQueries, pass.ssaBuilds, pass.treeCalls, pass.treeMemoHits, pass.seeds, pass.failedSeeds, pass.intervalAttempts, pass.intervalFallbacks);
    text += "budget,observations,stopped,peak_work,min_limit,max_limit\n";
    for (const auto& budget : totals.budgets)
        text += std::format("{},{},{},{},{},{}\n", budget.name, budget.observations, budget.stopped, budget.peakWork, budget.minLimit, budget.maxLimit);
    Logger::print(ctx, text);
}

SWC_END_NAMESPACE();
