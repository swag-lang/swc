#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

namespace SemaUndefined
{
    // True when the function needs the flow analysis: it declares '= undefined'
    // locals (or struct locals with undefined field defaults), or takes '#null'
    // parameters whose contract must be honored by the body.
    bool wantsCheck(Sema& sema, const SymbolFunction& sym);

    // Definite-assignment analysis for '= undefined' locals, run once on the fully
    // resolved body of a completed function. Proves that every read, every drop point
    // (reassignment, scope exit, break/return) and every error-unwind point sees an
    // initialized value, and marks each first initializing assignment so codegen
    // compiles it as an initialization (no destination drop).
    //
    // Also validates the '#null' parameter contract: a parameter whose FIRST use on
    // every path to an exit is an address-requiring operation (dereference, member
    // access, indexing, call) can never survive a null argument.
    Result checkFunction(Sema& sema, const SymbolFunction& sym, AstNodeRef bodyRef);
}

SWC_END_NAMESPACE();
