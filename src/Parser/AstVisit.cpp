#include "pch.h"
#include "Parser/AstVisit.h"
#include "Lexer/SourceFile.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

void AstVisit::start(AstVisitContext& ctx, const Ast& ast)
{
    ast_ = &ast;
    if (ast_->root().isInvalid())
        return;
    if (!ctx.currentLex)
        ctx.currentLex = &ast_->lexOut();

    AstVisitContext::Frame fr;
    fr.nodeRef      = ast_->root();
    fr.stage        = AstVisitContext::Frame::Stage::Pre;
    fr.nextChildIx  = 0;
    fr.sourceAtPush = ctx.currentLex;
    ctx.stack.push_back(std::move(fr));
}

bool AstVisit::step(AstVisitContext& ctx) const
{
    if (ctx.stack.empty())
        return false;

    auto& fr = ctx.stack.back();
    switch (fr.stage)
    {
        case AstVisitContext::Frame::Stage::Pre:
        {
            const AstNode* node = resolveNode(fr);
            SWC_ASSERT(node->id != AstNodeId::Invalid);
#if SWC_HAS_STATS
            Stats::get().numVisitedAstNodes.fetch_add(1);
#endif

            if (!node)
            {
                ctx.stack.pop_back();
                return !ctx.stack.empty();
            }

            // Pre-order callback
            if (cb_.pre)
            {
                const Action a = cb_.pre(ctx, node);
                if (a == Action::Stop)
                {
                    ctx.stack.clear();
                    return false;
                }
                if (a == Action::SkipChildren)
                {
                    fr.stage = AstVisitContext::Frame::Stage::Post;
                    return true;
                }
            }

            // Collect child refs at once
            fr.children.clear();
            collectChildren(fr.children, node);

            fr.stage = AstVisitContext::Frame::Stage::Children;
            return true;
        }

        case AstVisitContext::Frame::Stage::Children:
        {
            // Still have a child to descend into?
            while (fr.nextChildIx < fr.children.size())
            {
                const AstNodeRef childRef = fr.children[fr.nextChildIx++];
                if (childRef.isInvalid())
                    continue;
                SWC_ASSERT(childRef.get() != 0);
                
                AstVisitContext::Frame childFr;
                childFr.nodeRef      = childRef;
                childFr.stage        = AstVisitContext::Frame::Stage::Pre;
                childFr.nextChildIx  = 0;
                childFr.sourceAtPush = ctx.currentLex;
                ctx.stack.push_back(std::move(childFr));
                return true;
            }

            // No more children -> go to post
            fr.stage = AstVisitContext::Frame::Stage::Post;
            return true;
        }

        case AstVisitContext::Frame::Stage::Post:
        {
            const AstNode* node = resolveNode(fr);
            SWC_ASSERT(node->id != AstNodeId::Invalid);

            // Post-order callback
            if (cb_.post)
            {
                const Action a = cb_.post(ctx, node);
                if (a == Action::Stop)
                {
                    ctx.stack.clear();
                    return false;
                }
            }

            ctx.stack.pop_back();
            return !ctx.stack.empty();
        }
    }

    SWC_UNREACHABLE();
}

void AstVisit::run(AstVisitContext& ctx) const
{
    while (step(ctx))
    {
    }
}

void AstVisit::collectChildren(SmallVector<AstNodeRef>& out, const AstNode* node) const
{
    const auto& info = Ast::nodeIdInfos(node->id);
    info.collectChildren(out, ast_, node);
}

const AstNode* AstVisit::resolveNode(const AstVisitContext::Frame& fr) const
{
    if (fr.nodeRef.isInvalid() || !fr.sourceAtPush)
        return nullptr;
    return ast_->node(fr.nodeRef);
}

SWC_END_NAMESPACE()
