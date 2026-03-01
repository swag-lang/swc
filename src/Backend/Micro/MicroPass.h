#pragma once
#include "Backend/Micro/MicroPrinter.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

class MicroPass
{
public:
    virtual ~MicroPass()                   = default;
    virtual std::string_view  name() const = 0;
    virtual MicroRegPrintMode printModeBefore() const { return MicroRegPrintMode::Concrete; }
    virtual MicroRegPrintMode printModeAfter() const { return MicroRegPrintMode::Concrete; }
    virtual Result            run(MicroPassContext& context) = 0;
};

SWC_END_NAMESPACE();
