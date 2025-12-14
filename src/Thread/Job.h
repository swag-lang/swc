#pragma once
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE()

class JobManager;
class Job;
class CompilerContext;

using JobClientId = uint32_t;

enum class JobKind
{
    Invalid,
    Parser,
    Sema,
};

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
    JobKind     kind_  = JobKind::Invalid;
    JobManager* owner_ = nullptr; // which manager, if any, owns this job right now
    JobRecord*  rec_   = nullptr; // scheduler state for THIS manager run (from the pool)

public:
    explicit Job(const TaskContext& ctx, JobKind kind) :
        ctx_(ctx),
        kind_(kind)
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

    std::function<JobResult()> func;

    template<typename T>
    const T* safeCast() const
    {
        return kind_ == T::K ? static_cast<const T*>(this) : nullptr;
    }
    
    template<typename T>
    T* safeCast()
    {
        return kind_ == T::K ? static_cast<T*>(this) : nullptr;
    }    
};

SWC_END_NAMESPACE()
