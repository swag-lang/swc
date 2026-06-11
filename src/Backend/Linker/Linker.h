#pragma once

#include "Backend/Linker/LinkJob.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

// Base class for the integrated linker. A target-specific subclass lowers the backend output into a
// LinkJob (a target-independent LinkImage plus output settings); the shared executeLink() and
// finishLink() turn that into the final on-disk artifact. There is no external linker process.
//
// The three phases mirror the workspace async pipeline:
//   prepareLink  - foreground, reads compiler state, produces a self-contained LinkJob.
//   executeLink  - background-safe, serialises the image and writes the artifact (no compiler state).
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

    virtual Result prepareLink(LinkJob& outJob) = 0;
    static void    executeLink(LinkJob& job);
    Result         finishLink(const LinkJob& job) const;

protected:
    NativeBackendBuilder* builder_ = nullptr;
};

// Runs executeLink() as a normal job on the shared JobManager, so a module's link overlaps the next
// module's compilation instead of riding a one-off std::async thread. Self-contained: it only touches
// the LinkJob, never compiler state, so it is safe on any worker thread (mirrors executeLink's contract).
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
