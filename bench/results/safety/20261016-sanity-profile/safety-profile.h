#pragma once
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace SafetyProfile
{
    struct Counts
    {
        uint64_t passCycles = 0;
        uint64_t functions = 0, setup = 0, propagation = 0, checking = 0, observer = 0;
        uint64_t steps = 0, checkSteps = 0, checkCalls = 0, states = 0, capped = 0;
        uint64_t maxConvergedPayload = 0;
    };
    inline Counts totals;
    inline std::mutex mutex;
    inline thread_local Counts* active = nullptr;
    inline uint64_t cycles()
    {
        ULONG64 result = 0;
        QueryThreadCycleTime(GetCurrentThread(), &result);
        return result;
    }
    struct Scope
    {
        Counts local;
        Counts* previous = active;
        uint64_t mark = cycles();
        uint32_t phase = 0;
        Scope() { active = &local; }
        void close()
        {
            const uint64_t now = cycles();
            const uint64_t elapsed = now - mark;
            if (phase == 0) local.setup += elapsed;
            if (phase == 1) local.propagation += elapsed;
            if (phase == 2) local.checking += elapsed;
            if (phase == 3) local.observer += elapsed;
            mark = now;
        }
        void begin(uint32_t next) { close(); phase = next; }
        ~Scope()
        {
            close();
            active = previous;
            std::lock_guard lock(mutex);
            ++totals.functions;
            totals.setup += local.setup; totals.propagation += local.propagation;
            totals.checking += local.checking; totals.observer += local.observer;
            totals.steps += local.steps; totals.checkSteps += local.checkSteps;
            totals.checkCalls += local.checkCalls; totals.states += local.states;
            totals.capped += local.capped;
            totals.maxConvergedPayload = std::max(totals.maxConvergedPayload, local.maxConvergedPayload);
        }
    };
    struct PassScope
    {
        uint64_t mark = cycles();
        ~PassScope()
        {
            const uint64_t elapsed = cycles() - mark;
            std::lock_guard lock(mutex);
            totals.passCycles += elapsed;
        }
    };
    struct Reporter
    {
        ~Reporter()
        {
            ULONG64 process = 0;
            QueryProcessCycleTime(GetCurrentProcess(), &process);
            std::fprintf(stderr, "safety-profile: pass_cycles=%llu functions=%llu setup=%llu propagation=%llu checking=%llu observer=%llu process=%llu steps=%llu check_steps=%llu check_calls=%llu states=%llu capped=%llu max_converged_payload=%llu\n",
                totals.passCycles, totals.functions, totals.setup, totals.propagation, totals.checking, totals.observer,
                process, totals.steps, totals.checkSteps, totals.checkCalls, totals.states, totals.capped,
                totals.maxConvergedPayload);
        }
    };
}
