#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Static "sanity" analysis pass over the pre-RA Micro IR.
//
// A thin driver: it self-gates on the build configuration safety mask
// (the `#[Swag.Sanity]` mask, which a module or function can turn off), then runs
// every `SanitizerCheck` that mask still enables (Backend/Sanitizer). The registered
// set lives in this pass's `run`, so it is named in one place only. The analysis is
// read-only; on a finding this pass returns `Result::Error` to abort codegen so the
// faulty function is never run.
//
// Runs once, before the pre-RA optimization loop, on the unoptimized virtual-register
// IR: dead dereferences have not been eliminated, field offsets are not folded into
// bogus small constants, and control flow / guards keep their source shape — all of
// which the analysis relies on.
class MicroSanityPass final : public MicroPass
{
public:
    std::string_view name() const override { return "sanity"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
