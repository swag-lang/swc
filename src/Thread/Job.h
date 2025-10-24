#pragma once
#include "Main/Context.h"
#include <functional>

SWC_BEGIN_NAMESPACE();

class Job;
using JobRef = std::shared_ptr<Job>;
class CompilerContext;

enum class JobPriority : std::uint8_t
{
    High   = 0,
    Normal = 1,
    Low    = 2
};

// What the manager should do after process().
enum class JobResult : std::uint8_t
{
    Done,         // finished; remove and wake dependents
    Sleep,        // pause until woken via JobManager::wake(job)
    SleepOn,      // sleep until dep_ completes (set via setDependency / sleepOn)
    SpawnAndSleep // enqueue child_ (at childPriority_) and sleep until it completes
};

// Internal scheduler state for a job (kept small, cache-friendly).
struct JobRecord
{
    // Keep the job alive while scheduled (the user may drop their last ref).
    JobRef job;

    JobPriority priority{JobPriority::Normal};
    JobClientId clientId = 0;

    enum class State : std::uint8_t
    {
        Ready,
        Running,
        Waiting,
        Done
    };
    State state{State::Ready};

    // "Wake ticket" to prevent lost-wake races.
    // If a wake() occurs while the job is running, a following Sleep will NOT park it.
    std::atomic<std::uint64_t> wakeGen{0};

    // Jobs currently waiting for this job to complete (stored as Job*).
    // We look up their Record via job->rec_ under the manager lock.
    std::vector<Job*> dependents;
};

class Job : public std::enable_shared_from_this<Job>
{
    friend class JobManager;

public:
    explicit Job(const CompilerContext& cmpContext) :
        ctx_(cmpContext)
    {
    }

    // Wake all jobs currently waiting on this job (even before finishing).
    void wakeDependents() const;

    std::function<JobResult(Context&)> func_;

protected:
    Context ctx_;

    // For Result::SleepOn
    void setDependency(const JobRef& dep)
    {
        dep_ = dep;
    }

    // For Result::SpawnAndSleep
    void setChildAndPriority(const JobRef& child, JobPriority priority)
    {
        child_         = child;
        childPriority_ = priority;
    }

    // Convenience shorthands
    JobResult sleep()
    {
        clearIntents();
        return JobResult::Sleep;
    }

    JobResult sleepOn(const JobRef& dep)
    {
        dep_ = dep;
        return JobResult::SleepOn;
    }

    JobResult spawnAndSleep(const JobRef& child, JobPriority prio)
    {
        child_         = child;
        childPriority_ = prio;
        return JobResult::SpawnAndSleep;
    }

private:
    // Back-pointers / scheduler hooks (manager-owned but stored on the job)
    JobManager* owner_{nullptr}; // which manager, if any, owns this job right now
    JobRecord*  rec_{nullptr};   // scheduler state for THIS manager run (from the pool)

    // User intent (read by manager under lock after process()):
    JobRef      dep_;   // dependency for SleepOn
    JobRef      child_; // child for SpawnAndSleep
    JobPriority childPriority_{JobPriority::Normal};

    // Cleared by manager after consuming intent.
    void clearIntents()
    {
        dep_.reset();
        child_.reset();
        childPriority_ = JobPriority::Normal;
    }
};

SWC_END_NAMESPACE();
