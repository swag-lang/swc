#pragma once
SWC_BEGIN_NAMESPACE()

class Compiler;
class SourceFile;
class EvalContext;

struct SourceCodeLocation
{
    const SourceFile* file   = nullptr;
    uint32_t          offset = 0;
    uint32_t          len    = 0;
    uint32_t          line   = 0;
    uint32_t          column = 0;

    void fromOffset(const EvalContext& ctx, const SourceFile* inFile, uint32_t inOffset, uint32_t inLen = 1);
};

SWC_END_NAMESPACE()
