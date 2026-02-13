#include "pch.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef)
{
    ast.appendNodes(out, spanRef);
}

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes)
{
    for (auto n : nodes)
    {
        if (n.isValid())
            out.push_back(n);
    }
}

void AstNode::collectChildrenFromAst(SmallVector<AstNodeRef>& out, const Ast& ast) const
{
    Ast::nodeIdInfos(id_).collectChildren(out, ast, *this);
}

SourceCodeRange AstNode::codeRange(const TaskContext& ctx) const
{
    const SourceView& view  = srcView(ctx);
    const Token&      token = view.token(codeRef_.tokRef);
    return token.codeRange(ctx, view);
}

SourceCodeRange AstNode::codeRangeWithChildren(const TaskContext& ctx, const Ast& ast) const
{
    SourceCodeRange codeRange{};

    // Always use the SourceView of the node itself
    const auto baseViewRef = codeRef_.srcViewRef;
    auto&      view        = ctx.compiler().srcView(baseViewRef);
    if (codeRef_.tokRef.isInvalid() || view.tokens().empty())
        return codeRange;

    // Baseline comes from this node token
    const auto& baseTok  = view.token(codeRef_.tokRef);
    const auto  baseLoc  = baseTok.codeRange(ctx, view);
    const auto  baseLine = baseLoc.line;

    // Descend left-most while staying on the same line and same SourceView
    auto            leftMost = this;
    SourceCodeRange startLoc = baseLoc;
    while (true)
    {
        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(leftMost->id()).collectChildren(children, ast, *leftMost);
        if (children.empty() || children.front().isInvalid())
            break;
        const AstNode& child = ast.node(children.front());
        if (child.srcViewRef() != baseViewRef)
            break;
        const auto& childTok = view.token(child.tokRef());
        const auto  childLoc = childTok.codeRange(ctx, view);
        if (childLoc.line != baseLine)
            break;
        leftMost = &child;
        if (childLoc.offset < startLoc.offset)
            startLoc = childLoc;
    }

    // Descend right-most while staying on the same line and same SourceView
    auto            rightMost = this;
    SourceCodeRange endLoc    = baseTok.codeRange(ctx, view);
    while (true)
    {
        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(rightMost->id()).collectChildren(children, ast, *rightMost);
        if (children.empty() || children.back().isInvalid())
            break;
        const AstNode& child = ast.node(children.back());
        if (child.srcViewRef() != baseViewRef)
            break;
        const auto& childTok = view.token(child.tokRef());
        const auto  childLoc = childTok.codeRange(ctx, view);
        if (childLoc.line != baseLine)
            break;
        rightMost = &child;
        if (childLoc.offset > endLoc.offset)
            endLoc = childLoc;
    }

    // Compute span and fill location
    const uint32_t startOff = startLoc.offset;
    const uint32_t endByte  = endLoc.offset + endLoc.len;
    const uint32_t spanLen  = endByte > startOff ? (endByte - startOff) : 1u;
    codeRange.fromOffset(ctx, view, startOff, spanLen);
    return codeRange;
}

const SourceView& AstNode::srcView(const TaskContext& ctx) const
{
    return ctx.compiler().srcView(srcViewRef());
}

const Ast* AstNode::sourceAst(const TaskContext& ctx) const
{
    const SourceFile* file = srcView(ctx).file();
    if (!file)
        return nullptr;
    return &file->ast();
}

TokenRef AstNode::tokRefEnd(const Ast& ast) const
{
    const auto& info = Ast::nodeIdInfos(id_);

    SmallVector<AstNodeRef> children;
    info.collectChildren(children, ast, *this);

    if (children.empty())
        return codeRef_.tokRef;

    const AstNode& node = ast.node(children.back());
    return node.tokRefEnd(ast);
}

AstNodeRef AstNode::nodeRef(const Ast& ast) const
{
    return ast.findNodeRef(this);
}

SWC_END_NAMESPACE();
