#pragma once

SWC_BEGIN_NAMESPACE()

class EvalContext;

class Parser
{
public:
    Result parse(EvalContext& ctx);
};

SWC_END_NAMESPACE();
