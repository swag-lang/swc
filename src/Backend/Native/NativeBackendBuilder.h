#pragma once

#include "Backend/Native/NativeBackendTypes.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder
{
public:
    NativeBackendBuilder(CompilerInstance& compiler, bool runArtifact);

    Result run();
    bool   writeObject(uint32_t objIndex);

    TaskContext&              ctx();
    const TaskContext&        ctx() const;
    CompilerInstance&         compiler();
    const CompilerInstance&   compiler() const;
    NativeBackendState&       state();
    const NativeBackendState& state() const;

    bool reportError(std::string_view because) const;

private:
    bool validateHost() const;
    bool writeObjects();
    bool runGeneratedArtifact() const;

    TaskContext        ctx_;
    CompilerInstance&  compiler_;
    bool               runArtifact_ = false;
    NativeBackendState state_;
};

SWC_END_NAMESPACE();
