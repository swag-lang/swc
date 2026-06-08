#pragma once
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

class JobManager;
class Job;
class CompilerContext;

using JobClientId = uint32_t;

enum class JobKind
{
    Invalid,
    Format,
    Parser,
    Sema,
    CodeGen,
    JitPatch,
    CompilerMessage,
    NativeArtifact,
    NativeObj,
    ModuleApiExport,
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

// Identifies the exact dependency a sleeping job is waiting on, so that the producer
// satisfying that dependency can wake only the relevant jobs (instead of waking all).
// A null target means "not keyable" (wildcard sleeper, woken only by the barrier wakeAll).
struct WaitKey
{
    const void*   target = nullptr;
    TaskStateKind kind   = TaskStateKind::None;

    bool operator==(const WaitKey&) const = default;
    bool valid() const { return target != nullptr; }
};

struct WaitKeyHash
{
    std::size_t operator()(const WaitKey& k) const noexcept
    {
        const std::size_t h1 = std::hash<const void*>{}(k.target);
        const std::size_t h2 = static_cast<std::size_t>(k.kind);
        return h1 ^ (h2 * 0x9E3779B97F4A7C15ull);
    }
};

struct JobRecord
{
    Job*        job      = nullptr;
    uint32_t    index    = 0;
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

    // Dependency registration while Waiting (only set when registered in the wait registry).
    WaitKey waitKey{};
    bool    registered = false;
};

class Job
{
public:
    explicit Job(const TaskContext& ctx, JobKind kind) :
        ctx_(ctx),
        kind_(kind)
    {
    }

    virtual ~Job() = default;

    virtual JobResult  exec() = 0;
    TaskContext&       ctx() { return ctx_; }
    const TaskContext& ctx() const { return ctx_; }
    JobManager*        owner() const { return owner_; }
    JobKind            kind() const { return kind_; }
    void               setOwner(JobManager* owner) { owner_ = owner; }
    JobRecord*         rec() const { return rec_; }
    void               setRec(JobRecord* rec) { rec_ = rec; }
    JobPriority        priority() const { return rec_ ? rec_->priority : JobPriority::Normal; }
    JobClientId        clientId() const { return rec_ ? rec_->clientId : 0; }
    static JobResult   toJobResult(const TaskContext& ctx, Result result);
    static const char* kindName(JobKind kind);

    template<typename T>
    const T* cast() const
    {
        SWC_ASSERT(kind_ == T::K);
        return static_cast<const T*>(this);
    }

    template<typename T>
    T* cast()
    {
        SWC_ASSERT(kind_ == T::K);
        return static_cast<T*>(this);
    }

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

private:
    TaskContext ctx_;
    JobKind     kind_  = JobKind::Invalid;
    JobManager* owner_ = nullptr; // which manager, if any, owns this job right now
    JobRecord*  rec_   = nullptr; // scheduler state for THIS manager run (from the pool)
};

SWC_END_NAMESPACE();
