# Campagne noref — rapport final (BROUILLON stage F/G)

Branche `noref`, worktree `c:\Perso\swag-lang\swc-noref`. Rédigé le 2026-08-13, pendant que
les stages A (rejet parseur de `&T`), D (suppression du kind `Reference`), E (unittests) et
F (doc/VSCode/skills) sont préparés mais pas encore appliqués. Les chiffres ci-dessous sont
mesurés sur `git diff master...noref` et par grep sur les sources (hors `.dep/`/`.output/`).

Échelle globale du diff : **188 fichiers, +3135/−607 lignes**, dont :

| Zone            | Fichiers | +     | −    | Net   |
|-----------------|----------|-------|------|-------|
| `src/` (C++)    | 30       | 664   | 133  | +531  |
| `bin/std`       | 90       | 314   | 308  | **+6**|
| `bin/examples`  | 34       | 166   | 150  | +16   |
| `bin/apps`      | 3        | 4     | 4    | 0     |
| `tools/`        | 2        | 5     | 5    | 0     |
| `bin/unittests` | 15       | 1077  | 0    | +1077 (suites de non-régression des défauts, pas un coût de migration) |
| `.campaign/`    | 10       | 877   | 0    | (supprimé avant merge) |

---

## 1. Ce qui a été supprimé, ce qui est conservé

### Supprimé (la surface du type référence)

- **Le type `&T` / `const &T`** lui-même : la production parseur (`Parser.Type.cpp:184-194`,
  `AstNodeId::ReferenceType`) devient une erreur dédiée `parser_err_reference_type_removed`
  avec récupération vers `*T` (stage A, préparé) ; les deux lookaheads qui traitaient `&` comme
  début de type (`canStartSubType`, `parsePrimaryExpression`) tombent aussi.
- **`TypeInfoKind::Reference` et toute sa machinerie** (stage D, préparé) : `makeReference`,
  `castToReference` (~160 lignes, `Cast.Cast.cpp:1281-1440`, seule la branche moveref survit),
  les 4 copies de `shouldReadReferenceValue`, les carve-outs SemaJIT/SemaEscape/SemaInline,
  ~110 sites de disjonction `isReference()` à retyper.
- **`cast(&T)` / `cast(const &T)`** partout, y compris dans le protocole `opVisit`
  (`#inject(... cast(*T) ...)` désormais).
- **Les retours par référence** : `opIndex -> &T` remplacé par la paire `opIndexPtr -> *T`,
  `ref1`/`ref2` renommés `ptr1`/`ptr2`, familles `frontPtr`/`backPtr`/`peekPtr`.
- **Les diagnostics du monde référence** : `sema_err_ref_missing_init`,
  `sema_err_const_ref_type` ; reformulation de `sema_err_move_arg_param_not_move` et de l'aide
  de `parser_err_invalid_type` (« pointer/reference » → « pointer »).
- **Le chapitre de doc** `004_008_references.swg` (absorbé dans `004_007_pointers` réécrit,
  sections opIndexPtr et indexation à travers `*T`), plus le vocabulaire « reference » dans
  ~15 autres chapitres (drafts stage F prêts).
- **`&me`** comme idiome : avec `me` pointeur, `&me` est l'adresse du *slot* paramètre ;
  l'objet, c'est `me` tout court (balayage fait dans tout `bin/`).

### Conservé

- **`#move` / `#fwd`** et le `MoveReference` interne, inchangés, avec la règle copy-to-move
  (`Match.Func.cpp` `bindsReferenceToValue` reste pour `#move`).
- **`&` opérateur** : prise d'adresse en expression et ET binaire — aucune règle de
  highlighting à retirer côté VSCode, `&` reste dans la classe opérateur.
- **La seule indirection de surface : `*T` non-null** (et `#null *T` pour le nullable),
  `[*] T` pour les blocs.

### Remplacements (décisions arrêtées, ne pas rouvrir)

- Paramètres struct `const &T` → **par valeur** (ABI const-address, zéro copie).
- Paramètres mutables `&T` → `*T` + `dref` dans le corps ; scalaires chauds : copie locale
  + `defer` publication.
- `for v` sur éléments struct lie `const *T` (jamais de copie), `for &v` lie `*T` ;
  écriture scalaire d'élément = `dref v = x`.
