--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCDialogueLocalization.lua

    Registre centralise des cles IGUI pour les dialogues fallback.
    Utilise getText() si la cle existe, sinon fallback FR/EN embarque.
]]

local NPCDialogueLocalization = {
    entries = {
        IGUI_PHNPC_FALLBACK_GENERIC_1 = { fr = "Ouais, euh... on va voir.", en = "Yeah, uh... we'll see." },
        IGUI_PHNPC_FALLBACK_GENERIC_2 = { fr = "C'est une bonne question.", en = "That's a good question." },
        IGUI_PHNPC_FALLBACK_GENERIC_3 = { fr = "Je ne sais pas vraiment comment repondre a ca.", en = "I don't really know how to answer that." },
        IGUI_PHNPC_FALLBACK_GENERIC_4 = { fr = "Ecoute, je suis trop fatigue pour ca maintenant.", en = "Look, I'm too tired for this right now." },
        IGUI_PHNPC_FALLBACK_GENERIC_5 = { fr = "T'as une minute? Je reflechis...", en = "Give me a second? I'm thinking..." },
        IGUI_PHNPC_FALLBACK_GENERIC_6 = { fr = "C'est complique, tu vois.", en = "It's complicated, you know." },
        IGUI_PHNPC_FALLBACK_GENERIC_7 = { fr = "Je... je n'aime pas vraiment en parler.", en = "I... I don't really like talking about it." },
        IGUI_PHNPC_FALLBACK_GENERIC_8 = { fr = "Peut-etre plus tard, d'accord?", en = "Maybe later, alright?" },
        IGUI_PHNPC_FALLBACK_BRUTAL = { fr = "Ca ne te regarde pas. Degages.", en = "None of your business. Back off." },

        IGUI_NPC_Greeting_Friendly_1 = { fr = "Salut! Content de te voir. Comment ca va?", en = "Hey! Good to see you. How are you?" },
        IGUI_NPC_Greeting_Friendly_2 = { fr = "Hey! Ca roule? T'as du nouveau?", en = "Hey! Everything good? Any news?" },
        IGUI_NPC_Greeting_Friendly_3 = { fr = "Coucou! Quoi de neuf?", en = "Hi! What's new?" },
        IGUI_NPC_Greeting_LoneWolf_1 = { fr = "Quoi? T'as quelque chose a me dire?", en = "What? You got something to tell me?" },
        IGUI_NPC_Greeting_LoneWolf_2 = { fr = "Ouais, c'est quoi?", en = "Yeah, what is it?" },
        IGUI_NPC_Greeting_LoneWolf_3 = { fr = "Laisse-moi tranquille.", en = "Leave me alone." },
        IGUI_NPC_Greeting_Neutral_1 = { fr = "Salut.", en = "Hi." },
        IGUI_NPC_Greeting_Neutral_2 = { fr = "Ouais, bonjour.", en = "Yeah, hello." },
        IGUI_NPC_Greeting_Neutral_3 = { fr = "Qu'est-ce que tu veux?", en = "What do you want?" },

        IGUI_NPC_HungryThirsty_1 = { fr = "Man, j'creve de faim ET de soif... degoutant.", en = "Man, I'm starving AND thirsty... this is rough." },
        IGUI_NPC_HungryThirsty_2 = { fr = "Je tiens plus, j'ai besoin de manger et boire!", en = "I can't keep going, I need food and water!" },
        IGUI_NPC_Hungry = { fr = "J'ai une faim de loup. Faut que je trouve a bouffer.", en = "I'm starving. I need to find food." },
        IGUI_NPC_Hungry_2 = { fr = "Mon estomac crie famine, la...", en = "My stomach is screaming right now..." },
        IGUI_NPC_Thirsty = { fr = "J'ai trop soif. Besoin d'eau...", en = "I'm really thirsty. Need water..." },
        IGUI_NPC_Thirsty_2 = { fr = "Ma gorge est completement seche.", en = "My throat is completely dry." },

        IGUI_NPC_Wounded_1 = { fr = "Je suis mal en point, faut que je me soigne...", en = "I'm in bad shape, I need to patch myself up..." },
        IGUI_NPC_Wounded_2 = { fr = "Aidez-moi, j'suis grave blesse!", en = "Help me, I'm badly hurt!" },
        IGUI_NPC_Wounded_Brutal = { fr = "On s'fait tabasser, la! Faut se battre!", en = "We're getting wrecked here! Fight back!" },
        IGUI_NPC_Wounded_Anxious = { fr = "C'est pas bon... c'est pas bon...", en = "This is bad... really bad..." },

        IGUI_NPC_BittenHidden_1 = { fr = "Je... je ne me sens pas bien...", en = "I... I don't feel right..." },
        IGUI_NPC_BittenHidden_2 = { fr = "*tousse legerement* Ca va, ca va...", en = "*coughs lightly* I'm fine, I'm fine..." },
        IGUI_NPC_BittenHidden_3 = { fr = "Laisse-moi tranquille, j'ai besoin d'air", en = "Leave me alone, I need air." },

        IGUI_NPC_Attitude_Brutal_1 = { fr = "T'veux la bagarre? Parce que je demande que ca!", en = "You want a fight? Because I'm ready." },
        IGUI_NPC_Attitude_Brutal_2 = { fr = "Bouge pas de ma route, sinon...", en = "Don't stand in my way, or else..." },
        IGUI_NPC_Attitude_Brutal_3 = { fr = "On regle ca a la maniere forte, tu veux?", en = "We can settle this the hard way, if you want." },
        IGUI_NPC_Attitude_Courage_1 = { fr = "J'ai pas peur. Fonce!", en = "I'm not afraid. Let's move!" },
        IGUI_NPC_Attitude_Courage_2 = { fr = "Montre-moi c'que t'as comme ressource!", en = "Show me what resources you've got!" },
        IGUI_NPC_Attitude_Courage_3 = { fr = "On peut compter l'un sur l'autre, pas vrai?", en = "We can count on each other, right?" },
        IGUI_NPC_Attitude_Fear_1 = { fr = "Euh... je... je suis pas sur si c'est une bonne idee...", en = "Uh... I... I'm not sure this is a good idea..." },
        IGUI_NPC_Attitude_Fear_2 = { fr = "J'ai un peu peur, mais je te fais confiance.", en = "I'm scared, but I trust you." },
        IGUI_NPC_Attitude_Fear_3 = { fr = "T'es sur qu'c'est sage?", en = "Are you sure this is wise?" },

        IGUI_NPC_Morale_Low_1 = { fr = "J'en peux plus... c'est trop difficile.", en = "I can't do this much longer... it's too hard." },
        IGUI_NPC_Morale_Low_2 = { fr = "Tout est pourri. Pourquoi on continue?", en = "Everything is awful. Why are we still doing this?" },
        IGUI_NPC_Morale_Ok_1 = { fr = "On s'en sort pas mal pour l'instant.", en = "We're doing alright for now." },
        IGUI_NPC_Morale_Ok_2 = { fr = "La situation n'est pas completement desesperee.", en = "Things are not completely hopeless yet." },

        IGUI_NPC_Generic_1 = { fr = "T'as vu ca? Incroyable...", en = "Did you see that? Unbelievable..." },
        IGUI_NPC_Generic_2 = { fr = "C'est une rude epoque.", en = "These are hard times." },
        IGUI_NPC_Generic_3 = { fr = "Faut etre prudent.", en = "We need to stay careful." },
        IGUI_NPC_Generic_4 = { fr = "Ouais, d'accord.", en = "Yeah, alright." },

        IGUI_NPC_Learning_1 = { fr = "J'ai observe pas mal de choses dernierement...", en = "I've observed a lot lately..." },
        IGUI_NPC_Learning_2 = { fr = "Tu m'as enseigne des trucs, tu sais.", en = "You taught me a few things, you know." },
        IGUI_NPC_Learning_3 = { fr = "J'ai appris en te regardant faire...", en = "I learned by watching you..." },

        IGUI_NPC_Trade_Offer_1 = { fr = "Je peux te faire un bon prix si tu prends le lot.", en = "I can give you a better price if you take the whole batch." },
        IGUI_NPC_Trade_Offer_2 = { fr = "On peut troquer: ressources contre outils.", en = "We can trade: resources for tools." },
        IGUI_NPC_Trade_Offer_3 = { fr = "Les munitions valent cher aujourd'hui, fais une offre serieuse.", en = "Ammo is expensive today, make a serious offer." },
        IGUI_NPC_Trade_Offer_4 = { fr = "Si tu paies vite, je garde le prix avant que le marche bouge.", en = "If you pay fast, I'll keep this price before the market shifts." },
        IGUI_NPC_Trade_NoCash = { fr = "J'ai plus un rond. Faut que je vende avant d'acheter.", en = "I'm out of cash. I need to sell before I buy." },
        IGUI_NPC_Trade_DealDone = { fr = "Marche conclu, c'etait propre.", en = "Deal done, that was clean." },
        IGUI_NPC_Market_HighDemand = { fr = "La demande explose ici, les prix montent.", en = "Demand is surging here, prices are going up." },
        IGUI_NPC_Market_Oversupply = { fr = "On est en surstock, les prix chutent.", en = "We're overstocked, prices are dropping." },

        IGUI_NPC_Action_Trade_1 = { fr = "Je compare les prix des clans avant de signer.", en = "I compare faction prices before I close a deal." },
        IGUI_NPC_Action_Trade_2 = { fr = "Le troc marche encore mieux que l'argent, parfois.", en = "Barter still beats cash sometimes." },
        IGUI_NPC_Action_Trade_3 = { fr = "J'evite les arnaques: quantite, etat, puis paiement.", en = "I avoid scams: quantity, condition, then payment." },
        IGUI_NPC_Action_Build_1 = { fr = "On renforce les murs avant que la horde repasse.", en = "We're reinforcing walls before the horde passes again." },
        IGUI_NPC_Action_Build_2 = { fr = "Il me faut des planches et des clous pour avancer.", en = "I need planks and nails to keep building." },
        IGUI_NPC_Action_Build_3 = { fr = "Chaque barricade gagne du temps quand ca tourne mal.", en = "Every barricade buys us time when things go bad." },
        IGUI_NPC_Action_Cook_1 = { fr = "Je cuisine ce qu'on a avant que ca pourrisse.", en = "I cook what we have before it spoils." },
        IGUI_NPC_Action_Cook_2 = { fr = "Mieux vaut un repas moyen qu'un ventre vide.", en = "A mediocre meal beats an empty stomach." },
        IGUI_NPC_Action_Cook_3 = { fr = "Rationner proprement, c'est ce qui nous garde en vie.", en = "Proper rationing is what keeps us alive." },
        IGUI_NPC_Action_Defend_1 = { fr = "Je tiens la ligne si les morts approchent.", en = "I'll hold the line if the dead get close." },
        IGUI_NPC_Action_Defend_2 = { fr = "Reste derriere moi si ca casse.", en = "Stay behind me if this breaks bad." },
        IGUI_NPC_Action_Guard_1 = { fr = "Je prends la garde sur ce secteur.", en = "I'm taking guard duty in this sector." },
        IGUI_NPC_Action_Guard_2 = { fr = "Je surveille les angles morts et les fenetres.", en = "I'm watching blind spots and windows." },
        IGUI_NPC_Action_Guard_3 = { fr = "Une minute d'inattention, et c'est fini.", en = "One minute of inattention and we're done." },
        IGUI_NPC_Action_Scavenge_1 = { fr = "Je pars en recuperation, je prends juste l'essentiel.", en = "I'm heading out to scavenge, only essentials." },
        IGUI_NPC_Action_Scavenge_2 = { fr = "Les pharmacies et entrepots sont les plus disputes.", en = "Pharmacies and warehouses are the most contested." },
        IGUI_NPC_Action_Scavenge_3 = { fr = "Je note les sorties avant d'entrer dans un batiment.", en = "I map exits before entering a building." },
        IGUI_NPC_Action_Study_1 = { fr = "J'analyse ce qu'on fait pour eviter les erreurs.", en = "I analyze what we do to avoid mistakes." },
        IGUI_NPC_Action_Study_2 = { fr = "Observer, apprendre, survivre. C'est la methode.", en = "Observe, learn, survive. That's the method." },
        IGUI_NPC_Action_Recover_1 = { fr = "Je recupere un peu, sinon je vais craquer.", en = "I'm recovering for a bit, or I'll collapse." },
        IGUI_NPC_Action_Recover_2 = { fr = "Pas de repos, pas de jugement. Et la, on meurt.", en = "No rest means no judgment. That's how we die." },
        IGUI_NPC_Action_Medical_1 = { fr = "On nettoie, on panse, et on surveille la fievre.", en = "Clean it, bandage it, and monitor fever." },
        IGUI_NPC_Action_Medical_2 = { fr = "Si la plaie empire, on agit tout de suite.", en = "If the wound worsens, we act immediately." },
        IGUI_NPC_OrderParam_Guard_Base_1 = { fr = "Je tiens la garde autour de {baseId}.", en = "I'm holding watch around {baseId}." },
        IGUI_NPC_OrderParam_Guard_Perimeter_1 = { fr = "Je surveille tout le perimetre assigne, pas juste une porte.", en = "I'm watching the whole assigned perimeter, not just one door." },
        IGUI_NPC_OrderParam_Patrol_Perimeter_1 = { fr = "Je boucle sur le perimetre et je verifie que rien ne bouge.", en = "I'm looping the perimeter and checking that nothing moves." },
        IGUI_NPC_OrderParam_Defend_Escort_1 = { fr = "Je suis en escorte defensive autour de {playerId}.", en = "I'm on defensive escort around {playerId}." },
        IGUI_NPC_OrderParam_Defend_Aggressive_1 = { fr = "On m'a demande une couverture agressive. Si ca sort, je cogne.", en = "I was told to provide aggressive cover. If it comes out, I hit back." },
        IGUI_NPC_OrderParam_Defend_Player_1 = { fr = "Je couvre {playerId} dans ce rayon-la.", en = "I'm covering {playerId} inside that radius." },
        IGUI_NPC_OrderParam_Build_Base_1 = { fr = "Le chantier en cours concerne {baseId}.", en = "The current build job is tied to {baseId}." },
        IGUI_NPC_OrderParam_Build_Site_1 = { fr = "Je bosse sur la zone {siteId} tant qu'elle n'est pas terminee.", en = "I'm working on site {siteId} until it's finished." },
        IGUI_NPC_OrderParam_Scavenge_Food_1 = { fr = "Je fouille surtout pour trouver de la bouffe, genre {hint}.", en = "I'm scavenging mainly for food, stuff like {hint}." },
        IGUI_NPC_OrderParam_Scavenge_Water_1 = { fr = "Ma priorite dehors, c'est l'eau et tout ce qui ressemble a {hint}.", en = "My priority out there is water and anything like {hint}." },
        IGUI_NPC_OrderParam_Scavenge_Medicine_1 = { fr = "Je cherche du medical en priorite, surtout {hint}.", en = "I'm prioritizing medical supplies, especially {hint}." },
        IGUI_NPC_OrderParam_Scavenge_Tools_1 = { fr = "Je fouille pour des outils, notamment {hint}.", en = "I'm scavenging for tools, especially {hint}." },
        IGUI_NPC_OrderParam_Scavenge_Materials_1 = { fr = "Je sors pour ramener des materiaux comme {hint}.", en = "I'm heading out to bring back materials like {hint}." },
        IGUI_NPC_OrderParam_Scavenge_Ammo_1 = { fr = "Cette fouille vise surtout des munitions comme {hint}.", en = "This scavenging run is mostly for ammo like {hint}." },
        IGUI_NPC_OrderParam_Scavenge_Target_1 = { fr = "On m'a envoye chercher precisement {hint}.", en = "I was sent out to look for {hint} specifically." },
        IGUI_NPC_OrderParam_Scavenge_Stealth_1 = { fr = "Je dois faire cette recuperation discretement, sans attirer la horde.", en = "I have to handle this scavenging run quietly, without drawing the horde." },
        IGUI_NPC_OrderParam_Recover_Base_1 = { fr = "Je recupere a {baseId} avant de repartir.", en = "I'm recovering at {baseId} before heading back out." },
        IGUI_NPC_OrderParam_Study_Craft_1 = { fr = "Mon etude sert a preparer un vrai travail d'artisanat.", en = "My study time is meant to prepare real crafting work." },
        IGUI_NPC_OrderParam_Study_Delivery_1 = { fr = "Ce que j'apprends doit finir livre a {playerId}.", en = "What I'm learning is meant to end up delivered to {playerId}." },
        IGUI_NPC_OrderParam_Study_Base_1 = { fr = "J'etudie pour rendre {baseId} plus viable.", en = "I'm studying to make {baseId} more viable." },
        IGUI_NPC_OrderParam_Cook_Base_1 = { fr = "Je cuisine pour soutenir {baseId}.", en = "I'm cooking to support {baseId}." },
        IGUI_NPC_OrderParam_Follow_Player_1 = { fr = "Je suis l'ordre de suivre {playerId}.", en = "I'm under orders to follow {playerId}." },
        IGUI_NPC_OrderParam_Follow_NPC_1 = { fr = "Je reste dans le sillage de {npcId}.", en = "I'm staying in {npcId}'s wake." },
        IGUI_NPC_OrderParam_Follow_Distance_1 = { fr = "Je dois garder environ {distance} metres d'ecart.", en = "I'm supposed to keep about {distance} meters of distance." },
        IGUI_NPC_OrderParam_Stay_Radius_1 = { fr = "Je dois tenir dans un rayon d'environ {radius} metres.", en = "I'm supposed to hold inside a radius of about {radius} meters." },
        IGUI_NPC_OrderParam_Sleep_Base_1 = { fr = "On m'a colle au repos sur {baseId}.", en = "I was put on rest duty at {baseId}." },

        IGUI_NPC_Condition_Night_1 = { fr = "La nuit, chaque bruit compte double.", en = "At night, every noise counts twice." },
        IGUI_NPC_Condition_Night_2 = { fr = "On bouge lentement apres la tombee de la nuit.", en = "We move slowly after dark." },
        IGUI_NPC_Condition_Rain_1 = { fr = "La pluie couvre les pas, mais pas les erreurs.", en = "Rain covers footsteps, not mistakes." },
        IGUI_NPC_Condition_Rain_2 = { fr = "Sous la pluie, je protege surtout le materiel.", en = "In rain, I protect supplies first." },
        IGUI_NPC_Condition_ZombiePressure_1 = { fr = "J'entends trop de morts autour, restons serres.", en = "I hear too many dead nearby, stay tight." },
        IGUI_NPC_Condition_ZombiePressure_2 = { fr = "Si la pression monte, on replie vers la base.", en = "If pressure rises, we fall back to base." },
        IGUI_NPC_Condition_BaseSafety_1 = { fr = "La base tient bon, pour l'instant.", en = "The base is holding, for now." },
        IGUI_NPC_Condition_BaseSafety_2 = { fr = "On est plus en securite ici qu'en rue ouverte.", en = "We're safer here than out in the open." },
        IGUI_NPC_Inventory_Full_1 = { fr = "Mon sac est presque plein, faut trier.", en = "My bag is almost full, we need to sort." },
        IGUI_NPC_Inventory_Full_2 = { fr = "Si je prends plus, je ralentis tout le groupe.", en = "If I carry more, I slow the whole group." },
        IGUI_NPC_Trust_High_1 = { fr = "Je te fais confiance, on peut bosser proprement.", en = "I trust you, we can work cleanly." },
        IGUI_NPC_Trust_High_2 = { fr = "Avec toi, je prends des risques calcules.", en = "With you, I take calculated risks." },
        IGUI_NPC_Trust_Low_1 = { fr = "Je garde un oeil sur toi, au cas ou.", en = "I'm keeping an eye on you, just in case." },
        IGUI_NPC_Trust_Low_2 = { fr = "Prouve-moi que je peux te croire.", en = "Prove I can trust you." },
        IGUI_NPC_Relation_Positive_1 = { fr = "Avec toi, je peux parler sans serrer les dents.", en = "With you, I can talk without clenching my jaw." },
        IGUI_NPC_Relation_Positive_2 = { fr = "On se comprend mieux que la plupart des survivants.", en = "We understand each other better than most survivors do." },
        IGUI_NPC_Relation_Neutral_1 = { fr = "Pour l'instant, on reste corrects et prudents.", en = "For now, we stay civil and careful." },
        IGUI_NPC_Relation_Neutral_2 = { fr = "Je t'evalue encore, rien de plus.", en = "I'm still sizing you up, nothing more." },
        IGUI_NPC_Relation_Wary_1 = { fr = "Je reste mefiant. Un faux pas, et ca change vite.", en = "I stay wary. One wrong move and that changes fast." },
        IGUI_NPC_Relation_Wary_2 = { fr = "Je ne te tourne pas le dos, pas encore.", en = "I'm not turning my back on you, not yet." },
        IGUI_NPC_Relation_Fearful_1 = { fr = "Tu me mets mal a l'aise. Je prefere garder mes distances.", en = "You put me on edge. I'd rather keep some distance." },
        IGUI_NPC_Relation_Fearful_2 = { fr = "Je parle, mais je reste pret a degager si ca tourne mal.", en = "I'll talk, but I'm ready to bail if this turns bad." },
        IGUI_NPC_Relation_Hostile_1 = { fr = "Entre nous, c'est tendu. N'attends pas de chaleur.", en = "Between us, it's tense. Don't expect warmth." },
        IGUI_NPC_Relation_Hostile_2 = { fr = "On n'est pas en bons termes, alors pese tes mots.", en = "We're not on good terms, so choose your words carefully." },

        IGUI_NPC_Profession_Artisan = { fr = "Je suis artisan, je transforme les materiaux utilement.", en = "I'm an artisan, I turn raw materials into useful goods." },
        IGUI_NPC_Profession_Cook = { fr = "Je cuisine pour le groupe, c'est ma priorite.", en = "I cook for the group, that's my priority." },
        IGUI_NPC_Profession_Builder = { fr = "Je renforce la base avant la nuit.", en = "I reinforce the base before nightfall." },
        IGUI_NPC_Profession_Merchant = { fr = "Je fais tourner le commerce, c'est vital.", en = "I keep trade flowing, that's vital." },
        IGUI_NPC_Profession_Scout = { fr = "Je repere les zones a risque et les opportunites.", en = "I scout risky zones and opportunities." },
        IGUI_NPC_Profession_Warrior = { fr = "Je couvre les notres si ca tourne mal.", en = "I cover our people when things go bad." },
        IGUI_NPC_Profession_Scholar = { fr = "J'etudie ce qu'on voit pour mieux survivre.", en = "I study what we observe to survive better." },
        IGUI_NPC_Profession_Unknown = { fr = "Je fais ce qu'il faut pour tenir un jour de plus.", en = "I do whatever it takes to survive one more day." },

        IGUI_NPC_Faction_Allied = { fr = "Ton clan est fiable. On peut cooperer.", en = "Your faction is reliable. We can cooperate." },
        IGUI_NPC_Faction_Neutral = { fr = "On reste neutres pour l'instant.", en = "We stay neutral for now." },
        IGUI_NPC_Faction_Hostile = { fr = "Ton clan nous met la pression. On reste sur nos gardes.", en = "Your faction is pressuring us. We stay on guard." },
        IGUI_NPC_Faction_EventRaid = { fr = "On a entendu des rumeurs de raid. Faut se preparer.", en = "We've heard raid rumors. We need to prepare." },
        IGUI_NPC_Faction_EventNeedHelp = { fr = "Le clan manque de mains. On aurait besoin d'aide.", en = "The faction is short on hands. We could use help." },

        IGUI_NPC_Event_TradeDone_1 = { fr = "Le dernier troc s'est bien passe. J'aime quand c'est net.", en = "That last trade went smoothly. I like it when it's clean." },
        IGUI_NPC_Event_TradeDone_2 = { fr = "On a deja fait affaire, donc on peut parler serieusement.", en = "We've already traded, so we can talk seriously." },
        IGUI_NPC_Event_Helped_1 = { fr = "Je n'oublie pas qu'on s'est aides recemment.", en = "I haven't forgotten that we helped each other recently." },
        IGUI_NPC_Event_Helped_2 = { fr = "Apres ce qu'on a partage, je te parle autrement.", en = "After what we shared, I talk to you differently." },
        IGUI_NPC_Event_PlayerHostile_1 = { fr = "Vu ton dernier ecart, me pousse pas plus loin.", en = "After your last move, don't push me any further." },
        IGUI_NPC_Event_PlayerHostile_2 = { fr = "Je me souviens tres bien de ce que t'as fait. Fais attention.", en = "I remember exactly what you did. Watch yourself." },
        IGUI_NPC_Event_BiteSecret_1 = { fr = "Y a un truc qui cloche. J'essaie encore de le cacher.", en = "Something is wrong. I'm still trying to hide it." },
        IGUI_NPC_Event_BiteSecret_2 = { fr = "Ne me fixe pas comme ca. J'ai juste besoin de temps.", en = "Don't stare at me like that. I just need time." },
        IGUI_NPC_Event_LastOrderTrade_1 = { fr = "Je sors d'une affaire recente, j'ai encore les comptes en tete.", en = "I just came off a deal, I've still got the numbers in my head." },
        IGUI_NPC_Event_LastOrderTrade_2 = { fr = "Mon dernier echange m'a laisse prudent sur ce qu'on promet.", en = "My last exchange left me careful about what we promise." },
        IGUI_NPC_Event_FriendlyStable_1 = { fr = "Entre nous, y a pas de tension pour l'instant. Restons comme ca.", en = "Between us, there's no tension right now. Let's keep it that way." },
        IGUI_NPC_Event_FriendlyStable_2 = { fr = "Tant qu'on reste reglos, je vois pas pourquoi ca deraperait.", en = "As long as we stay straight with each other, I don't see why this would go bad." },
        IGUI_NPC_Event_OrderFinished_Guard_1 = { fr = "Je viens de finir ma garde. Rien n'est tombe sur nous cette fois.", en = "I just finished my watch. Nothing fell on us this time." },
        IGUI_NPC_Event_OrderFinished_Guard_2 = { fr = "Apres la garde, j'ai encore tous les bruits du secteur en tete.", en = "After guard duty, I still have every sound in this sector in my head." },
        IGUI_NPC_Event_OrderFinished_Defend_1 = { fr = "Je viens de finir une couverture defensive. J'ai encore l'adrenaline.", en = "I just finished a defensive cover assignment. I've still got the adrenaline." },
        IGUI_NPC_Event_OrderFinished_Defend_2 = { fr = "Tenir la defense use les nerfs, meme quand rien ne craque.", en = "Holding defense drains your nerves, even when nothing breaks." },
        IGUI_NPC_Event_OrderFinished_Follow_1 = { fr = "Suivre quelqu'un longtemps, ca apprend ses habitudes.", en = "Following someone for a while teaches you their habits." },
        IGUI_NPC_Event_OrderFinished_Follow_2 = { fr = "Je viens de finir un deplacement de suivi. J'ai encore son rythme en tete.", en = "I just wrapped a follow movement. I've still got their pace in my head." },
        IGUI_NPC_Event_OrderFinished_Recover_1 = { fr = "Je sors juste d'un temps de recuperation. J'ai les idees un peu plus claires.", en = "I just came off a recovery break. My head is a little clearer now." },
        IGUI_NPC_Event_OrderFinished_Recover_2 = { fr = "Avoir souffle un peu evite de faire des erreurs stupides.", en = "Getting a bit of rest keeps me from making stupid mistakes." },
        IGUI_NPC_Event_OrderFinished_Scavenge_1 = { fr = "Je reviens de recuperation. Le terrain est sale et dispute dehors.", en = "I'm back from scavenging. The ground out there is ugly and contested." },
        IGUI_NPC_Event_OrderFinished_Scavenge_2 = { fr = "Apres une fouille, je sais encore mieux ce qui manque au groupe.", en = "After a scavenging run, I know even better what the group is missing." },
        IGUI_NPC_Event_OrderFinished_Study_1 = { fr = "Je viens de sortir d'un temps d'etude. Ca remet un peu d'ordre dans la tete.", en = "I just came out of a study session. It puts a bit of order back in my head." },
        IGUI_NPC_Event_OrderFinished_Study_2 = { fr = "Etudier ici, c'est chercher du sens dans des ruines.", en = "Studying here is trying to find meaning in ruins." },
        IGUI_NPC_Event_OrderFinished_Sleep_1 = { fr = "Je sors du repos. Pas frais, mais moins casse qu'avant.", en = "I'm coming off rest. Not fresh, but less broken than before." },
        IGUI_NPC_Event_OrderFinished_Sleep_2 = { fr = "Dormir par tranches, c'est tout ce qu'on a encore.", en = "Sleeping in fragments is all we've got left." },
        IGUI_NPC_Event_OrderFinished_Stay_1 = { fr = "Je viens de tenir la position sans bouger de ma zone.", en = "I just held position without leaving my zone." },
        IGUI_NPC_Event_OrderFinished_Stay_2 = { fr = "Rester en place parait simple, jusqu'a ce que tout se rapproche.", en = "Holding still sounds simple until everything starts closing in." },
        IGUI_NPC_Event_OrderFinished_Build_1 = { fr = "Je viens de finir sur la construction. La base tiendra un peu mieux.", en = "I just wrapped up some building. The base will hold a little better now." },
        IGUI_NPC_Event_OrderFinished_Build_2 = { fr = "Le chantier m'a use, mais chaque planche compte ici.", en = "The worksite wore me down, but every plank matters here." },
        IGUI_NPC_Event_OrderFinished_Cook_1 = { fr = "Je sors de la cuisine. Au moins, le groupe mangera chaud.", en = "I'm just out of the kitchen. At least the group will eat warm." },
        IGUI_NPC_Event_OrderFinished_Cook_2 = { fr = "Finir de cuisiner remet un peu d'ordre dans ce chaos.", en = "Finishing the cooking brings a bit of order to this chaos." },

        IGUI_NPC_Event_PathBlocked_1 = { fr = "Route barree: barricade ou porte bloquee, je dois contourner.", en = "Path blocked: barricade or jammed door, I need to reroute." },
        IGUI_NPC_Event_PathBlocked_2 = { fr = "J'ai bute sur un obstacle, je cherche un autre angle.", en = "I hit an obstacle, looking for another angle." },
        IGUI_NPC_Event_PathContour_1 = { fr = "Je contourne par le cote, c'est plus lent mais plus sur.", en = "I'm taking a side route, slower but safer." },
        IGUI_NPC_Event_PathContour_2 = { fr = "Pas de passage direct, je tourne autour.", en = "No direct opening, so I'm going around." },

        IGUI_NPC_Event_WeatherShelter_1 = { fr = "Je suis trempe, je cherche un abri tout de suite.", en = "I'm soaked, I need shelter now." },
        IGUI_NPC_Event_WeatherShelter_2 = { fr = "Sous cette pluie, rester dehors c'est tomber malade.", en = "Staying out in this rain means getting sick." },
        IGUI_NPC_Event_WeatherWarmth_1 = { fr = "Il fait trop froid, il me faut des vetements chauds ou un feu.", en = "It's too cold, I need warm clothes or a fire." },
        IGUI_NPC_Event_WeatherWarmth_2 = { fr = "Si la neige tient, on va y laisser notre sante.", en = "If this snow keeps up, we'll lose our health out here." },
        IGUI_NPC_Event_WeatherSick_1 = { fr = "Le froid me ronge, je commence a tomber malade.", en = "The cold is eating through me, I'm getting sick." },
        IGUI_NPC_Event_WeatherSick_2 = { fr = "Mouille et gele, c'est la pire combinaison.", en = "Wet and freezing is the worst combination." },

        IGUI_NPC_Event_TraumaFreeze_1 = { fr = "Je bloque... j'arrive plus a bouger un instant.", en = "I'm freezing up... I can't move for a moment." },
        IGUI_NPC_Event_TraumaFreeze_2 = { fr = "Quand la horde approche, mon cerveau se coupe.", en = "When the horde closes in, my mind locks up." },
        IGUI_NPC_Event_TraumaRage_1 = { fr = "Ils ont pris les notres. Je vais les broyer.", en = "They took our people. I'm going to crush them." },
        IGUI_NPC_Event_TraumaRage_2 = { fr = "Ma peur se transforme en rage pure.", en = "My fear is turning into pure rage." },

        IGUI_NPC_Event_InjuryLocalized_1 = { fr = "Ma jambe me lache, je ralentis tout le monde.", en = "My leg is giving out, I'm slowing everyone down." },
        IGUI_NPC_Event_InjuryLocalized_2 = { fr = "Avec ces blessures, je perds en precision et en force.", en = "With these injuries, I lose accuracy and strength." },

        IGUI_NPC_Event_ExpeditionStart_1 = { fr = "Je pars en expedition hors-zone. Retour pas avant plusieurs jours.", en = "I'm leaving on an off-grid expedition. I won't be back for days." },
        IGUI_NPC_Event_ExpeditionStart_2 = { fr = "Plus la distance est grande, plus le retour est incertain.", en = "The farther I go, the less certain my return is." },
        IGUI_NPC_Event_ExpeditionReturn_1 = { fr = "Je suis revenu d'expedition avec du butin, mais c'etait limite.", en = "I'm back from expedition with loot, but it was close." },
        IGUI_NPC_Event_ExpeditionReturn_2 = { fr = "L'aller-retour a ete long. On a eu de la chance.", en = "That round trip was long. We got lucky." },

        IGUI_NPC_Event_StoryShared_1 = { fr = "J'ai raconte ce qu'on a vecu. Ca soulage un peu.", en = "I shared what we've lived through. It helps a bit." },
        IGUI_NPC_Event_StoryShared_2 = { fr = "Parler des histoires du groupe nous tient debout.", en = "Sharing group stories helps keep us standing." },
        IGUI_NPC_Event_SocialTalk_1 = { fr = "Parler fait redescendre la solitude.", en = "Talking pushes back loneliness." },
        IGUI_NPC_Event_SocialTalk_2 = { fr = "J'avais besoin d'un vrai contact humain.", en = "I needed real human contact." },
        IGUI_NPC_Event_SocialTrade_1 = { fr = "Meme un troc, c'est un lien avec quelqu'un.", en = "Even a trade is still a human connection." },
        IGUI_NPC_Event_SocialTrade_2 = { fr = "Le commerce aide moins que parler, mais ca compte.", en = "Trade helps less than a real talk, but it still counts." }
    }
}

function NPCDialogueLocalization.normalizeLanguageCode(languageCode)
    local code = string.upper(tostring(languageCode or ""))
    code = code:gsub("[^A-Z]", "")
    if #code >= 2 then
        return code:sub(1, 2)
    end
    return "EN"
end

function NPCDialogueLocalization:getText(key, languageCode, fallbackFr, fallbackEn)
    if not key or #tostring(key) == 0 then
        return "..."
    end

    if getText then
        local ok, translated = pcall(function()
            return getText(key)
        end)
        if ok and translated and translated ~= key and #tostring(translated) > 0 then
            return tostring(translated)
        end
    end

    local entry = self.entries[key] or {}
    local langCode = self.normalizeLanguageCode(languageCode)
    local fr = fallbackFr or entry.fr or key
    local en = fallbackEn or entry.en or fr

    if langCode == "FR" then
        return fr
    end

    return en
end

_G.NPCDialogueLocalization = NPCDialogueLocalization
return NPCDialogueLocalization
