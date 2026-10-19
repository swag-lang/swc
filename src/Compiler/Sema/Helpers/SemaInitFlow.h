#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

namespace SemaInitFlow
{
    // Needed for default elision, definite initialization, inferring complete
    // opSet initialization, or nullable parameter contracts.
    bool wantsCheck(Sema& sema, const SymbolFunction& sym);

    // Run once on a completed function's resolved body. Elide safe defaults
    // only when reads, drops, unwinds, and escapes prove them dead, then mark
    // first assignments for codegen. Without a safe default, reject every
    // observation lacking definite initialization.
    //
    // Validate nullable parameters: a first use requiring an address on every
    // path to an exit means a null argument cannot survive.
    //
    // checkReturnContract reports nullable returns that no path can produce.
    // Plain functions only: interface impls have imposed signatures, and fallible
    // catch paths synthesize zero/null results.
    Result checkFunction(Sema& sema, const SymbolFunction& sym, AstNodeRef bodyRef, bool checkReturnContract = false);
}

SWC_END_NAMESPACE();
