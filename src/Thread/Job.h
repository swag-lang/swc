#pragma once
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE()

class JobManager;
class Job;
class CompilerContext;

using JobClientId = uint32_t;

enum class JobPriority : std::uint8_t
{
    High   = 0,
    Normal = 1,
    Low    = 2
};

enum class JobResult : std::uint8_t
{
    Done,
    Sleep
};

struct JobRecord
{
    Job*        job      = nullptr;
    JobPriority priority = JobPriority::Normal;
    JobClientId clientId = 0;

    enum class State : uint8_t
    {
        Ready,   // queued to run
        Running, // currently executing
        Waiting, // sleeping / not runnable
        Done     // completed
    };

    State state{State::Ready};
};

class Job
{
    TaskContext ctx_;

    // Back-pointers / scheduler hooks (manager-owned but stored on the job)
    JobManager* owner_ = nullptr; // which manager, if any, owns this job right now
    JobRecord*  rec_   = nullptr; // scheduler state for THIS manager run (from the pool)

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
    JobPriority        priority() const { return rec_ ? rec_->priority : JobPriority::Normal; }
    JobClientId        clientId() const { return rec_ ? rec_->clientId : 0; }

    // Convenience shorthand for sleeping
    JobResult sleep() { return JobResult::Sleep; }

    std::function<JobResult()> func;
};

SWC_END_NAMESPACE()
