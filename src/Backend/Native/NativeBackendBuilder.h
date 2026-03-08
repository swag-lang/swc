#pragma once

#include "Backend/Native/NativeBackendTypes.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder
{
public:
    NativeBackendBuilder(CompilerInstance& compiler, bool runArtifact);

    Result run();
    Result writeObject(uint32_t objIndex);

    TaskContext&              ctx();
    const TaskContext&        ctx() const;
    CompilerInstance&         compiler();
    const CompilerInstance&   compiler() const;
    NativeBackendState&       state();
    const NativeBackendState& state() const;

    Result reportError(DiagnosticId id) const;

    template<typename T1>
    Result reportError(DiagnosticId id, std::string_view name1, T1&& value1) const
    {
        Diagnostic diag = Diagnostic::get(id);
        diag.addArgument(name1, std::forward<T1>(value1));
        return reportError(std::move(diag));
    }

    template<typename T1, typename T2>
    Result reportError(DiagnosticId id, std::string_view name1, T1&& value1, std::string_view name2, T2&& value2) const
    {
        Diagnostic diag = Diagnostic::get(id);
        diag.addArgument(name1, std::forward<T1>(value1));
        diag.addArgument(name2, std::forward<T2>(value2));
        return reportError(std::move(diag));
    }

private:
    Result reportError(Diagnostic diag) const;
    Result validateHost() const;
    Result writeObjects();
    Result runGeneratedArtifact() const;

    TaskContext        ctx_;
    CompilerInstance&  compiler_;
    bool               runArtifact_ = false;
    NativeBackendState state_;
};

SWC_END_NAMESPACE();
