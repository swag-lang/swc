#pragma once
#include "Support/Core/Result.h"

#include "Backend/Linker/LinkJob.h"
#include "Support/Os/Os.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;

// Base class for the integrated linker. A target-specific subclass lowers the backend output into a
// LinkJob; the shared executeLink()/finishLink() turn that job into the final on-disk artifact.
//
// The three phases mirror the workspace async pipeline:
//   prepareLink  - foreground, reads compiler state, produces a self-contained LinkJob.
//   executeLink  - background-safe, produces the artifact (no compiler state touched).
//   finishLink   - foreground, reports diagnostics and validates the artifact.
class Linker
{
public:
    explicit Linker(NativeBackendBuilder& builder);
    virtual ~Linker() = default;

    static std::unique_ptr<Linker> create(NativeBackendBuilder& builder);

    // Discovers the MSVC/SDK library directories the integrated linker resolves imports against. Also
    // used for dry-run and show-config reporting.
    static Os::WindowsToolchainDiscoveryResult queryToolchainPaths(const NativeBackendBuilder& builder, Os::WindowsToolchainPaths& outToolchain);

    // Synchronous one-shot link on the calling thread.
    Result link();

    virtual Result prepareLink(LinkJob& outJob)                                                                                                             = 0;
    virtual Result tryPrepareIncrementalLink(bool& outPrepared, LinkJob& outJob, std::span<const fs::path> objectPaths, std::span<const Utf8> libraryNames) = 0;

    static void executeLink(LinkJob& job);
    Result      finishLink(const LinkJob& job) const;

protected:
    NativeBackendBuilder* builder_ = nullptr;
};

// Schedule a prepared link on the shared JobManager so it can overlap later
// module compilation. Like executeLink(), it touches only the prepared LinkJob.
class NativeLinkJob final : public Job
{
public:
    static constexpr auto K = JobKind::NativeLink;

    NativeLinkJob(const TaskContext& ctx, LinkJob& job) :
        Job(ctx, JobKind::NativeLink),
        job_(&job)
    {
    }

    JobResult exec() override
    {
        ctx().state().setNone();
        Linker::executeLink(*job_);
        return JobResult::Done;
    }

private:
    LinkJob* job_ = nullptr;
};

SWC_END_NAMESPACE();
