#pragma once
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.h"

SWC_BEGIN_NAMESPACE();

class Ast;
struct AstNode;

namespace ModuleApi
{
    bool       tryFindReachableNodeRef(const Ast& ast, const AstNode* targetNode, AstNodeRef& outNodeRef);
    bool       isGeneratedSourceDecl(const SourceFile& file, AstNodeRef declRef);
    AstNodeRef findExportDeclRoot(const SourceFile& file, AstNodeRef declRef);
    bool       isModuleApiOpaqueType(const Symbol& symbol);

    const SourceView& moduleApiNodeSourceView(TaskContext& ctx, const Ast& ast, AstNodeRef nodeRef);
    TokenRef          moduleApiSnippetStartTokRef(const Ast& ast, const AstNode& node);
    uint32_t          sourceTokenByteStart(const SourceView& srcView, const Token& token);
    uint32_t          sourceTokenByteEnd(const SourceView& srcView, const Token& token);
    bool              tryGetModuleApiSnippetOffsets(TaskContext& ctx, const SourceFile& file, AstNodeRef nodeRef, uint32_t& outStartOffset, uint32_t& outEndOffset);
    bool              tryGetModuleApiSnippetStartOffset(TaskContext& ctx, const SourceFile& file, AstNodeRef nodeRef, uint32_t& outStartOffset);
    bool              tryGetModuleApiSnippet(TaskContext& ctx, const SourceFile& file, AstNodeRef nodeRef, std::string_view& outSnippet);
    Utf8              buildSanitizedModuleApiSnippet(TaskContext& ctx, const SourceFile& file, AstNodeRef nodeRef, uint32_t startOffset, std::string_view snippetText, std::string_view eol);
}

SWC_END_NAMESPACE();
