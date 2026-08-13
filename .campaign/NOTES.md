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

## RÉGLÉ 2026-08-13: crash macro me-binding (ex-BLOCAGE COURANT)
- Diagnostic complet. La maladie: avec les receveurs UFCS SANS cast, l'expression
  de binding `me` d'un macro (`.header.bag`, `.chunks`...) porte un SYMBOLE stocké
  = le CHAMP feuille (ou, faute de champ, le paramètre me brut du macro). Trois
  chemins prenaient ce symbole pour « nommable seul »:
  1. Sema.Member.Auto addCandidateFromInlineReceiverPayload:295 (candidat symVar nu),
  2. SemaInline materializedReceiverBinding:313 (binding var du frame),
  3. les boucles bindingVars de collectAutoMemberCandidates:450/458 (+
     bindCurrentReceiverIfCandidateMatches).
  L'identifiant gauche synthétisé par makeAutoMemberLeftExpr porte ce symbole SANS
  base, court-circuite la re-résolution (token `.` + symbole présent,
  Sema.Identifier:638), et resolveIdentifierVariablePayload n'a aucune catégorie
  pour un champ d'instance → SWC_UNREACHABLE. Variante me-param: encore pire,
  resolveCanonicalParameter (CodeGenFunctionHelpers:462) remappe PAR NOM sur le
  me de l'APPELANT → mauvaise base silencieuse.
  Le monde REF ne passait jamais là: le receveur était enrobé castToReference
  (pas de symbole stocké) → chemin sain = candidat par TYPE + baseExprRef
  (clone détaché de l'expression receveur par usage élidé).
- FIX: prédicat partagé SemaHelpers::bindingSymbolResolvesStandalone (ni champ
  d'instance, ni paramètre d'une AUTRE fonction) appliqué aux 4 sites ci-dessus;
  sinon retombée sur le candidat type+baseExprRef (sain, les deux mondes l'ont).
- Repro réduit: .campaign/probe5.swg (receveur membre imbriqué + offsets non nuls
  anti-coïncidence) + test de suite bin/unittests/native/inline/
  macro_receiver_member_access.swg. Les sondes .campaign vertes (JIT + natif).
- CRASH 2 (même famille): receveur avec INDEX (`.shapes[shapeId].fields`,
  tagbin.swg:829) → CodeGen.Index.cpp:321. Le candidat type+baseExprRef clone en
  DÉTACHÉ par usage élidé, et le clone détaché JETTE le substitut des nœuds
  ré-expansibles (IndexExpr, CallExpr...) en comptant sur une re-sema qui n'existe
  pas dans le flux auto-member (SkipChildren, état posé à la main). Les chaînes de
  membres pures survivent (état répliqué), pas les index.
- FIX 2 (l'équivalent monde-références): matérialiser le binding me des
  macros/mixins en préfixe `let __inline_arg = cast(<type param>) <clone détaché>`
  quand l'expression receveur n'est pas une variable nommable seule
  (receiverNeedsStandaloneHome, SemaInline materializeInlineBindings). Le cast
  synthétisé porte CodeGenLoweringPayload.ufcsReceiverAddress → codegen émet
  l'ADRESSE (CodeGen.Cast:1383, les 2 tryEmit* du stage 2). Le monde REF faisait
  EXACTEMENT ça: le receveur cast-wrappé n'était pas une « direct stable lvalue »
  → matérialisé; le castless a accidentellement pris le raccourci direct.
  Évaluation UNE fois, binding var = local résoluble, élisions saines.
- Repro réduit: .campaign/probe6.swg (index en fin et milieu de chaîne) + test de
  suite bin/unittests/native/inline/macro_receiver_indexed_access.swg.
  9/9 sondes vertes (JIT + natif), BUILD 29.
- string.swg:301 contourné avec `.buffer![0]` (doc-conforme). probe4 verte.
- Edits antérieurs en place: paramBindsByAddress (exclusions safety/direct/address),
  narrow-pin par cast détaché pour bindings adresse (SemaInline ~1674),
  boxing variadique const *T, receveur UFCS SANS cast (lvalue ET rvalue,
  storage rvalue via __call_arg_ptr_storage + spill codegen CallHelpers ~1080).

## RÉGLÉ 2026-08-13 (suite): trois portes du monde références restées mortes
- CRASH 3 (préexistant au stage 2, prouvé par bissection binaire 26+merge):
  receveur RVALUE d'un opCast #[Implicit, Inline] (ex: `g_StoreArgs =
  Utf8.fromUtf16(...)` → opCast String→string → opSet). buildStructOpCastResolvedArgs
  ne posait que bindsReferenceToValue (gardé sur isReference) → les BITS de la
  struct passaient comme pointeur receveur. FIX: structOpCastPassesAddressAsPointer
  (Cast.Cast.cpp) pose passUfcsAddressAsPointer (le flag du receveur UFCS castless)
  + NeedsAddressableStorage pour les sources scalaires. Sonde probe7.swg; suite
  native/specops/operator_cast_rvalue_receiver.swg.
- CRASH 4 (même famille): le receveur du cast SET (conversion opSet implicite,
  ex: `arr.add("alpha")` → temp String) codait en dur bindsReferenceToValue=true.
  Même fix (réutilise le prédicat).
- CRASH 5 (LE gros — cause réelle des mimalloc 0x6C61/0x6766 des tools):
  CodeGen.Foreach emitForeachBindSymbols décidait adresse-vs-copie sur
  isReference() → le binding struct par valeur (désormais const *T synthétisé)
  prenait la branche COPIE: memcopy de sizeof(T) octets dans le slot pointeur
  de 8 → le binding contenait les premiers octets de l'élément (le ptr du
  premier champ string = le TEXTE). Déclencheur partout: `for f in typeof.fields`
  (#ast de IsSet, commandline.swg), toute boucle sur tableau natif/slice de
  structs. FIX: flag de nœud AstForeachStmtFlagsE::BindsValueAddress posé par
  sema (Sema.Loop foreachElementTypes) quand il synthétise le pointeur; codegen
  le lit; l'alias d'échappement (bindForeachAddressAlias) le suit aussi.
  Sonde probe8.swg; suite native/flow/for_struct_member_variadic.swg
  (for_struct_binding.swg existant nette aussi la régression copie).
- Sondes de script (scratchpad, jetables): CommandLine.parse + Env.arguments +
  premain getNativeArgs + visites Array'String — toutes vertes au build 34.
- BUILDS: 30 = bissection (26+merge, sans mes fixes), 31 = fixes restaurés,
  32 = +opCast, 33 = +Set-cast, 34 = +foreach binding.

## État session 2026-08-13
- master local MERGÉ dans noref (Tier B/C: deque/orderedmap/orderedset/
  priorityqueue/mappedfile/watcher/globalization/json + win32). Nouveaux fichiers
  migrés au monde pointeurs (opIndexPtr, frontPtr/backPtr/peekPtr, injects *T,
  comparateurs par valeur, {source: me}). Balayage `&me` nus hérités (allocator
  pages KEY/segmentBase!, GWLP_USERDATA, encoder/decoder dref me, wnd/menuctrl,
  audio bus, rendercpu): `&me` = adresse du SLOT en monde pointeur, l'objet c'est
  `me`. BUILD NUM 28 (27 = merge+instrumentation, 28 = fix). Un bump par binaire
  exécuté, toujours.
- REPRENDRE: échelle core → pixel → gui → tests.swgs dm, puis D/E/F/G.

## RÉGLÉ 2026-08-13 (session suivante): la corruption native ET l'échelle core+pixel
- CORE VERT: `swc_devmode tools\std.swgs dm test core` → 576 passed (JIT+natif).
- PIXEL VERT: `tools\std.swgs dm test pixel` → 361 passed.
- Les root causes, dans l'ordre (commits 1a5e0f209, f65690fd3, 851efe9ff, + en cours):
  1. RECEVEUR RVALUE D'UN INLINE (la corruption sandbox): materializeInlineReceiverBinding
     et materializeInlineBindings homaient le receveur PAR VALEUR → le temporaire migrait
     dans le scope inline, dont la sortie le DROPPAIT pendant que l'expression englobante
     consommait encore la slice (.toString()). Fix: le home tient l'ADRESSE (cast
     ufcsReceiverAddress + __call_arg_ptr_storage pour les valeurs en registre); les uses
     élidés ne comptant pas comme uses de `me`, le cas rvalue est forcé explicitement
     (forceReceiverHomeMaterialization). Suite: native/inline/inline_rvalue_receiver_lifetime.swg
     (opDrop-poison, sans allocateur). Sonde probe9 scratchpad.
  2. RECEVEUR USING-PATH CASTLESS: le `continue` castless de Match applyCasts s'appliquait
     même quand le pointee ≠ source (récepteur `using base`), et passUfcsAddressAsPointer
     refusait → codegen DÉRÉFÉRENÇAIT le receveur (ArrayPtr.add plantait me=slot). Fix:
     la route castless exige pointee == source. Suite: native/using/using_base_receiver_call.swg.
  3. SPILL DES RECEVEURS STRUCT-REGISTRE: un struct 8 octets revenu en RAX n'avait pas de
     scalarStoreBits → jamais spillé → les BITS passaient comme pointeur me
     (Id.make() == b). Fix: spill par taille de stockage (CodeGenCallHelpers ~1084).
     Suite: native/specops/operator_equals_register_rvalue_receiver.swg.
  4. FOLD CONST-SET: supportsConstSetCallJit + buildConstSetCallArguments gataient sur
     isReference → l'opSet ConstExpr d'un champ de littéral d'agrégat ne foldait plus et
     tombait dans un chemin runtime qui PERD la source constante (angle 'deg). Fix: accepter
     le pointeur-valeur non-null. Suite: jit/compiler/const_eval_pointer_set_receiver.swg.
     Le trou runtime résiduel (opSet NON-ConstExpr + source constante) est PRÉ-EXISTANT
     (master échoue la même sonde) → F-129.
  5. ZÉROING FALLIBLE LARGE (pré-existant, master crashe aussi): le storage unique du nœud
     fail servait l'ERREUR et le RÉSULTAT zéro; taillé pour l'erreur, le zéroing d'un
     résultat 512 octets écrasait la frame (ImageCanvas). Fix: storage taillé au max des
     deux (AstFailExpr::semaPostNode). Suite: native/flow/fallible_wide_result_fail.swg.
  6. RECEVEUR CONSTANTE → ADRESSE NATIVE (pré-existant en germe): un struct constant lié
     à un me pointeur était LOWERÉ en octets → adresse de payload-buffer compilateur baked
     dans le code → JIT OK, natif mort (ImageFormat.matches). Fix: le matérialiseur passe
     l'adresse du STATIC payload (segment relogeable) (materializeDefaultConstantPayload).
     Suite: native/functions/constant_receiver_address.swg.
  7. APPEL QUALIFIÉ EXPLICITE: `Vec2.length(v)` ne liait pas me par adresse (les checks
     exigeaient un ufcsArg) → bits bruts comme pointeur me. Fix: bindsExplicitMeAddress
     (SÉPARÉ de allowsImplicitAddressBinding: le RANKING d'overloads ne doit PAS changer —
     l'étendre à la volée a cassé 88 tests core par flips de sélection, leçon apprise).
  8. `ptr == null` NE PEELE PLUS: le retry relationnel peelait le pointeur non-null vers
     l'opEquals du pointé même face à null → 46 erreurs gui. Fix: null reste une question
     d'identité (SemaSpecOp tryResolveRelational). Suite: native/types/pointer_null_compare.swg.
  9. MUTATION D'ÉLÉMENT EN ITÉRATION: le checker flaggait `for &v in volumes do
     v.removeBack()` (méthode String via le binding pointeur) comme mutation STRUCTURELLE
     du conteneur. Fix: ne flagger que si l'owner-struct du callee EST le type de la
     source itérée (checkIterationMutation). Master acceptait la même source.
- MIGRATIONS bin/: truetype findTable (`return it`), pixel svgparse/rendercpu/layer
  (dref sur bindings scalaires, bindings passés tels quels, assert null retiré),
  gui localization/filebrowser/formlayout (idem + auto-scope explicité dans une closure).

## RÉGLÉ (session suivante): gui VERT — 379 passed (core 578, pixel 361)
- Le crash CodeGen.Index.cpp:321: l'ingrédient manquant de la réplique était le corps
  COURT + mtd NON-CONST de isVisible (`mtd isVisible() => .hidden == 0`). Deux défauts:
  10. CLONE DÉTACHÉ SANS SIDE-MAPS: copyDetachedBindingExprState (SemaClone) copiait
      l'état du nœud (type/symbole/substituts récursifs) mais PAS les semaPayloads
      (IndexSpecOpSemaPayload...) ni les resolved-call-arguments, qui vivent dans des
      side-maps par nœud. Le clone hérite d'un TYPE → sema le croit résolu → pas de
      re-résolution → codegen retombe sur l'index brut. Fix: porter le semaPayload
      (partagé, gardé si le clone en a déjà un) + copyResolvedCallArguments; et
      applyIndexReadSpecOpResult clear-avant-set (une re-résolution de clone remplace
      légitimement la sélection portée). Trace décisive: le nœud du crash ≠ le nœud
      résolu par sema (chaîne parents: le clone de substitution directe du receveur
      dans le corps court inline).
  11. FALLBACK SPEC-OP RECEVEUR-SEUL (porte monde-références morte): dans
      tryResolveReceiverOnlySpecOp, quand le match sonde échoue (candidat unique),
      le resolvedArg ne posait bindsReferenceToValue QUE pour un receveur RÉFÉRENCE
      → me *Array recevait les 8 premiers octets de l'opérande (le buffer!) comme
      pointeur (`@countof(param Array par valeur)` → count poubelle → dépassement).
      Fix: la branche pointeur-valeur non-null pose passUfcsAddressAsPointer +
      NeedsAddressableStorage/__call_arg_ref_storage comme la branche référence.
- Tests de régression (nécessitent core, donc tests bin/std):
  unittests/collections/arrayptr.test.swg — l'élément indexé+bang receveur d'un
  mtd inline COURT non-const, et @countof d'un Array paramètre par valeur.
- L'assert du fallback raw-index garde son dump enrichi (type + nœud + parents,
  DEV_MODE) — c'est lui qui a permis le diagnostic.

## REPRENDRE ICI
- `tools\tests.swgs dm` (suites complètes), fallout itératif, puis D (suppression du
  kind Reference), E (unittests refs), F (doc).
- BUILD NUM: 63 = binaire courant. RE-BUMPER à 64 au prochain rebuild.
- ÉTAT: core COMPILE et FORGE (320 fichiers, core.test.exe) ✓. Les tools TOURNENT
  (std.swgs parse ses args, compile le workspace, lance le test) ✓. Le crash
  restant est au RUNTIME NATIF de core.test.exe, dans __init_8 (sandbox):
  `Path.directoryName` reçoit un chemin dont les PREMIERS OCTETS SONT NULS.
- FIX POSÉ EN CHEMIN: Env.getNativeArgs ne CONCATÈNE plus @pinfos.args à la
  ligne de commande OS — la ligne effective transmise par la chaîne de hooks
  GAGNE (environment.win32.swg). Sans ça, la premain de core.dll (2e passage,
  rtflags=0 — passage PROGRAMME voulu par le hook généré, bits done disjoints)
  doublait/collait les args → CommandLine.parse voyait « dm » décalé → le tool
  prenait swc.exe au lieu de swc_devmode. Args OK vérifiés vs oracle master.
- DIAGNOSTIC du crash natif restant (sondes byte-level, retirées de l'arbre):
  * `root` arrive à enterSandbox avec path[0]==0 → GetFullPathNameW échoue →
    fallback → le chemin nul se propage → assert isValidPathName.
  * La ligne source: defaultSandboxRoot →
    `Path.combine(realSpecialDirectory(.Temp).toString(), "swag-sandbox")` —
    le TEMPORAIRE String de realSpecialDirectory semble libéré pendant que sa
    slice .toString() est encore consommée (nommer le temporaire dans une
    var locale GUÉRIT — heisenbug). NE PAS committer ce contournement: le
    root-cause est la planification des drops de temporaires d'argument en
    NATIF (JIT vert sur la même forme!).
  * Avec le temporaire nommé, l'init PASSE et les tests démarrent, puis
    d'autres pannes mémoire: « memory block address is not the start of an
    allocation » — 2e famille probable: un buffer AVANCÉ puis free (op String
    genre trimLeft/remove migrée, ou même famille de drops).
- HARNAIS DISPONIBLES (rapides):
  * Module natif isolé important core: scratchpad p9m (test -d src
    --module-file module.swg) — 1 s/cycle, JIT+natif; 5 sondes vertes (retval
    String, utf16 round-trip, stack-buffer retval, ligne sandbox exacte,
    réplique defaultSandboxRoot+catch-else) — la corruption NE se reproduit
    PAS isolée: il faut le contexte d'init réel de core.dll.
  * Scripts scratchpad boxprobe*.swgs (JIT): args/rtflags/ctx — tous verts.
  * L'oracle: swc.exe ET swc_devmode.exe de c:\Perso\swag-lang\swc (master,
    build du 13/08 11:50) — comparer chaque comportement douteux.
- PISTE POUR LA REPRISE: instrumenter les DROPS émis en natif autour de
  `f().toString()` en argument (CodeGen des temporaires de statement, hooks
  opDrop des String/Array en sortie d'#init), comparer JIT vs natif sur le
  MÊME AST; et viser la 2e famille via les tests qui suivent l'init une fois
  le sandbox passé (réactiver temporairement le tempDir nommé pour ça).
- BUILD NUM: 38 = binaire courant (tous les fixes C++ committés + ConstantLower
  + passthrough encore NON committés au moment du build — ils le sont
  maintenant). RE-BUMPER à 39 au prochain rebuild.
