#pragma once
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace SemaSwitch
{
    inline void pushEnumScopeBinding(Sema& sema, const TypeInfo* enumType)
    {
        if (enumType)
        {
            SemaFrame frame = sema.frame();
            frame.pushScopeBindingType(enumType->typeRef());
            sema.pushFramePopOnPostNode(frame);
        }
    }
}

SWC_END_NAMESPACE();
