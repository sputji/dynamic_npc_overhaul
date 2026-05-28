🎮 Checklist de re-test en jeu — v0.0.13

Avant : redemarrer completement PZ, nouvelle sandbox Apocalypse, debug menu actif.

1. Suivi / recrutement
  [ ] Le NPC garde ~2 tuiles d'ecart quand le joueur s'arrete (pas de collage)
  [ ] Marche/cours bascule proprement sans micro-saccades
  [ ] Changement de direction joueur reste fluide

2. Ordres de deplacement
  [ ] "Va la-bas" atteint la cible sans derive continue
  [ ] "Mets-toi a l'abri" rejoint un batiment proche sans aller-retour
  [ ] Pas d'erreur rouge `ClimbOverFenceState` liee au NPC durant ces ordres

3. Combat / equipement
  [ ] Le NPC equipe la meilleure arme melee disponible (si inventaire mixte)
  [ ] Le combat reste stable (pas de spam erreur rouge cote PHNPC)

4. Inventaire / tenue / mort
  [ ] Vetements donnes au NPC se portent automatiquement (si slot libre)
  [ ] Les armes donnees (main primaire/secondaire) sont presentes dans le cadavre
  [ ] Le contenu du cadavre affiche bien inventaire + vetements + armes

5. Validation console
  [ ] Aucune erreur ROUGE reliee a PHNPC au demarrage
  [ ] Aucune erreur ROUGE reliee a PHNPC apres 5 min de jeu actif

6. Validation v0.0.13b
  [ ] Donner 2+ vetements du meme slot (ex: veste faible puis veste forte) -> NPC porte le meilleur score
  [ ] Ordre "Va la-bas" avec clotures proches -> pas de boucle d'erreur `ClimbOverFenceState`
  [ ] Ordre "Mets-toi a l'abri" zone avec clotures -> pas de spam erreurs rouges fence

---

🎮 Checklist de tests en jeu — v0.0.12
Avant : Redémarrer complètement PZ (pas juste reload mod) pour purger le KahluaThread. Charger une sandbox neuve (Apocalypse par défaut).

1. Chargement du mod
  [✅]Aucune erreur ROUGE dans console.txt au démarrage
  [✅]Bannière [PHNPC] Enforce v0.0.9p loaded visible dans console
  [ ]Les 8 overrides XML (windowlunge, falldown, defaultlunge, door, doorbang, doorclaw) chargent
  [✅]Traductions FR : menu clic-droit affiche du français (pas UI_PHNPC_... brut)
2. Spawn NPC (sandbox, debug ON conseillé)
  [✅]Menu DEBUG_PHNPC → spawn at player → un zombie apparaît
  [✅]Le « zombie » a une vraie tenue (pas la tenue zombie déchirée)
  [✅]Il ne mord pas quand le joueur s'approche
  [✅]Il ne devient pas invisible quand frappé
  [⚠️]Animation idle = Bob_Idle (homme) ou Kate_Idle (femme), bras le long du corps (PAS bras tendus zombie) : A encore la posture de zombie, pas de idle humain
3. Recrutement + suivi (le plus critique)
  [✅]Clic droit sur NPC → « Recruter » → bark de confirmation
  [✅]Joueur marche → NPC suit en marchant sans saccades
  [✅]Joueur court loin (>6 tuiles) → NPC passe en course automatiquement : Le NPC/PNJ passe bien en course quand le joueur est loin (>6 tuiles), il s'arrete bien à ~3 tuiles du joueur, pas de coller mais quand il repasse en marche il continue a sacader et coller toujours le joueur même quand il s'arrête.
  [❌]Joueur s'arrête → NPC s'arrête à ~2 tuiles, pas collé : Continue de coller le joueur.
  [✅]Joueur change de direction brutalement → pas de saccade sur le NPC (fix v0.0.9o) : Fonctionnele le NPC/PNJ ne sacade pas quand le joueur change de direction brutalement, il suit le joueur de manière fluide même quand il change de direction.
1. Ordres de déplacement
  [❌]« Va là-bas » (clic carte) → curseur de drag → NPC pathfind jusqu'au point sans s'arrêter en route : Ne fonctione pas du tous, part dans la direction bas gauche, ne s'arrte jamais sauf si gros obstacle qui le bloque. Voir log pour les erreurs.
  [❌]« Va là-bas » à travers une porte fermée → NPC ouvre la porte (silencieusement, pas de crash) : Le NPC/PNJ ne va pas sur la positions demander. Voir log pour les erreurs.
  [❌]« Mets-toi à l'abri » → NPC court vers un bâtiment proche et s'arrête dedans : Le NPC/PNJ ne vas pas dans le batiement le plus proche pour se mettre a l'abri, il cours et fait des allez retrour entre le joueur et une position inconu aleatoire. Voir log pour les erreurs.
  [⚠️]« Reste ici » → NPC patrouille dans un rayon ~5 tuiles autour du point : Il patrouille bien dans un rayon de 5 tuiles autour du point donner. Voir log pour les erreurs.
  [✅]« Sois libre » → NPC erre autonomement mais reste dans l'équipe
  [✅]« Quitte l'équipe » → NPC libéré, retour en patrouille passive
