#pragma once

using Ref         = uint32_t;
using AstNodeRef  = Ref;
using FileRef     = Ref;
using TokenRef    = Ref;
using JobClientId = Ref;

constexpr AstNodeRef  INVALID_AST_NODE_REF  = UINT32_MAX;
constexpr FileRef     INVALID_FILE_REF      = UINT32_MAX;
constexpr TokenRef    INVALID_TOKEN_REF     = UINT32_MAX;
constexpr JobClientId INVALID_JOB_CLIENT_ID = UINT32_MAX;
