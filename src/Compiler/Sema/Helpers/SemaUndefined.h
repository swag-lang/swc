#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;

namespace SemaUndefined
{
    // Definite-assignment analysis for '= undefined' locals, run once on the fully
    // resolved body of a completed function. Proves that every read, every drop point
    // (reassignment, scope exit, break/return) and every error-unwind point sees an
    // initialized value, and marks each first initializing assignment so codegen
    // compiles it as an initialization (no destination drop).
    Result checkFunction(Sema& sema, AstNodeRef bodyRef);
}

SWC_END_NAMESPACE();
