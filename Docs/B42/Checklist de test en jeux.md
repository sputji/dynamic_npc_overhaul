🎮 Checklist de re-test en jeu — v0.0.17

Avant :
- redemarrer completement PZ,
- copier la version repo vers `C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul`,
- verifier dans `console.txt` les banners `v0.0.17 loaded` (Main/Manager/Actions/Barks/Combat/Inventory/Outfits/Pathfinding/Health/Loot).

1. Stabilite runtime
  [ ] Aucune erreur rouge PHNPC repetitive au demarrage (plus de boucle line 118/135 de Update).
  [ ] Aucune erreur rouge PHNPC apres 5 minutes avec 5+ NPC recrutes.

2. Suivi / recrutement
  [ ] Le NPC garde ~2 tuiles d'ecart a l'arret (pas de collage joueur).
  [ ] Plus de micro-saccades marche/course (plus de spam `follow anchor` toutes les secondes).
  [ ] Changement de direction joueur fluide sans reset de path visible.
  [ ] Franchissement portes/fenetres/clotures sans blocage milieu animation.

3. Armes a feu
  [ ] NPC avec arme a feu + munitions + Aiming>=1 tire a distance (<=10 tuiles).
  [ ] Cooldown de tir respecte (pas de rafale continue).
  [ ] NPC sans munitions ne tire pas et repasse melee.
  [ ] NPC avec Aiming=0 n'utilise pas les armes a feu.

4. Progression XP / competences
  [ ] `getSkillSummary(npc)` affiche 13 competences (meme niveau 0).
  [ ] Apres combat, l'XP evolue (Aiming/Blunt/Strength/Fitness/Maintenance).
  [ ] Montee de niveau declenche un bark levelup visible.

5. Vetements / Outfits
  [ ] Vetements donnes sont equipes automatiquement (`onItemGiven`).
  [ ] Si un vetement meilleur est donne sur meme slot, il remplace l'ancien.
  [ ] Le score defensif est visible en debug (`OutfitDef`).

6. Barks meteo
  [ ] Par pluie : BarkRain1-3.
  [ ] Par orage : BarkStorm1-3.
  [ ] Par froid/neige : BarkSnow1-3.
  [ ] Par canicule (>35 C) : BarkHot1-2.
  [ ] Par brouillard dense : BarkFog1-2.

---

🎮 Checklist de re-test en jeu — v0.0.16

Avant :
- redemarrer completement PZ,
- copier la version repo vers `C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul`,
- verifier dans `console.txt` les banners `v0.0.16 loaded` (Main/Actions/Barks/Combat/Inventory/Outfits/Pathfinding/Health/Loot).

1. Suivi / recrutement
  [❌] Le NPC garde ~2 tuiles d'ecart a l'arret, sans collage. colle toujours le joueur.
  [❌] Plus de micro-saccades marche/course (pas de spam re-path toutes les secondes). Toujours des micro-saccades quand le NPC/PNJ Cours et marche, log montre un calcul a chaque secondes se qui fait les sacades il faut corriger cela !.
  [❌] Changement de direction joueur fluide. toujours des micro-saccades quand le NPC/PNJ Cours et marche, log montre un calcul a chaque secondes se qui fait les sacades il faut corriger cela !.
  [❌] Franchissement portes/fenetres/clotures sans blocage (pathToLocationF natif). ne fonctionne pas, le NPC/PNJ ne passe plus les barieres ou obstacles bas, il commance sont annimation pour passer de l'autres coter et reste bloqué au milieu. Voir log pour les erreurs.

2. Armes a feu
  [❌] NPC equipe une arme a feu si elle est dans son inventaire avec des munitions. Utilise toujours les armes a contendante meme si il a une arme a feux avec un carton de munitions dans son inventaire. voir log pour les erreurs.
  [❌] NPC tire sur les zombies a distance (<= 10 tuiles) et respecte le cooldown. : Non, le NPC/PNJ n'utilise pas les armes a feu pour tirer sur les zombies même s'il en a dans son inventaire avec des munitions, il utilise toujours les armes a contendante. voir log pour les erreurs.
  [❌] NPC sans munitions ne tente pas de tirer (reste en corps a corps).
  [❌] NPC avec niveau Aiming = 0 n'utilise pas les armes a feu.

