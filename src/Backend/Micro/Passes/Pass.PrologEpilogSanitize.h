#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroPrologEpilogSanitizePass final : public MicroPass
{
public:
    std::string_view name() const override { return "prolog-epilog-sanitize"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
