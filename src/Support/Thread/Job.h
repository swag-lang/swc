#pragma once
#include "Main/TaskContext.h"
#include "Support/Core/Result.h"
#include "Support/Report/Assert.h"

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
    JitExec,
    CompilerMessage,
    NativeArtifact,
    NativeObj,
    NativeLinkPrepare,
    NativeLink,
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
    Error,
    Sleep
};

// Identifies the exact dependency a sleeping job is waiting on, so that the producer
// satisfying that dependency can wake only the relevant jobs (instead of waking all).
// A null target means "not keyable": the producer uses its completion alias or the barrier wakeAll.
struct WaitKey
{
    const void*   target = nullptr;
    TaskStateKind kind   = TaskStateKind::None;

    bool operator==(const WaitKey&) const = default;
    bool valid() const { return target != nullptr; }

    // A job that waits for something to happen to a name (a symbol spelled that way, the impl
    // blocks registering on it) waits on the name itself. The target is the identifier index
    // offset by one, a value no object address takes. Identifier indices are per compiler, so a
    // shared pool can see a spurious wake from another module; the job then checks and parks again.
    static WaitKey name(IdentifierRef idRef, TaskStateKind kind) { return {reinterpret_cast<const void*>(static_cast<uintptr_t>(idRef.get()) + 1), kind}; }
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

    // Intrusive wait indexes, mutated only under the owning manager's mutex.
    JobRecord* clientWaitPrevious = nullptr;
    JobRecord* clientWaitNext     = nullptr;
    JobRecord* keyWaitPrevious    = nullptr;
    JobRecord* keyWaitNext        = nullptr;
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
