#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

namespace SemaInitFlow
{
    // True when the function needs the flow analysis: it has a local whose safe
    // default may be elided, a local that requires definite initialization, an
    // 'opSet' candidate for complete-initialization inference, or 'nullable'
    // parameters whose contract must be honored by the body.
    bool wantsCheck(Sema& sema, const SymbolFunction& sym);

    // Flow analysis for initialization, run once on the fully resolved body of a
    // completed function. It leaves safe initialization intact unless every read,
    // drop point (reassignment, scope exit, break/return), error-unwind point and
    // escape proves it dead, then marks each first assignment for codegen. For a
    // type without a safe default, the same flow facts instead reject every
    // observation that is not definitely initialized.
    //
    // Also validates the 'nullable' parameter contract: a parameter whose FIRST use on
    // every path to an exit is an address-requiring operation (dereference, member
    // access, indexing, call) can never survive a null argument.
    //
    // When 'checkReturnContract' is set (plain functions only: interface impls have
    // an imposed signature, and a fallible function synthesizes a zero — hence null
    // — result on its 'catch' error path), a 'nullable' return type that no return
    // path can produce is reported as a dead contract too.
    Result checkFunction(Sema& sema, const SymbolFunction& sym, AstNodeRef bodyRef, bool checkReturnContract = false);
}

SWC_END_NAMESPACE();
