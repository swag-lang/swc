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
// and OFF for release/fast-compile.
//
// Runs once, before the pre-RA optimization loop, on the unoptimized virtual-register
// IR: dead dereferences have not been eliminated, field offsets are not folded into
// bogus small constants, and control flow / guards keep their source shape — all of
// which the analysis relies on. Locals live in stack slots (addressed against
// `debugStackBaseVirtualReg`).
class MicroSanityPass final : public MicroPass
{
public:
    std::string_view name() const override { return "sanity"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
