#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Static "sanity" analysis over the pre-RA Micro IR.
//
// A path-sensitive abstract interpreter (ported from the old swag bytecode sanity
// pass) that simulates execution per function to catch provable null-pointer
// dereferences before they can fault at runtime.
//
// It is a read-only analysis: it never mutates the IR. It self-gates on the build
// configuration safety mask (`SafetyWhat::Null`), so it is ON for debug/fast-debug
// and OFF for release/fast-compile, and can be toggled per scope with
// `#[Swag.Safety(SafetyWhat.Null, ...)]`.
//
// Runs as a start pass: in debug builds (optimize=false) local variables still live
// in stack slots (mem2reg has not run), which is exactly the model this interpreter
// needs to track null values flowing through locals.
class MicroSanityPass final : public MicroPass
{
public:
    std::string_view name() const override { return "sanity"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