- `opIndexPtr` : contextes *place* = membre, `&`, cible d'assignation, index imbriqué ;
  valeur d'abord hors place ; jamais const-eval ; inline OK.
- `me` = pointeur non-null (`const *T` pour `mtd const`).
- Helpers « visit » des tests : par pointeur + `for ... in dref values`.

---

## 2. Les défauts de compilateur débusqués par la migration

La migration a agi comme un fuzzer sur tout le codebase : chaque « porte » `isReference()`
du compilateur était un raccourci que la transparence du type référence maintenait en vie.
En les fermant, on a trouvé **~18 causes racines**, dont **au moins quatre pré-existaient sur
master** (prouvé par bissection ou par sonde identique sur le compilateur de référence) — la
référence ne faisait que les masquer. Une ligne chacune (mécanisme → site du fix) :

**Portes `isReference` restées mortes (le monde pointeur prenait la mauvaise branche) :**
1. Binding struct par valeur du foreach : codegen décidait adresse-vs-copie sur
   `isReference()` → memcopy de l'élément dans le slot pointeur de 8 octets (les crashes
   mimalloc 0x6C61 des tools) → flag `BindsValueAddress` posé par sema, lu par codegen et
   par l'alias d'échappement (`Sema.Loop` + `CodeGen.Foreach`).
2. Receveur d'un `opCast` struct rvalue : `buildStructOpCastResolvedArgs` ne posait que
   `bindsReferenceToValue` → les bits de la struct passaient comme pointeur receveur
   (`Cast.Cast.cpp`, `passUfcsAddressAsPointer`) — **pré-existant** (bissection binaire).
3. Receveur du cast Set (conversion `opSet` implicite) codé en dur
   `bindsReferenceToValue=true` → même fix, même prédicat.
4. Fold const-set : `supportsConstSetCallJit`/`buildConstSetCallArguments` gataient sur
   `isReference` → l'opSet ConstExpr d'un littéral d'agrégat ne foldait plus ; le chemin
   runtime de repli **perd la source constante** — trou **pré-existant** (master échoue la
   même sonde), filé **F-129**.
5. Exemption d'assignabilité des écritures indexées à travers un receveur pointeur, et
   dé-freeze des paramètres pointeurs mutables liés par l'inliner (stage 1,
   `02f1935f4`).

**Receveurs pointeur (la famille UFCS/inline, le gros de la campagne) :**
6. Receveur UFCS castless portant un symbole nu : trois chemins auto-member le prenaient
   pour une variable nommable seule → `SWC_UNREACHABLE` en codegen ou remap silencieux sur
   un paramètre de l'appelant → prédicat partagé `bindingSymbolResolvesStandalone`
   (`SemaHelpers`, `Sema.Member.Auto`, `SemaInline`).
7. Receveur de macro avec index : le clone détaché jette le substitut spec-op
   (`opIndexPtr`) sans re-sema → matérialisation du binding en préfixe
   `let` tenant l'adresse (`SemaInline materializeInlineBindings`) — l'équivalent exact de
   ce que le monde référence faisait via son cast-wrap.
8. Receveur RVALUE d'un inline homé PAR VALEUR : le temporaire migrait dans le scope
   inline, droppé à la sortie pendant que l'expression englobante consommait encore sa
   slice — la corruption sandbox-init (`Path.combine` sur buffer libéré) → le home tient
   l'ADRESSE (`materializeInlineReceiverBinding` + `forceReceiverHomeMaterialization`).
9. Route castless sur receveur `using`-path : elle s'appliquait même quand pointee ≠
   source → codegen déréférençait la valeur comme pointeur → la route exige
   pointee == source (`Match.Func applyCasts`).
10. Struct 8 octets revenu en registre : pas de `scalarStoreBits` → jamais spillé → les
    bits passaient comme `me` → spill par taille de stockage (`CodeGenCallHelpers`).
11. Receveur UFCS lvalue AVEC nœud de cast : une résolution en pause laissait un substitut
    pollué → route castless (continue) pour les lvalues (`Match.Func applyCasts`).
12. Boxing variadique d'un `const *T` : box incohérent (typeinfo du pointé + bits du
    pointeur comme données) → tailles poubelles dans `ConcatBuffer.grow` → box = pointé,
    receveur exclu des deux côtés (`assignUntypedVariadicTypeInfo` + codegen call helpers).
