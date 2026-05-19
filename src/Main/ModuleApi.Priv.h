#pragma once

SWC_BEGIN_NAMESPACE();

class Ast;
class SourceFile;
struct AstNode;

namespace ModuleApi
{
    bool       tryFindNodeRef(const Ast& ast, const AstNode* targetNode, AstNodeRef& outNodeRef);
    AstNodeRef findExportDeclRoot(const SourceFile& file, AstNodeRef declRef);
    bool       hasExplicitPublicAccessModifier(const SourceFile& file, AstNodeRef declRef);
    bool       isExportedPublicDeclScope(const SourceFile& file, AstNodeRef declRef, const Symbol& symbol);
    bool       extractPublicNamespacePath(const Symbol& symbol, std::vector<IdentifierRef>& outNamespacePath);
}

SWC_END_NAMESPACE();
