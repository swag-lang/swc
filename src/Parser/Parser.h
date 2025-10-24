#pragma once

SWC_BEGIN_NAMESPACE()

class SourceFile;

class EvalContext;

class Parser
{
    SourceFile* file_ = nullptr;

public:
    Result parse(EvalContext& ctx);
};

SWC_END_NAMESPACE();
