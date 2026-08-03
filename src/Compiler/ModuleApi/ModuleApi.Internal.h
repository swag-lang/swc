#pragma once
#include "Compiler/ModuleApi/ModuleApi.Source.h"

SWC_BEGIN_NAMESPACE();

namespace ModuleApi
{
    bool       isDeclarationWrapper(const AstNode& node);
    AstNodeRef findEnclosingImplRef(const SourceFile& file, AstNodeRef declRef);
    bool       hasExplicitPublicAccessModifier(const SourceFile& file, AstNodeRef declRef);
    bool       isExportedPublicDeclScope(const SourceFile& file, AstNodeRef declRef, const Symbol& symbol);
    bool       extractPublicNamespacePath(TaskContext& ctx, const SourceFile& file, AstNodeRef declRef, const Symbol& symbol, std::vector<IdentifierRef>& outNamespacePath);
    Result     resolvePendingEntries(TaskContext& ctx, ModuleApiFileEntries& entries, bool diagnosticsOnly);
}

SWC_END_NAMESPACE();
