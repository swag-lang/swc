#pragma once
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace SemaSwitch
{
    inline void pushEnumScopeBinding(Sema& sema, TypeRef enumTypeRef)
    {
        if (enumTypeRef.isValid())
        {
            SemaFrame frame = sema.frame();
            frame.pushScopeBindingType(enumTypeRef);
            sema.pushFramePopOnPostNode(frame);
        }
    }
}

SWC_END_NAMESPACE();