3. Progression XP / competences
  [❌] `getSkillSummary(npc)` dans la console debug affiche les 13 competences.
  [❌] Apres combat, l'XP augmente (verifiable via console debug).
  [❌] Montee de niveau declenche un bark levelup visible.

4. Vetements / Outfits
  [❌] Vetements donnes portent automatiquement (appel onItemGiven).
  [❌] Si le NPC a deja un vetement de score inferieur, il l'echange pour le meilleur.
  [❌] Score defensif visible pour differents types de vetements.

5. Barks meteo
  [❌] Par temps de pluie : NPC dit une phrase sur la pluie (BarkRain1-3).
  [❌] Par orage intense : NPC dit une phrase sur l'orage (BarkStorm1-3).
  [❌] Par temps froid/neige : NPC dit une phrase sur la neige (BarkSnow1-3).
  [❌] Par canicule (>35 C) : NPC dit une phrase sur la chaleur (BarkHot1-2).
  [❌] Par brouillard dense : NPC dit une phrase sur le brouillard (BarkFog1-2).

1. Stabilite / console
  [ ] Banners `v0.0.16 loaded` visibles pour Main/Manager/Actions/Barks/Combat/Inventory/Outfits/Pathfinding.
  [❌] Aucune erreur rouge PHNPC au demarrage.
  [❌] Aucune erreur rouge PHNPC apres 5 minutes de jeu actif.
  [✅] FPS stable avec 5+ NPC simultanes.

---

🎮 Checklist de re-test en jeu — v0.0.15

Avant :
- redemarrer completement PZ,
- copier la version repo vers `C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul`,
- verifier dans `console.txt` les banners `v0.0.15 loaded` (Actions/Enforce/Update/Combat/Inventory/Health/Loot).

1. Suivi / recrutement
  [❌] Le NPC garde ~2 tuiles d'ecart a l'arret, sans collage.
  [❌] Plus de micro-saccades marche/course (pas de spam re-path toutes les secondes).
  [❌] Changement de direction joueur fluide.
  [❌] Franchissement clotures/obstacles bas sans blocage animation.

1. Ordres de deplacement
  [❌] "Va la-bas" atteint la cible puis reste en surveillance zone (pas de retour joueur).
  [❌] "Mets-toi a l'abri" entre dans un batiment et bascule en `staying` sans sortir.
  [❌] En zone cloturee : pas de boucle `ClimbOverFenceState`.

1. Combat / equipement
  [❌] Combat stable sans erreurs rouges PHNPC.
  [❌] Le NPC garde le verrou d'ordre `goingto/shelter` en presence de zombies.

1. Inventaire / tenue / mort
  [❌] Vetements donnes au NPC portes automatiquement (slot libre/remplacement meilleur score).
  [❌] Armes donnees visibles dans le cadavre apres mort.
  [❌] Contenu cadavre coherent (inventaire + vetements + armes).

1. Validation console
  [❌] Banners modules `v0.0.15 loaded` visibles.
  [❌] Aucune erreur rouge PHNPC au demarrage.
  [❌] Aucune erreur rouge PHNPC apres 5 minutes de jeu actif.

---

🎮 Checklist de re-test en jeu — v0.0.14

Avant : redemarrer completement PZ, nouvelle sandbox Apocalypse, debug menu actif.

1. Suivi / recrutement
  [❌] Le NPC garde ~2 tuiles d'ecart quand le joueur s'arrete (pas de collage) : Continue de coller le joueur.
  [❌] Marche/cours bascule proprement sans micro-saccades (plus de spam `follow anchor` en log) : Fonctionne mais toujour des micro-saccades quand le NPC/PNJ Cours et marche, log montre un calcul a chaque secondes se qui fait les sacades il faut corriger cela !.
  [✅] Changement de direction joueur reste fluide : Fonctionne
  [❌] Franchissement d'obstacles bas/clotures fonctionne sans blocage animation : Ne fonctionne pas, le NPC/PNJ se bloque lorsqu'il tente de franchir des obstacles bas ou des clôtures.

