# Campagne noref — plan stage 2 (suppression du type référence)

Worktree: c:\Perso\swag-lang\swc-noref, branche `noref`.
Stage 1 (fait, commits 36f7bb6db + 575ec97e6): opIndexPtr + UFCS ptr receivers +
indexing/spec-ops à travers *T non-null + bin/ vidé des refs explicites.
Validation stage 1 EN ATTENTE du créneau de test (autre agent dessus).

## Échelle de validation stage 1 (dès créneau libre)
1. `bin\swc_devmode.exe tools\std.swgs dm test core` puis `pixel`, `gui`
2. `bin\swc_devmode.exe tools\tests.swgs dm` (complet)
NB: binaire DevMode à jour (rebuild fait après tous les edits C++).

## Stage 2 — ordre d'exécution

### A. Parser: rejeter `&T` en position de type
- src/Compiler/Parser/Parser/Parser.Type.cpp:184-194 (AstNodeId::ReferenceType) →
  erreur dédiée "references were removed; use a pointer '*T'" (nouvelle diag parser,
  suivre write-swag-compiler-messages). GARDER #move/#fwd (MoveRefType, lignes 196-230).

### B. me → pointeur
- Sema.Function.cpp:1430-1474 addMeParameter: makeReference → pointeur non-null
  (const *T pour mtd const). Cast.Runtime.cpp:252-256 (miroir matching).
- Réflexion: typeinfo receivers deviennent *T (tests typeinfo_struct_methods à adapter).
- `me` passé en valeur qq part dans bin/? `let self: const *Image = me` déjà écrit
  compatible deux mondes (image.swg:226, crop.swg:7).

### C. for/foreach bindings → pointeurs
- Sema.Loop.cpp:399-416: `for &v` → *T (const *T si source const); struct `for v` →
  const *T (JAMAIS copie). #typeof(v) devient un pointeur: adapter les tests
  for_struct_binding.swg (typeof + écritures v = X → dref v = X? NON: v pointer,
  écriture élément = dref v = X).
- Protocole opVisit: bin les `#inject(... cast(&T) ...)` → cast(*T); scalar path
  `item = scan[0]` inchangé. Fichiers: runtime/iteration.swg:135-206,
  core array.swg:190-192, staticarray.swg:146-148, list.swg:50,52,115,117,
  hashtable.swg:74-80,215-221, hashset.swg:72-74,185-187, string.swg:289.
  + les CORPS de `for &v` dans bin/ (gui/apps/std, ~168 sites): écritures scalaires
  `v = x`/`v *= k` → dref; membres v.f inchangés (peel pointeur).
- CodeGen.Foreach.cpp:380-385, 456 (unwrapAliasRefPayload) à adapter.

### D. Suppression TypeInfoKind::Reference
- TypeInfo.h:52 (kind), 138-141 (isReference — ATTENTION: couvre aussi MoveReference;
  narrower: garder isMoveReference, retyper les ~110 sites disjonction pure).
