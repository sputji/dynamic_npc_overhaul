**Phase 1 : Bilan de l'existant (Ce que ton mod fait aujourd'hui sur la B41)**

Le Cerveau (AI Decision Engine) : Une boucle de ~33ms qui calcule les besoins (faim, soif, moral) et exécute des machines à états finis (FSM) pour 6 ordres principaux (Étudier, Construire, Cuisiner, Commercer, Défendre, Garder).

Le Dialogue IA : Un pont HTTP asynchrone vers Ollama, soutenu par un système de fallback intelligent (16+ réponses contextuelles) et multilingue.

Le Métier : 5 professions (Artisan, Cuisinier, Bâtisseur, Marchand, Explorateur) avec des cycles de production et de consommation réels.

La Survie et Psychologie : Un système de morsure cachée (avec toux et anxiété), des traumas de type PTSD (gel/rage), et l'impact de la météo.

L'Apprentissage : Une observation passive où les PNJ gagnent de l'XP en regardant le joueur agir.

Le Réseau (Dispatcher v1.0.5) : Une séparation stricte entre le mode SOLO (0 overhead réseau) et MULTI (synchronisation via transmitModData toutes les 5 secondes).


**Phase 2 : Feuille de route pour la Build 42**

Étape 1 : Nettoyage et R&D (Environnement B42)

Archiver le vieux code : Mets de côté tout ce qui concerne NPCSpawner_SOLO.lua, NPCSpawner_MULTI.lua, et tes hooks de pathfinding personnalisés.

Étudier l'API Animale : Télécharge un mod ou regarde le code source de la B42 concernant les animaux (cerfs, vaches). Identifie comment le jeu instancie ces entités, gère leurs groupes, et utilise les nouveaux arbres de comportement (Behavior Trees).

Migrer la Configuration : Supprime ton ModOptionsEngine.lua embarqué et recrée tes paramètres (Profils, URL Ollama, etc.) en utilisant l'UI native de configuration de mods de la B42.

Étape 2 : Le "Nouveau Corps" (Fondations et Mouvement)

Instanciation Native : Crée ta nouvelle entité PNJ en te basant sur l'architecture des animaux de la B42, mais en lui appliquant un modèle visuel humain et un inventaire.

Pathfinding Natif : Connecte les ordres de déplacement de ton mod aux nouvelles fonctions de pathfinding du jeu. Laisse le moteur gérer les collisions et l'évitement d'obstacles.

Test de Stabilité : Fais spawner un PNJ "coquille vide" et vérifie qu'il peut se déplacer sans générer d'erreurs d'affichage (adieu les crashs IsoFallingClothing).

Étape 3 : Greffe du Cerveau (Logique et FSM)

Réintégration de NPCBrain.lua : Connecte ton moteur de décision (calcul des besoins à 33ms) à la nouvelle entité.

Traduction des Ordres : Convertis tes anciens ordres FSM (Garder, Défendre, Construire) pour qu'ils pilotent les nouvelles animations et actions de la B42.

Test des Métiers : Réactive tes 5 professions et vérifie que la production et l'échange d'objets fonctionnent avec la nouvelle gestion d'inventaire.

Étape 4 : Le Multijoueur et l'UI (Le grand test)

Synchronisation Native : Observe comment la B42 synchronise les animaux en multijoueur. Remplace tes appels intensifs à transmitModData par le système réseau natif des entités non-joueuses (ce qui devrait réduire tes lags).

Refonte de l'Interface : Réécris ton NPC_UI.lua et OllamaChatUI.lua pour t'assurer que les clics droits et les fenêtres s'affichent correctement avec le nouveau moteur de rendu.

Étape 5 : Réintégration des systèmes avancés (La surcouche)

Le pont Ollama : Réintègre OllamaBridge.lua. Comme c'est du HTTP pur, cela devrait fonctionner presque sans modification.

Survie et Apprentissage : Réactive le système de morsure cachée, l'apprentissage passif et la gestion des traumas.

Commandes Admin : Remets en place tes commandes /phnpc pour faciliter le débogage final.