1. Combat NPC vs zombies
  [✅]Spawn quelques zombies à proximité → NPC engage automatiquement : Fonctionne mais crash voir log pour les erreurs.
  [✅]NPC se tourne vers la cible (faceLocationF) avant de frapper : Fonctionne mais crash voir log pour les erreurs.
  [✅]Le zombie reçoit knockDown(true) + perd 25 HP par hit : Fonctionne mais crash voir log pour les erreurs.
  [✅]Le zombie meurt et ne se relève pas (cycle setHealth(0) après clear de PHNPC_IsNPC)
  [⚠️]NPC ne s'attaque jamais lui-même ou un autre NPC (tmd.PHNPC_IsNPC check) : Fonctionne, le NPC/PNJ ne s'attaque pas lui même ou les autres NPC/PNJ, mais on vas faire une evolutions plus tard.
  [⚠️]Si NPC a une arme dans l'inventaire (Base.Bat, Base.Axe, Base.Knife...) elle est équipée : Fonctionne il prend bien une arme de sont inventaire pour frapper les zombies, mais il prend pas la meilleure arme disponible (hache > batte > couteau).
1. Fuite quand blessé
  [✅]Frapper son propre NPC (autoriser PvP) → HP descend
  [⚠️]À <30% HP → bark UI_PHNPC_FleeHurt + NPC fuit : Le NPC/PNJ fuit bien quand il est à moins de 30% de sa vie, mais il pousse en boucle le joueur. Voir log pour les erreurs.
  [⚠️]Direction de fuite opposée aux zombies + se rapproche du joueur : Le NPC/PNJ fuit bien quand il est à moins de 30% de sa vie, mais il pousse en boucle le joueur. Voir log pour les erreurs.