- makeReference (TypeInfo.cpp:932-946) supprimé; makeMoveReference RESTE.
- Cast.Cast.cpp castToReference:1281-1440 → ne garder que la branche moveref
  (copy-to-move Match.Func.cpp:62-98 bindsReferenceToValue reste pour #move).
- Les 4 copies shouldReadReferenceValue (Sema.Binary/Assign/Logical/Unary) →
  réduire à moveref (params #move lisibles en valeur).
- Sema.Assign.cpp:20-37 assignmentTargetTypeRef: garder pour moveref? (#move param
  comme cible d'écriture: vérifier tests move.swg `a = #move b` — a était &V,
  devient *V → `dref a = #move b`... NON: opAssign des tests. À trancher sur tests.)
- SemaJIT.cpp:155-159,686-990 carve-outs refs → moveref only.
- SemaEscape, SemaInline (12 sites), Match ranks, TypeRuntimeHash:399-407,
  ABITypeNormalize:51, DebugInfoCodeView:1142, Runtime.h PointerRef flag,
  runtime api.swg:693 (PointerRef flag mort — garder valeur, ne pas renuméroter).
- Diagnostics: retirer sema_err_ref_missing_init, sema_err_const_ref_type;
  reformuler sema_err_move_arg_param_not_move ("pointer parameter");
  parser_err_invalid_type (mention "reference").

### E. Unittests (2/3 des usages refs du repo)
- SUPPRIMER/RÉÉCRIRE: native|sema/types/reference*.swg, take_address (parties refs),
  inline/reference_return_address, scalar_ref_value_arg, inline_const_ref_address,
  inline_reftuple, args_untyped_variadic_ref, function_pointer_ref,
  jit/compiler/array_ref_indexing (→ opIndexPtr), specops/operator_index_reference_*,
  errors sema_err_ref_missing_init.swg, sema_err_const_ref_type.swg,
  sema_err_no_overload_match.swg:66-76 (cas ref), assign_to_const (cas for-binding à retyper),
  nullable_use_site refs, countof refs, compare refs, casts auto/explicit/any refs,
  reflection typeinfo_struct_methods (&T → *T).
- AJOUTER: erreur `&T` en type (parser), for-bindings pointeurs (typeof), me *T.

### F. Doc + VSCode + skills
- bin/reference/modules/language/src/004_008_references.swg SUPPRIMÉ (absorber le
  peu utile dans 004_007_pointers: opIndexPtr, indexing à travers *T).
- 004_007_pointers.swg:158-196 (section "reference is transparent") réécrite.
- 005_003_for_elements.swg (for &v = adresse), 006_008_custom_iteration (ptr:bool),
  006_009 (assign exemple &Vector3 → *Vector3 + dref), 007_006 ufcs, 002_007/002_008
  catalogues, 013_004 borrowing (retirer "reference" de la liste des views).
- 006_005 operator_overloading: documenter opIndexPtr.
- .agents/skills/write-idiomatic-swag-code: "Prefer references for non-null borrowed
  values" → pointeurs non-null. design-swag-bin-modules si mention.
- vscode/syntaxes/swag.tmLanguage.json: vérifier si `&` type highlighting existe.
- swc format (src/Format): virer le support du type `&`.

### G. Fin de campagne
- Version bump déjà fait (25). UN SEUL bump pour toute la campagne? Non: bump par
  change → déjà 25, stage 2 = re-bump 26.
- backlog: T-xxx phase 2 ergonomie (sucre éventuel: lvalue-deref postfix, etc.)
  + findings F-xxx si régressions perf inline opIndexPtr.
- Rapport final: différences supprimées, coûts, propositions phase 2 (l'utilisateur
  veut des propositions d'amélioration de syntaxe APRÈS migration fonctionnelle).

## Décisions arrêtées (ne pas rouvrir)
- opIndexPtr: place contexts = membre, &, cible d'assignation, index imbriqué;
  valeur d'abord hors place; jamais const-eval; inline OK.
- Paramètres struct const& → par VALEUR (ABI const-address, zéro copie).
- Paramètres mutables &T → *T (+ dref corps); scalaires chauds: copie locale + defer.
- #move/#fwd inchangés (MoveReference interne conservé).
- Les helpers "visit" tests: par pointeur + `for ... in dref values`.

## État itération stage 2 (checkpoint courant)
- core COMPILE jusqu'au run des tools; erreurs résiduelles = boxing variadique.
- BUG EN COURS: for-binding *String passé à un variadic any → box incohérent
  (typeinfo String + bits du pointeur comme données) → ConcatBuffer.grow taille
  poubelle (mimalloc 0x6C61...). Repro attendu: `for name in arr { sb.appendFormat("%", name) }`.
  Piste compilateur: typage du box variadique (assignUntypedVariadicTypeInfo,
  Match.Func.cpp ~2809) vs codegen box (CodeGenCallHelpers.Call.cpp:227-234 règle
  "const ref boxed as pointee") — décider: box *T = (typeinfo *T, data=ptr) COHÉRENT,
  puis dref aux sites bin/tools qui veulent la VALEUR.
- Corrections faites cette itération: opCast receiver ptr (Cast.Struct:414),
  using-path castToPointer UFCS + codegen (2 tryEmit*), me=X→dref me (9 sites),
  {source: me}, dref me += (vectors), relational retry peel (garde isType/pointerLike),
  isOwnerStructType peel ptr, generated opEquals/opCompare par valeur,
  materializeInlineBindings decl nul, CodeGen.Member indirection pré-override,
  markConstParamBindingTarget ptr mut, tryResolveIndexAssign writesThroughPtr,
  tools campaign/workspaces dref bindings, latin1/find/floatext/scc/env.window/directory.

## Reprise immédiate (état exact)
- DERNIÈRE ERREUR core: string.swg:301 `if .buffer do .buffer[0] = 0` →
  "indexing into '#null [*] u8' dereferences a value that can still be null".
  Le narrowing `if .buffer` ne s'installe/retrouve plus avec me POINTEUR.
  Chaîne: SemaHelpers::collectNarrowGuardFromExpr → extractNarrowPath
  (SemaHelpers.cpp:393, gère MemberAccess+racines) — vérifier ce que le substitut
  du membre ÉLIDÉ résout (resolveNarrowSourceRef viewZero + transparent casts)
  côté INSTALLATION (condition) ET côté REQUÊTE (usage nullable-index,
  Sema.Index sema_err_nullable_index → qui interroge queryNarrowFact?).
  Repro sonde: struct { buf: #null [*] u8 } + mtd { if .buf do .buf[0] = 0 }.
- FAIT depuis le dernier commit: boxing variadique const *T = pointé
  (dereferenceConstUntypedVariadicArgument + assignUntypedVariadicTypeInfo,
  receveur exclu des deux côtés) — le crash mimalloc des tools est réglé;
  receveur UFCS lvalue SANS nœud de cast (Match.Func applyCasts `continue`,
  route passUfcsAddressAsPointer) — élimine la pollution de substitut sur pause
  (erreurs String/hasExtension disparues); sondes probe-ufcs-ptr 3/3 vertes,
  probe-me-ptr 3 tests verts.
- Après ce fix: reprendre l'échelle core→pixel→gui→tests.swgs dm, puis D (suppression
  du kind), E (unittests), F (doc). Les sondes scratchpad probe-* doivent rester vertes.
- PRÉCISION: probe4 (narrowing `if .buf do .buf[0]=0` dans un mtd NON inline) PASSE.
  L'échec string.swg:301 vient donc du contexte INLINE (#[Inline] clear() cloné chez
  l'appelant): le clone du garde/usage à travers la liaison du receveur pointeur.
  Regarder SemaClone/SemaInline: clonage des gardes de narrowing + bindings me,
  et forceRuntimeSafetyMaterialization (SemaInline:1638 excluait isReference —
  faut-il exclure aussi les pointeurs receveurs?). Sonde à écrire: même struct
  avec #[Swag.Inline] sur la mtd + appel depuis #test.

## BLOCAGE COURANT (reprendre ICI)
- CRASH: SWC_UNREACHABLE CodeGen.Identifier.cpp:259 (resolveIdentifierVariablePayload)
  sur le `me` du MACRO opVisit (array.swg:177 `if !.count`) cloné chez des appelants
  core (Scc.validateManifest, Reader.findChunk...). Le symbole me-binding du macro
  n'entre dans AUCUNE catégorie de storage. PRÉ-EXISTAIT à mes edits narrow-pin.
  À comprendre: comment le monde REF résolvait l'identifiant me d'un corps de macro
  cloné (remplacement de binding par l'expr receveur? chemin ref-payload?), et
  pourquoi le monde POINTEUR le laisse passer en symbole brut. Regarder:
  SemaClone remplacement des identifiants de binding (idRef==me), CodeGen.Identifier
  245-259, et bindings me des macros (#[Macro] func(ptr) opVisit(const me,...)).
  Repro probable: #[Macro] mtd-like avec `const me` + `if !.count` + appel.
- string.swg:301 contourné avec `.buffer![0]` (doc-conforme). probe4 verte.
- Edits en place: paramBindsByAddress (exclusions safety/direct/address),
  narrow-pin par cast détaché pour bindings adresse (SemaInline ~1674),
  boxing variadique const *T, receveur UFCS SANS cast (lvalue ET rvalue,
  storage rvalue via __call_arg_ptr_storage + spill codegen CallHelpers ~1080),
  BUILD NUM 26 (ATTENTION: re-bump à CHAQUE rebuild désormais — le cache a
  masqué des états pendant des heures!).
