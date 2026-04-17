#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct CompilerTag
{
    Utf8       name;
    Utf8       source;
    ConstantRef cstRef = ConstantRef::invalid();
};

class CompilerTagRegistry
{
public:
    Result setup(TaskContext& ctx);

    const CompilerTag*              find(std::string_view name) const;
    const std::vector<CompilerTag>& all() const { return tags_; }

private:
    std::vector<CompilerTag> tags_;
};

SWC_END_NAMESPACE();
