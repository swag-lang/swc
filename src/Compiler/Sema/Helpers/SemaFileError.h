#pragma once
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

namespace SemaFileError
{
    inline Result reportCompilerFileError(Sema& sema, DiagnosticId id, AstNodeRef nodeRef, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = SemaError::build(sema, id, nodeRef);
        FileSystem::setDiagnosticPathAndBecause(diag, &sema.ctx(), path, because);
        diag.report(sema.ctx());
        return Result::Error;
    }
}

SWC_END_NAMESPACE();
