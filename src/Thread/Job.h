#pragma once
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE()
class JobManager;

class Job;
using JobRef = std::shared_ptr<Job>;
class CompilerContext;

enum class JobPriority : std::uint8_t
{
    High   = 0,
    Normal = 1,
    Low    = 2
};

enum class JobResult : std::uint8_t
{
    Done,         // finished; remove and wake dependents
    Sleep,        // pause until woken via JobManager::wake(job)
    SleepOn,      // sleep until dep_ completes (set via setDependency / sleepOn)
    SpawnAndSleep // enqueue child_ (at childPriority_) and sleep until it completes
};

struct JobRecord
{
    // Keep the job alive while scheduled (the user may drop their last ref).
    JobRef job;

    JobPriority priority{JobPriority::Normal};
    JobClientId clientId{0};

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
    TaskContext ctx_;

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

    // Back-pointers / scheduler hooks (manager-owned but stored on the job)
    JobManager* owner_ = nullptr; // which manager, if any, owns this job right now
    JobRecord*  rec_   = nullptr; // scheduler state for THIS manager run (from the pool)

    // User intent (read by manager under lock after process()):
    JobRef      dep_;   // dependency for SleepOn
    JobRef      child_; // child for SpawnAndSleep
    JobPriority childPriority_ = JobPriority::Normal;

public:
    explicit Job(const TaskContext& ctx) :
        ctx_(ctx)
    {
    }

    TaskContext&       ctx() { return ctx_; }
    const TaskContext& ctx() const { return ctx_; }
    JobManager*        owner() const { return owner_; }
    void               setOwner(JobManager* owner) { owner_ = owner; }
    JobRecord*         rec() const { return rec_; }
    void               setRec(JobRecord* rec) { rec_ = rec; }
    JobPriority        priority() const { return rec_->priority; }
    JobPriority        childPriority() const { return childPriority_; }
    JobClientId        clientId() const { return rec_->clientId; }
    JobRef             child() const { return child_; }
    JobRef             dep() const { return dep_; }

    void wakeDependents() const;
    void clearIntents();

    std::function<JobResult()> func;
};

SWC_END_NAMESPACE()
