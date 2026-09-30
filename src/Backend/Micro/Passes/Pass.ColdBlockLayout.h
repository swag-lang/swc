#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Final layout of the blocks that report a fault.
//
// A runtime guard lowers to a test, a jump over its report, and the report:
// the two arguments of the panic, the registers parked around the call, the
// call, and their reloads. Left where lowering put it, that report sits in the
// middle of the path every execution takes, so each guard costs the hot path a
// taken jump and a dozen instructions of distance. A checked three-add loop
// body of 12 instructions spans 69.
//
// This moves every such block behind the function's last instruction. The hot
// path keeps the test and a jump that is not taken; the report returns through
// a jump of its own, because a panic can come back when a hook handles it.
// Nothing about the guard changes, only where its cold half lives.
//
// It runs last before emission: the prologue and epilogue rewrites read the
// function as one entry, one body and its returns, and must not find code
// behind the final return.
class MicroColdBlockLayoutPass final : public MicroPass
{
public:
    std::string_view name() const override { return "cold-block-layout"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
