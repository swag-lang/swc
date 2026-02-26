#pragma once
#include "Support/Core/StrongRef.h"

SWC_BEGIN_NAMESPACE();

class SourceView;
struct Token;
struct AstNode;
class TypeInfo;
class ConstantValue;
struct Identifier;
struct MicroOperandRefTag;
struct MicroLabelRefTag;
struct MicroInstrRefTag;

using SourceViewRef   = StrongRef<SourceView>;
using TokenRef        = StrongRef<Token>;
using AstNodeRef      = StrongRef<AstNode>;
using TypeRef         = StrongRef<TypeInfo>;
using ConstantRef     = StrongRef<ConstantValue>;
using IdentifierRef   = StrongRef<Identifier>;
using MicroOperandRef = StrongRef<MicroOperandRefTag>;
using MicroLabelRef   = StrongRef<MicroLabelRefTag>;
using MicroInstrRef   = StrongRef<MicroInstrRefTag>;

SWC_END_NAMESPACE();
