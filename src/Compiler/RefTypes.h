#pragma once
#include "Support/Core/StrongRef.h"

SWC_BEGIN_NAMESPACE();

class SourceView;
struct Token;
struct AstNode;
class TypeInfo;
class ConstantValue;
struct Identifier;

using SourceViewRef = StrongRef<SourceView>;
using TokenRef      = StrongRef<Token>;
using AstNodeRef    = StrongRef<AstNode>;
using TypeRef       = StrongRef<TypeInfo>;
using ConstantRef   = StrongRef<ConstantValue>;
using IdentifierRef = StrongRef<Identifier>;

SWC_END_NAMESPACE();
