#pragma once

SWC_BEGIN_NAMESPACE()

struct ConstantValue
{
    TypeInfoRef typeRef;

    union
    {
        bool b;
    };
};

SWC_END_NAMESPACE()
