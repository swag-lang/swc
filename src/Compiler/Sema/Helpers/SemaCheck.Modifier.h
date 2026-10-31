#pragma once
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace SemaCheck
{
    // Call only after confirming a '#wrap' or '#promote' modifier.
    inline Result checkIntegerModifierTarget(Sema& sema, const AstNode& node, const SemaNodeView& targetView)
    {
        if (SemaHelpers::aliasType(sema, targetView).isIntLike())
            return Result::Continue;

        return SemaError::raiseModifierOnlyInteger(sema, node, targetView.typeRef());
    }
}

SWC_END_NAMESPACE();