13. Appel qualifié explicite `Vec2.length(v)` : `me` non lié par adresse (les checks
    exigeaient un ufcsArg) → `bindsExplicitMeAddress`, tenu SÉPARÉ du ranking d'overloads
    (l'étendre à la volée avait flippé la sélection de 88 tests core — leçon retenue).
14. Const-eval d'une méthode sur receveur constant : `ConstantLower` passe désormais
    l'adresse du constant lowered ; payload pointeur passé tel quel en codegen.
15. Receveur constant en NATIF : la constante liée à `me` était lowered en octets →
    l'adresse d'un buffer du heap compilateur bakée dans le code (JIT OK, natif mort) →
    adresse du payload STATIC relogeable (`materializeDefaultConstantPayload`) —
    **pré-existant en germe**.

**Faux positifs de checks révélés par le retypage :**
16. `ptr == null` : le retry relationnel peelait le pointeur non-null vers l'`opEquals` du
    pointé, qui rejetait null (46 erreurs gui) → null reste une question d'IDENTITÉ
    (`SemaSpecOp tryResolveRelational`).
17. Checker de mutation d'itération : `for &v in volumes do v.removeBack()` (méthode de
    l'ÉLÉMENT) flaggé comme mutation structurelle du conteneur → ne flagger que si
    l'owner-struct du callee EST le type de la source itérée.

**Pré-existants purs, débusqués au passage :**
18. Zéroing d'un résultat fallible large : le storage unique du nœud `fail` servait
    l'erreur ET le résultat zéro, taillé pour l'erreur → un résultat de 512 octets écrasait
    la frame → storage au max des deux (`AstFailExpr::semaPostNode`) — **master crashe la
    même sonde**.
19. `Env.getNativeArgs` concaténait les args de la chaîne de hooks à la ligne de commande
    OS → double ligne imparsable dès la premain programme de core.dll (`dm` perdu) — côté
    `bin/runtime`, vérifié contre l'oracle master.

**Encore ouverts au moment du rapport :**
- Assert `CodeGen.Index.cpp:321` sur `richeditview.swg:217` (gui) : un IndexExpr sur
  `ArrayPtr'RichEditLine` atteint codegen sans payload spec-op — déterministe, réplique
  isolée verte, pistes dans NOTES (contexte impl d'interface / re-sema après pause).
- Narrowing `if .buffer` non retrouvé à travers un clone INLINE avec receveur pointeur :
  contourné en `string.swg:301` par `.buffer![0]` — à filer en finding si non réglé à la
  clôture (le fait le plus important à ne pas laisser mourir).

Le verdict : la transparence de `&T` ne « simplifiait » pas le compilateur — elle
court-circuitait des chemins (matérialisation de receveur, homing de temporaires, lowering
de constantes) dont l'absence était invisible tant qu'un cast-wrap les cachait. Quatre bugs
de master en sont sortis, chacun avec sa suite de non-régression (14 nouveaux fichiers de
tests, +1077 lignes).

---

## 3. Coûts résiduels chiffrés

### `dref` : +165 sites nets sur tout `bin/`

- Occurrences `dref` dans les sources `bin/` (hors `.dep/.output`) : **1413 → 1578**
  (+165 nets ; 169 lignes ajoutées, 4 retirées). `dref` préexistait largement (déréférence
  de pointeurs ordinaires) ; la campagne en ajoute ~12 %.
- Répartition qualitative des ajouts (échantillonnée sur le diff) :
  - **Écritures scalaires via binding de boucle** : `dref v += 1`, `dref jit += ...`,
    `if dref v > best[i]` — le gros contingent (examples/aoc, pixel svgparse/rendercpu,
    gui).
  - **Le motif out-param** : `var cursor = dref cursorPtr` … `defer dref cursorPtr = cursor`
    (la décision « copie locale + defer » pour les scalaires chauds) — plusieurs sites
    tools/examples ; le plus verbeux des motifs résiduels.
  - **Écritures place à travers helpers pointeur** : `dref count.ptr2(x, y, 1000) += 1`,
    `dref addrp(offset) = v` — lisibilité moyenne : le `dref` préfixe porte sur toute la
    chaîne postfixe, ce qui se lit mal à distance.
  - **Visiteurs** : `for name in dref values` (helpers de test par pointeur), déréférences
    de String de binding vers paramètres `string` via `.toString()`.
- `for &` : **241 sites** dans `bin/` — l'orthographe n'a pas changé (237 avant), seul le
  sens (adresse au lieu de référence).

### Boilerplate `opIndexPtr`

- **10 définitions** dans `bin/std/modules` : 5 conteneurs (Array, StaticArray, HashTable,
  Deque, OrderedMap) × paire const/mutable **aux corps identiques** (seule la signature
  change). S'y ajoutent `ptr1`/`ptr2` (grilles) et 7 défs `frontPtr`/`backPtr`/`peekPtr`.
- Coût en lignes NUL par rapport au monde référence : les paires remplacent en place les
  paires `opIndex -> const &T / &T` qui existaient déjà (le diff d'`array.swg` est un
  renommage ligne à ligne). Le coût réel est la **duplication const/mut** (héritée) et le
  fait que chaque conteneur écrit désormais à la main `opIndexSet`/`opIndexAssign` dont le
  corps est `dref .opIndexPtr(i) = value` (deque.swg:62-65).

### Delta de verbosité sur les fichiers représentatifs

- `bin/std` : 90 fichiers touchés, **+6 lignes nettes**. `bin/examples` : +16 nettes sur
  34 fichiers (aoc intcode réécrit sur `ptr1/ptr2/opIndexPtr` + dref). `bin/apps` et
  `tools/` : **zéro net**. La migration fonctionnelle du monde utilisateur coûte donc
  **~+22 lignes sur ~130 fichiers** — le monde pointeur n'est pas plus verbeux, il est
  plus *explicite* aux points de mutation.
- Le C++ du compilateur GROSSIT provisoirement (+531 nettes) : c'est la machinerie receveur
  pointeur (matérialisation, spill, castless) ; le stage D récupérera plusieurs centaines
  de lignes (castToReference, kind, diagnostics, disjonctions).
- Restent **409 orthographes `&T`** dans `bin/unittests` — c'est le stage E (suppression /
  réécriture planifiée), pas un coût résiduel du produit.

---

## 4. Propositions de phase 2 (ergonomie de syntaxe)

Cadre : la campagne a acheté une propriété — *toute mutation à travers une indirection est
visible au site* (`dref`, `&` à l'appel, `*T` dans la signature). Aucune proposition
ci-dessous ne doit la revendre. Les décisions arrêtées (opIndexPtr place-contexts, params
const& par valeur, #move/#fwd intacts) ne sont pas rouvertes. Quatre propositions
retenues, deux évaluées et rejetées.

### P1 — Déréférence postfixe `p.*` (retenue, priorité haute)

- **Motivation mesurée** : les motifs `dref count.ptr2(x, y, 1000) += 1` et
  `dref addrp(offset) = param0 + param1` (diff examples/tools). Le `dref` préfixe porte
  sur toute la chaîne postfixe : le lecteur doit scanner jusqu'au bout pour savoir *quoi*
  est déréférencé, et la question de précédence (`dref x.f` = `dref (x.f)`) se repose à
  chaque lecture. ~40 % des 169 `dref` ajoutés sont en fin de chaîne postfixe.
- **Syntaxe proposée** : `expr.*` comme forme postfixe strictement équivalente à
  `dref expr` — `count.ptr2(x, y, 1000).* += 1`, `addrp(offset).* = v`. `dref` préfixe
  reste valide (les deux formes coexistent, comme `!` postfixe coexiste avec les tests
  explicites de nullabilité).
- **Précédent** : Zig `ptr.*` (exactement cette grammaire, pour exactement ce problème) ;
  le `!` postfixe de Swag lui-même (l'accès notnull a déjà fait ce voyage :
  préfixe/enrobage → postfixe chaînable).
- **Impact sema/codegen** : parseur seulement — une production postfixe qui fabrique le
  même nœud de déréférence unaire ; sema/codegen inchangés ; formatter : pas d'espace,
  même rôle que `!`. Grammaire VSCode : un token.
- **Loi des sigils** : `.*` est une orthographe d'OPÉRATEUR (ensemble gelé, comme `!`),
  ni `#` ni `@` — conforme (rien de compile-time, rien d'intrinsèque). Pas de nouveau
  mot-clé nu.
- **Anti-transparence** : la déréférence reste ÉCRITE à chaque site ; on ne change que sa
  position.

### P2 — Dérivation automatique des formes valeur/écriture depuis `opIndexPtr` (retenue)

- **Motivation mesurée** : chaque conteneur écrit à la main `opIndexSet` (et parfois
  `opIndexAssign`) dont le corps canonique est `dref .opIndexPtr(index) = value`
  (deque.swg:62-65) ; et la paire const/mut d'`opIndexPtr` duplique 10 corps identiques
  sur 5 conteneurs.
- **Proposition** : quand un type définit `opIndexPtr` mutable et pas d'`opIndexSet` /
  `opIndexAssign`, le compilateur les synthétise (`dref .opIndexPtr(i) = v`,
  `dref .opIndexPtr(i) op= v`). Optionnellement, symétrique lecture : hors contexte place,
  `a[i]` en valeur se résout déjà sur `opIndexPtr` + déréférence — à documenter comme
  contrat plutôt qu'à dériver.
- **Précédent** : le compilateur génère déjà `opEquals`/`opCompare` (SemaSpecOp.Generated,
  retouché par cette campagne) ; Rust dérive `index_mut`-based `+=` via auto-deref de
  `IndexMut` ; Kotlin synthétise `a[i] op= v` depuis get/set.
- **Impact sema/codegen** : SemaSpecOp.Generated, un clone de signature + corps synthétisé
  inline ; respecte « jamais const-eval » (hérite de la décision opIndexPtr). Aucun
  changement de ranking : la forme écrite à la main gagne toujours.
- **Sigils / décisions** : aucun sigil ; renforce la décision « opIndexPtr = source de
  vérité des places ». La dérivation const-depuis-mut du couple `opIndexPtr` lui-même est
  volontairement EXCLUE (le compilateur ne peut pas prouver qu'un corps est const-sûr) —
  la duplication const/mut reste, elle est héritée du monde référence et bornée (10 défs).

### P3 — Mode de paramètre `#inout` (retenue, moyen terme, la plus structurante)

- **Motivation mesurée** : le motif décidé « scalaire chaud : copie locale + defer » est le
  résiduel le plus verbeux — `var cursor = dref cursorPtr` … `defer dref cursorPtr = cursor`
  écrit À LA MAIN à chaque site (plusieurs occurrences dans le diff examples/tools), avec
  le risque d'oublier le defer ou de publier deux fois.
- **Syntaxe proposée** : `func advance(cursor: #inout u64, ...)` ; au site d'appel,
  l'adresse reste explicite : `advance(&cursor)`. Dans le corps, `cursor` est une VALEUR
  locale ordinaire (pas de dref) ; la publication est générée à la sortie (sémantique
  copy-in/copy-out, pas aliasing garanti pendant l'appel).
- **Précédent** : Swift `inout` (copy-in/copy-out officiel, `&` requis à l'appel, PAS un
  type de première classe) ; Ada `in out`.
- **Impact sema/codegen** : ABI = `*T` (rien de neuf côté appel) ; sema retype le
  paramètre en local T dans le corps + defer synthétisé ; escape-analysis simplifiée (le
  pointeur ne fuit jamais dans le corps) ; interdiction de stocker/échapper le mode
  (ce n'est pas un type). Interaction #move : modificateurs disjoints, même famille
  grammaticale (`#move`/`#fwd`/`#inout` sur paramètre).
- **Loi des sigils** : `#` correct — instruction au COMPILATEUR sur la convention d'appel,
  aucune existence runtime (le test « existe-t-il après le compilateur ? » répond non :
  il ne reste qu'un `*T` et deux copies).
- **Anti-transparence** : la mutation reste visible à l'appel (`&cursor`) ; c'est
  l'inverse d'une référence : pas de type, pas de stockage, pas d'aliasing pendant
  l'appel. À ne proposer QUE si l'inventaire de friction post-merge confirme la densité
  du motif (T-386 le gate déjà ainsi).

### P4 — Auto-déréférence de `*T` en contexte d'assignation scalaire (ÉVALUÉE, REJETÉE)

- **La tentation** : faire que `v = x` / `v += 1` sur un binding de boucle `*T` écrive à
  travers, rendant `dref v = x` inutile — la plus grosse part des 169 sites.
- **Pourquoi c'est un non** : c'est EXACTEMENT la transparence que la campagne vient de
  retirer, réintroduite au pire endroit — `=` changerait de sens selon le type de
  l'opérande gauche, et un nom redeviendrait « une valeur qui est secrètement une
  adresse ». La variante « seulement pour les bindings de boucle » est pire : elle crée
  une SECONDE espèce de nom à sémantique référence, non déclarée par un type, exactement
  le genre de cas spécial que les ~18 défauts de la section 2 ont coûté à débusquer
  (chaque « le binding est spécial » était une porte isReference). Précédent à charge :
  Rust, qui a des bindings `&mut` partout, garde `*v += 1` — et vit très bien ; C# avec
  ses `ref` locals transparents est le contre-exemple (write-through invisible).
- **Le vrai remède** aux sites concernés, c'est P1 (`v.* += 1`, 3 caractères, mutation
  toujours écrite).

### P5 — `&` implicite pour les paramètres `*T` ordinaires (ÉVALUÉE, REJETÉE)

- **La tentation** : puisque le receveur se lie tout seul par adresse (`v.length()` ET
  `Vec2.length(v)` depuis `bindsExplicitMeAddress`), étendre aux paramètres `*T`
  quelconques : `sort(arr)` au lieu de `sort(&arr)`.
- **Pourquoi c'est un non** : le `&` au site d'appel est l'information que la campagne
  voulait rendre visible — « cette fonction peut muter ça ». Rust impose `&mut v` à
  l'appel pour cette raison précise. Et la leçon est déjà MESURÉE dans cette campagne :
  étendre `allowsImplicitAddressBinding` à la volée a flippé la sélection d'overloads de
  88 tests core (commit 851efe9ff) — le ranking est sensible à toute liaison implicite
  nouvelle. La doctrine reste : liaison d'adresse implicite = RECEVEUR uniquement
  (`me`), où la convention objet la rend attendue ; tout autre paramètre pointeur se
  prend une adresse explicite.

### P6 — Complément documentaire (retenue, coût nul)

- Documenter comme CONTRAT du langage les deux asymétries que la campagne a créées et que
  les propositions ci-dessus n'effacent pas : (a) lecture d'élément `a[i]` en valeur hors
  place-context passe par `opIndexPtr` + déréférence implicite DE LECTURE (jamais
  d'écriture implicite) ; (b) `for v` sur structs lie `const *T` — l'accès membre `v.f`
  peel le pointeur, seule l'écriture scalaire exige `dref`/`.*`. C'est le stage F
  (004_007/005_003/006_005 réécrits) ; la phase 2 n'a qu'à tenir ces textes à jour si P1
  ou P2 atterrissent.

**Ordre suggéré** : P1 (pur parseur, gain immédiat sur les sites les plus laids), P2
(SemaSpecOp.Generated, machinerie existante), P6 (avec le stage F), puis P3 seulement après
l'inventaire de friction post-merge (T-386).

---

## 5. État de l'échelle de validation au moment du rapport

- `std.swgs dm test core` : **576 passed** (JIT + natif) — VERT.
- `std.swgs dm test pixel` : **361 passed** — VERT.
- `std.swgs dm test gui` : compile (sema OK), **BLOQUÉ en codegen** sur
  `CodeGen.Index.cpp:321` (richeditview.swg:217) — voir section 2, item ouvert.
- Sondes `.campaign/probe1-9` : 14/14 vertes (JIT + natif). Build DevMode n° 52.
- `tools\tests.swgs dm` (échelle complète) : **[PLACEHOLDER — METTRE À JOUR AVANT MERGE :
  statut final de `tools\tests.swgs dm` sur le binaire DevMode à jour, + rappel que
  `--all-cfg` et l'échelle Release restent la porte de l'utilisateur]**.
- Stages restants à l'écriture de ce brouillon : A (rejet parseur `&T`), D (suppression du
  kind), E (unittests, 409 orthographes `&T` restantes), F (doc/VSCode/skills), G
  (backlog T-386/F-129+, suppression `.campaign/`, régénération `web/language.html`).
