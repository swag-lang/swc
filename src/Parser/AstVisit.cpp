#include "pch.h"
#include "Parser/AstVisit.h"
#include "Lexer/SourceFile.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

void AstVisit::start(AstVisitContext& ctx, const SourceFile* rootFile, AstNodeRef rootRef)
{
    if (rootRef.isInvalid())
        return;
    if (!ctx.currentSource)
        ctx.currentSource = rootFile;

    AstVisitContext::Frame fr;
    fr.nodeRef      = rootRef;
    fr.stage        = AstVisitContext::Frame::Stage::Pre;
    fr.nextChildIx  = 0;
    fr.sourceAtPush = ctx.currentSource;
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
            collectChildRefs(node, fr.children);

            fr.stage = AstVisitContext::Frame::Stage::Children;
            return true;
        }

        case AstVisitContext::Frame::Stage::Children:
        {
            // Still have a child to descend into?
            if (fr.nextChildIx < fr.children.size())
            {
                const AstNodeRef childRef = fr.children[fr.nextChildIx++];

                AstVisitContext::Frame childFr;
                childFr.nodeRef      = childRef;
                childFr.stage        = AstVisitContext::Frame::Stage::Pre;
                childFr.nextChildIx  = 0;
                childFr.sourceAtPush = ctx.currentSource;
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

void AstVisit::collectChildRefs(const AstNode* node, SmallVector<AstNodeRef>& out)
{
    const auto& info = Ast::nodeIdInfos(node->id);
    info.collect(node, out);
}

const AstNode* AstVisit::resolveNode(const AstVisitContext::Frame& fr)
{
    if (fr.nodeRef.isInvalid() || !fr.sourceAtPush)
        return nullptr;

    // IMPORTANT: resolve with the file snapshot captured when this frame was pushed.
    // This preserves the original semantics where children were resolved using the
    // current file at discovery time, regardless of later file-scope changes.
    return fr.sourceAtPush->parserOut().ast().node(fr.nodeRef);
}

SWC_END_NAMESPACE()