1. Ordres de deplacement
  [✅] "Va la-bas" atteint la cible sans derive continue et sans retour auto vers le joueur : Fonctionne et reste en surveillance sur la zone.
  [❌] "Mets-toi a l'abri" rejoint un batiment proche et reste en staying (pas d'aller-retour) : Ne fonctionne pas, rentre pas les batiment tape les mur et reviens vers le joueur, il ne reste pas en staying dans le batiment.
  [❌] Zone avec clotures : pas de boucle d'etat `ClimbOverFenceState` : Ne Fonctionne pas, le NPC/PNJ ne passe plus les barieres ou obstacles bas, il commance sont annimation pour passer de l'autres coter et reste bloqué au milieu. Voir log pour les erreurs.

1. Combat / equipement
  [✅] Le NPC equipe la meilleure arme melee disponible (inventaire mixte) : Fonctionne
  [❌] Le combat reste stable (pas de spam erreur rouge cote PHNPC) : Ne fonctionne pas, Crash, il y a des erreurs rouges dans le log.

1. Inventaire / tenue / mort
  [❌] Vetements donnes au NPC se portent automatiquement (slot libre ou remplacement meilleur score) : Ne fonctionne pas il ne portes pas les vêtements que je lui est donner dans son inventaire même si il n'a pas de vêtement, il garde sa tenue de base même si je lui donne des vêtements dans son inventaire. Voir log pour les erreurs.
  [❌] Les armes donnees au NPC sont presentes dans le cadavre apres mort : non ne fonctionne pas, juste les items quand le NPC/PNJ spawn. 
  [❌] Le contenu du cadavre affiche inventaire + vetements + armes : non ne fonctionne pas, juste les items quand le NPC/PNJ spawn. 

1. Validation console
  [⚠️] Banners `v0.0.14 loaded` visibles pour Actions/Enforce/Update/Combat/Inventory/Health/Loot
  [❌] Aucune erreur rouge PHNPC au demarrage : Il y a des erreurs rouges a voir dans le log.
  [❌] Aucune erreur rouge PHNPC apres 5 minutes de jeu actif

ACTIONS a Faire :
- Corriger les micro-saccades du suivi marche/course (log `follow anchor`). : Arreter le calcul de la distance au joueur a chaque secondes, faire un calcul plus intelligent pour basculer entre marche et course sans saccade.
- Corriger le franchissement d'obstacles bas/clotures qui bloque le NPC/PNJ : Le NPC/PNJ ne passe plus les barieres ou obstacles bas, il commance sont annimation pour passer de l'autres coter et reste bloqué au milieu. Il faut corriger cela pour que le NPC/PNJ puisse franchir les obstacles bas/clotures sans se bloquer.
- Corriger les ordres de déplacement "Va la-bas" et "Mets-toi a l'abri" pour qu'ils fonctionnent correctement : "Va la-bas" doit atteindre la cible sans derive continue et sans retour auto vers le joueur et ce mettre en surveillance sur la zone, "Mets-toi a l'abri" doit rejoindre un batiment proche et rester en staying (pas d'aller-retour) doit rester dans le batiment refermer les portes et fenettres pour rester a l'abri ne doit pas sortire du batiment.
- Corriger les erreurs rouges dans le log liées au combat et à l'inventaire : Il y a des erreurs rouges dans le log liées au combat et à l'inventaire, il faut les corriger pour que le combat reste stable et que l'inventaire fonctionne correctement.
- Corriger le port automatique des vêtements donnés au NPC : Le NPC/PNJ ne portes pas les vêtements que je lui est donner dans son inventaire même si il n'a pas de vêtement, il garde sa tenue de base même si je lui donne des vêtements dans son inventaire. Il faut corriger cela pour que le NPC/PNJ porte automatiquement les vêtements donnés par le joueur si le slot est libre ou pour remplacer un vêtement de score inférieur.
- Corriger le loot des armes dans le cadavre du NPC : Les armes que je lui donne dans son inventaire ne sont pas présentes dans le cadavre après la mort du NPC/PNJ, il y a juste les items et les vêtements par defaut au spawn du NPC/PNJ dans le cadavre. Il faut corriger cela pour que les armes données au NPC soient présentes dans le cadavre après sa mort.


---

🎮 Checklist de re-test en jeu — v0.0.13

Avant : redemarrer completement PZ, nouvelle sandbox Apocalypse, debug menu actif.

1. Suivi / recrutement
  [⚠️] Le NPC garde ~2 tuiles d'ecart quand le joueur s'arrete (pas de collage) : Le NPC/PNJ continue de coller le joueur.
  [❌] Marche/cours bascule proprement sans micro-saccades : micro-saccades quand le NPC/PNJ Cours et marche, log montre un calcul a chaque secondes se qui fait les sacades.
  [✅] Changement de direction joueur reste fluide : Les changement de direction du joueur sont fluide, le NPC/PNJ suit le joueur de manière fluide même quand il change de direction.
  [❌] Le NPC/PNJ ne passe plus les barieres ou obstacles bas : GROS BUG, le NPC/PNJ ne passe plus les barieres ou obstacles bas, il commance sont annimation pour passer de l'autres coter et reste bloqué au milieu.

1. Ordres de deplacement
  [❌] "Va la-bas" atteint la cible sans derive continue : Le NPC cours en direction de la cible mais ne l'atteint jamais, il sacade pour y allez (log montre un calcul a chaque secondes se qui fait les sacades) et quand il arrive a proximite de la cible il fait demi-tour pour revenir sur le joueur
  [❌] "Mets-toi a l'abri" rejoint un batiment proche sans aller-retour : Le NPC/PNJ vas dans le batiement le plus proche pour se mettre a l'abri, il ouvre la porte rentre et resort directment pour revenir sur le joueur.
  [✅] Pas d'erreur rouge `ClimbOverFenceState` liee au NPC durant ces ordres : Je n'ai pas vu d'erreur `ClimbOverFenceState` dans le log pendant les tests de déplacement.

1. Combat / equipement
  [✅] Le NPC equipe la meilleure arme melee disponible (si inventaire mixte)
  [✅] Le combat reste stable (pas de spam erreur rouge cote PHNPC) : Les deplacement sont plutot aleatoir mais le combat reste stable.

1. Inventaire / tenue / mort
  [❌] Vetements donnes au NPC se portent automatiquement (si slot libre) : Non il ne portes pas les vêtements que je lui est donner dans son inventaire même si il n'a pas de vêtement, il garde sa tenue de base même si je lui donne des vêtements dans son inventaire. Voir log pour les erreurs.
  [❌] Les armes donnees (main primaire/secondaire) sont presentes dans le cadavre : Non il n'y a pas les armes que je lui est donner dans son inventaire dans le cadavre, il y a juste les items et les vêtements du NPC/PNJ dans le cadavre. Voir log pour les erreurs.
  [⚠️] Le contenu du cadavre affiche bien inventaire + vetements + armes : Quand il spawn avec oui mais ce que je lui donne disparer la mort.

1. Validation console
  [⚠️] Aucune erreur ROUGE reliee a PHNPC au demarrage
  [⚠️] Aucune erreur ROUGE reliee a PHNPC apres 5 min de jeu actif

1. Validation v0.0.13b
  [❌] Donner 2+ vetements du meme slot (ex: veste faible puis veste forte) -> NPC porte le meilleur score : Non il ne portes pas les vetements que je lui est donner dans son inven
  [❌] Ordre "Va la-bas" avec clotures proches -> pas de boucle d'erreur `ClimbOverFenceState` : Non le NPC/PNJ ne passe plus les barieres ou obstacles bas, il commance sont annimation pour passer de l'autres coter et reste bloqué au milieu. Voir log pour les erreurs.
  [❌] Ordre "Mets-toi a l'abri" zone avec clotures -> pas de spam erreurs rouges fence : Non le NPC/PNJ vas dans le batiement le plus proche pour se mettre a l'abri, il ouvre la porte rentre et resort directment pour revenir sur le joueur sans refermer la porte derriere lui. Voir log pour les erreurs.

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