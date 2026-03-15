#include "pch.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void walkBoundaryOnSameLine(const TaskContext& ctx, const Ast& ast, const SourceView& view, const AstNode& root, SourceViewRef baseViewRef, uint32_t baseLine, bool walkLeft, SourceCodeRange& boundaryLoc)
    {
        SmallVector<AstNodeRef> children;
        const AstNode*          current = &root;
        while (true)
        {
            children.clear();
            Ast::nodeIdInfos(current->id()).collectChildren(children, ast, *current);
            if (children.empty())
                break;

            const AstNodeRef childRef = walkLeft ? children.front() : children.back();
            if (childRef.isInvalid())
                break;

            const AstNode& child = ast.node(childRef);
            if (child.srcViewRef() != baseViewRef)
                break;

            const SourceCodeRange childLoc = view.token(child.tokRef()).codeRange(ctx, view);
            if (childLoc.line != baseLine)
                break;

            current = &child;
            if (walkLeft)
            {
                if (childLoc.offset < boundaryLoc.offset)
                    boundaryLoc = childLoc;
            }
            else if (childLoc.offset > boundaryLoc.offset)
            {
                boundaryLoc = childLoc;
            }
        }
    }
}

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef)
{
    ast.appendNodes(out, spanRef);
}

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes)
{
    for (const AstNodeRef n : nodes)
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

    const SourceViewRef baseViewRef = codeRef_.srcViewRef;
    const SourceView&   view        = ctx.compiler().srcView(baseViewRef);
    if (codeRef_.tokRef.isInvalid() || view.tokens().empty())
        return codeRange;

    const Token&          baseTok  = view.token(codeRef_.tokRef);
    const SourceCodeRange baseLoc  = baseTok.codeRange(ctx, view);
    const uint32_t        baseLine = baseLoc.line;

    SourceCodeRange startLoc = baseLoc;
    walkBoundaryOnSameLine(ctx, ast, view, *this, baseViewRef, baseLine, true, startLoc);

    SourceCodeRange endLoc = baseLoc;
    walkBoundaryOnSameLine(ctx, ast, view, *this, baseViewRef, baseLine, false, endLoc);

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
    const AstNodeIdInfo& info = Ast::nodeIdInfos(id_);

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