1. Mort + loot
  [✅]Tuer un NPC (frapper jusqu'à HP=0)
  [✅]Cadavre apparaît au sol
  [⚠️]Clic droit cadavre → Examiner → contenu contient ses items + vêtements : Il y a bien le cadavre au sol et on peut cliquer droit dessus pour examiner son contenu, il n'y a les items et les vêtements du NPC/PNJ dans le cadavre, mais il n'y a pas les armes que je lui est donner dans son inventaire. Voir log pour les erreurs.zd
  [⚠️]Logs [PHNPC][Loot] dans console signalent le transfert vers body:getContainer() : A controler dans console.txt.
  [⚠️]Fallback : si pas de cadavre après 120 ticks, items au sol (test edge case explosion) : Pas tester car le cadavre est bien la.
1. Portes / fenêtres (fix v0.0.9o)
  [✅]NPC traverse une porte fermée pendant le suivi → ouverture silencieuse, pas de NPE : Le NPC/PNJ ouvre bien les portes et les fenetres mais ne les referme pas appres sont passage, Je n'ai pas l'impresions qu'il cherche le meilleur chemin pour traverser les portes ou les fenetres et obstacles.
  [✅]NPC ne casse pas les portes (pas de pounding zombie) : fonctionne il casse les portes ou les fenetres si fermer, sinon il les ouvre simplement pour les traverser.
  [❌]Fenêtre fermée sur le chemin → NPC l'ouvre (pattern Bandits ZAOpenWindow) : Ne fonctionne plus, il ne ferme plus les fenêtres et les portes derriere lui.
  [⚠️]console.txt ne contient AUCUN ToggleDoor / isLocalPlayer null pointer : A controler dans console.txt.
1. Danger module (NPC attire les zombies)
  [✅]Quand NPC combat ou court → zombies dans 15 tuiles l'aggro lui (pas le joueur) : Fonctionne les zombies aggro bien le NPC/PNJ quand il combat ou court, même si le joueur est à proximité, les zombies aggros le personnege Joueur/NPC/PNJ le plus proche de eux. Parfait!
  [✅]Quand NPC marche calmement → reste discret : Fonctionne tres bien.
  [✅]Spawn 5-10 NPC simultanés → joueur bouge, 0 saccade : Le jeu ne saccade pas même avec 5-15 NPC/PNJ simultanés, le pcall ne dégrade pas perceptiblement les performances.
  [✅]Laisser tourner 5 minutes sans intervention → console.txt reste propre : A controler dans console.txt, il y des erreurs ou de warnings liés à PHNPC.
  [✅]FPS stable (le pcall ne dégrade pas perceptiblement) : Le jeu ne saccade pas même avec 5-15 NPC/PNJ simultanés, le pcall ne dégrade pas perceptiblement les performances. Pour le moment
1.  Knockdown / falldown (fix T-pose v0.0.9i + hardening v0.0.9p)
  [✅]Pousser violemment un NPC → il tombe puis se relève sans T-pose : Fonctionne, le NPC/PNJ tombe bien quand il est poussé violemment et se relève sans T-pose, il a une animation de chute et de relève fluide. Mais quand il colle le joueur il garde la posture de zombie et il n'a pas d'animation de idle humain.
  [⚠️]Les variables BumpFall/OnTheFloor sont reset (vérifiable dans getModData) : A controler dans console.txt, les variables BumpFall/OnTheFloor sont bien reset dans getModData après la chute.
1.  Inventaire NPC
  [✅]Clic droit NPC → « Inventaire » → fenêtre s'ouvre, items transférables : Oui on voit l'inventaire du NPC/PNJ et on peut transférer les items entre l'inventaire du joueur et celui du NPC/PNJ.
  [✅]Donner une arme → le NPC l'utilise en combat (test #5) : Fonctionne il prend bien une arme de sont inventaire pour frapper les zombies, mais il prend pas la meilleure arme disponible (Stat dega armes).
  [❌]Donner des vêtements → le NPC les porte (test #5) : Non il ne portes pas les vêtements que je lui est donner dans son inventaire, il garde sa tenue de base même si je lui donne des vêtements dans son inventaire. Voir log pour les erreurs.
1.  Bugs divers
  [✅]NPC ne devient pas invisible quand frappé : Oui, le NPC/PNJ ne devient pas invisible quand il est frappé, il garde sa tenue de base même s'il est frappé.
  [⚠️]Animation idle = Bob_Idle (homme) ou Kate_Idle (femme), bras le long du corps (PAS bras tendus zombie) : A encore la posture de zombie, pas de idle humain, il garde la posture de zombie même s'il est recruté et qu'il suit le joueur.
  [✅]NPC ne mord pas quand le joueur s'approche : Oui, le NPC/PNJ ne mord pas quand le joueur s'approche, il garde sa tenue de base même s'il est approché par le joueur.
  [❌]Erreur ROUGE dans console.txt : Oui, il y a des erreur rouge dans console.txt.



🎮 Checklist de tests en jeu — v0.0.11
P0 version 0.0.11 : Amélioration du pathfinding, des animations de combat, et des interactions avec les portes/fenêtres.

1. Recrutement + s'éloigner (>6 tuiles) → NPC doit **courir** sans saccade, s'arrêter à ~3 tuiles, pas de coller. [❌] : Ne cours quand le joueur est loin (>6 tuiles) il marche, le NOC/PNJ n'arrivent pas a courir il y a un debut d'annimations de course et il arrete pour marcher et il ne s'arrête pas à ~3 tuiles, il continue de coller le joueur même quand il s'arrête.
2. "Va là-bas" → arriver à destination → **rester immobile** (pas de patrouille aléatoire). [❌] : Ne fonctione plus du tous, part dans une direction aléatoire, ne s'arrte jamais sauf si gros obstacle.
3. "Reste ici" → patrouille libre dans rayon 5 (`NoPatrol` reseté à `nil` à l'ordre). [❌] :Fonctionne mais le NPC/PNJ continue a revenir ver le joueur apres avoir patrouiller dans le rayon de 5 tuiles, ils ne reste pas en patrouille.
4. "Mets-toi à l'abri" → trouve une room, marche **directement** (pas de boucle), referme la porte derrière lui UNE FOIS à l'arrivée. [❌] : Ne fonctionne pas, le NPC/PNJ ne vas pas dans le batiement le plus proche pour se mettre a l'abri, il cours et fait des allez retrour entre le joueur et une position inconu aleatoire. Il ne referme pas les portes derriere lui.
5. Combat → NPC équipe sa meilleure arme (hache > batte si les deux présentes). [❌] : Non, le NPC/PNJ n'équipe pas les armes qu'il a dans son inventaire, Gros bug. voir log
6. Aucun message `ERROR` dans console.txt lié au mod. [❌] : Il y a des erreurs liées au mod dans console.txt.