#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA dominance-scoped common-subexpression elimination on virtual registers.
// A pure compute whose opcode, operand shape, and SSA input values match an
// earlier instruction that dominates it — and whose result value still lives in
// the earlier destination register at that point — is rewritten into a plain
// register copy, which copy elimination then folds away. This deduplicates the
// multiply-high expansions strength reduction emits for division and modulo by
// the same constant (`u / C` and `u % C` share one mulhi chain), and any repeated
// address or extension computation the front end produces. A load is numbered
// the same way, scoped to the straight line it sits in: it folds onto an earlier
// load of the same address only when no label, store, call or terminator lies
// between them.
class MicroValueNumberingPass final : public MicroPass
{
public:
    std::string_view name() const override { return "value-numbering"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
