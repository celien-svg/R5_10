# Cours 1 — Pourquoi le relationnel ne suffit pas toujours

**R5.A.10 — Nouveaux paradigmes de bases de données · BUT Informatique 3e année**
*Cours à lire en autonomie, 45 minutes environ. Il remplace la séance de cours magistral et prépare le TP 1.*

---

## Comment lire ce document

Ce cours remplace le cours de la séance 1, qui n'a pas pu être assuré. Il reprend le support projeté et ce qui aurait été dit à l'oral. Trois consignes pour qu'il vous serve vraiment :

1. **Faites l'exercice de la section 2 sur papier, avant de lire sa correction.** C'est le moment le plus important des dix-huit heures du module. Le lire sans l'avoir cherché vous-même ne vous apprendra presque rien.
2. **Recopiez le tableau de la section 4.** Il resservira à chaque séance et à l'évaluation écrite.
3. **Terminez par l'auto-évaluation de la section 9.** Si vous séchez sur plus de deux questions, relisez la section concernée.

Le TP 1 (`TP1_etudiants_Environnement.md`) se fait après cette lecture, et suppose que vous avez installé Docker et le SDK .NET avec la fiche d'installation.

---

## 1. Le module, et PixelHub

Depuis la première année, vous faites du relationnel : des tables, des clés étrangères, du SQL. C'est très bien, et personne ne va vous dire que c'était une erreur. Ce module part d'une autre question : **est-ce que toutes les données d'une application ont vraiment la même forme, et méritent le même traitement ?**

Pour y répondre, on va construire **une seule application sur les six séances**, une plateforme de jeu appelée **PixelHub**, et lui brancher à chaque séance un moteur de base de données de plus, chacun choisi pour un usage précis.

| Séance | Thème | Ce qu'on ajoute |
|---|---|---|
| 1 | Panorama | Pourquoi, et PostgreSQL |
| 2 | MongoDB | Le catalogue de jeux, à schéma variable |
| 3 | Redis | Classements, matchmaking, joueurs en ligne |
| 4 | Neo4j | Graphe social, recommandation |
| 5 | Cohabitation | Cohérence et arbitrages entre les quatre bases |
| 6 | Évaluation | Mise en situation sur un autre domaine |

À la fin de la séance 4, votre application tournera avec quatre bases de données en même temps. La séance 5 servira à se demander si c'était une bonne idée.

### PixelHub, concrètement

Une plateforme où l'on découvre des jeux, joue des parties classées et achète des skins. Suivez une joueuse, Nova :

1. **Nova se connecte.** Son profil, son niveau, son solde : 1 200 pièces d'or.
2. **Elle parcourt le catalogue.** Des milliers de jeux, filtrables par genre, plateforme, tags.
3. **Elle rejoint une file d'attente.** Le matchmaking l'apparie à un adversaire de son niveau.
4. **Elle joue une partie classée.** Son score évolue, elle gagne trois places au classement.
5. **Elle voit ce que jouent ses amis.** Trois de ses amis ont *Hades II*, qu'elle ne possède pas.
6. **Elle achète un skin.** 500 pièces débitées de son solde. Une fois, pas deux.

Six actions banales. Six formes de données radicalement différentes. Regroupées, elles donnent quatre familles de données dans un seul produit :

| Donnée | Ce qu'elle a de particulier |
|---|---|
| **Catalogue** | Des milliers de jeux, aux fiches très différentes selon le genre |
| **Matchmaking** | File d'attente, joueurs en ligne, classements mis à jour en continu |
| **Communauté** | Amis, guildes, « a joué avec », recommandations |
| **Boutique** | Monnaie virtuelle, achats de skins, inventaire |

Faut-il vraiment les stocker toutes de la même façon ? C'est la question des dix-huit heures. On commence par le catalogue.

### Comment vous serez évalués

- **40 %** : deux ou trois TP relevés parmi les séances 2 à 4, notés sur le fonctionnement et sur la **justification des choix de modélisation**.
- **40 %** : la mise en situation de la séance 6, sur un autre domaine que PixelHub : une cartographie des données, une brique implémentée, une courte soutenance.
- **20 %** : un court écrit sur CAP, ACID/BASE et les critères de choix d'un moteur.

Le critère qui compte partout : **savoir justifier le choix d'un moteur**, davantage que la maîtrise de la syntaxe d'un outil.

---

## 2. ⭐ Un exercice avant de continuer : le catalogue

Vous devez stocker le catalogue de jeux de PixelHub. Voici trois jeux à représenter :

| Jeu | Genre | Attributs utiles |
|---|---|---|
| *Counter-Strike* | FPS | nombre de joueurs par équipe, liste des cartes, liste des modes de jeu, présence d'un classement compétitif |
| *Cities: Skylines* | Gestion | liste des scénarios, taille maximale de la carte, présence d'un mode bac à sable, durée moyenne d'une partie |
| *Stardew Valley* | Simulation | nombre de saisons, liste des personnages épousables, coopératif oui/non, nombre maximum de joueurs |

> **Modélisez ça en relationnel.** Tables, colonnes, clés étrangères : les outils que vous connaissez depuis deux ans. Prenez **dix minutes, sur papier**, et ne lisez pas la suite avant d'avoir une proposition.

### Vos trois solutions, vos trois problèmes

Vous avez très probablement abouti à l'une de ces trois modélisations. Les trois sont mauvaises, et c'est exactement le but de l'exercice.

| Ce que vous avez proposé | Le problème |
|---|---|
| **Une seule table `Jeu` avec toutes les colonnes** | Sur 3 jeux et 12 attributs spécifiques, la table est vide à environ 70 %. Et au 40e genre ? Le jour où l'on ajoute un jeu de course avec un nombre de circuits, il faut un `ALTER TABLE` en production. |
| **Une table par genre** (`JeuFPS`, `JeuGestion`, …) | Comment afficher « tous les jeux triés par note » ? Avec une `UNION` sur N tables, à réécrire chaque fois qu'un genre apparaît. |
| **Une table `Jeu` + une table `Attribut(jeu_id, cle, valeur)`** | La bonne intuition ! Mais `valeur` est un `VARCHAR` : on perd tout typage, on ne peut plus écrire `WHERE nb_joueurs > 4` proprement, et la moindre requête devient une pile de jointures. Ce motif s'appelle *Entity-Attribute-Value*, et il est connu pour être un cauchemar à maintenir. |

### Le vrai problème

Comptez les champs. Communs aux trois jeux : `titre`, `genre`, `note`, soit **3 champs**. Présents sur un seul jeu : `joueursParEquipe`, `cartes`, `modes`, `classementCompetitif`, `scenarios`, `tailleCarteMax`, `modeBacASable`, `dureeMoyenne`, `nombreSaisons`, `personnagesEpousables`, `coop`, `joueursMax`, soit **12 champs**. Et un nouveau genre en ajoutera d'autres demain.

**Le problème n'est pas que vous modélisez mal. Le problème est que cette donnée n'a pas de schéma fixe, et que le relationnel exige un schéma fixe.** Vous vous battez contre l'outil. Il existe des moteurs conçus exactement pour cette forme de donnée : on en voit un en séance 2.

Gardez votre feuille. En fin de séance 2, vous comparerez votre modélisation d'aujourd'hui au document MongoDB équivalent.

---

## 3. Le schéma variable n'est qu'un cas parmi d'autres

Trois autres situations où le relationnel se retrouve hors de son terrain.

**1. Les jointures en profondeur.** Question : « quels jeux possèdent les amis de mes amis, que je n'ai pas ? » Avec une table `Amitie(joueur_a, joueur_b)`, il vous faut une jointure pour les amis, une deuxième pour les amis des amis. Et à la profondeur 4 ? Chaque niveau ajoute une jointure, et chaque jointure multiplie le volume intermédiaire. Le SQL devient illisible avant de devenir lent. En séance 4, dans le langage de Neo4j, la même question s'écrira sur une ligne.

**2. La montée en charge horizontale.** Pour encaisser plus de charge, deux façons :

| | Scale-up (vertical) | Scale-out (horizontal) |
|---|---|---|
| Principe | Une machine plus grosse : plus de RAM, plus de CPU | Beaucoup de machines modestes |
| Avantage | Simple, rien à changer dans le code | Théoriquement sans limite |
| Limite | Plafond physique, coût qui explose en haut de gamme | Il faut **répartir les données** ; une jointure entre deux serveurs, ou une transaction qui verrouille trois machines, coûtent très cher |

Retenez la formule : **le relationnel préfère une grosse machine, le NoSQL préfère beaucoup de petites machines.** La plupart des moteurs NoSQL ont été conçus pour le scale-out, en acceptant de renoncer à certaines garanties. Lesquelles, c'est l'objet de la section 5.

**3. Les données éphémères à accès intensif.** Le nombre de joueurs en ligne change 500 fois par seconde, et ne vaut plus rien dans une heure. Personne ne veut faire un `INSERT` sur disque pour ça, et un `SELECT COUNT(*)` toutes les 200 ms pour afficher un compteur, c'est du gâchis.

> **À retenir.** Ne dites jamais « le relationnel c'est lent » ou « SQL c'est dépassé ». C'est faux. La formulation correcte : **le relationnel est excellent pour ce pour quoi il a été conçu ; ces cas-là sortent de son domaine de conception.**

---

## 4. Les quatre familles de bases non relationnelles

Une famille, c'est **une forme de donnée et une structure d'accès**. Pour chacune, posez-vous la question : à quoi ressemble une clé, à quoi ressemble une valeur ?

### Clé-valeur

Le modèle le plus simple : un dictionnaire géant et distribué. On donne une clé, on obtient une valeur. Rien d'autre. Aucune requête sur le contenu de la valeur.

- **Exemples** : Redis, Memcached, Amazon DynamoDB.
- **Force** : latence extrêmement faible (souvent en mémoire), modèle trivial.
- **Limite** : impossible de demander « tous les enregistrements où X > 3 ». Si on ne connaît pas la clé, on ne trouve rien.
- **Cas d'usage** : cache, sessions, compteurs, files d'attente, classements.

*Analogie* : une consigne de gare. Vous donnez votre numéro de casier, on vous rend votre sac. Personne ne peut demander « tous les casiers qui contiennent un sac rouge », il faudrait tous les ouvrir.

### Document

On stocke des documents JSON, regroupés en collections. Chaque document peut avoir sa propre structure, et on peut requêter *à l'intérieur* du document.

- **Exemples** : MongoDB, CouchDB.
- **Force** : schéma souple, et un objet métier tient souvent dans un seul document, donc pas de jointure pour le reconstituer.
- **Limite** : les relations entre documents sont à gérer à la main, et la souplesse se paie en rigueur : rien n'empêche d'écrire n'importe quoi.
- **Cas d'usage** : catalogues, profils, contenus, données semi-structurées.

C'est la réponse directe à l'exercice du catalogue.

### Graphe

On stocke des **nœuds**, des **relations** entre nœuds, et des propriétés sur les deux. La relation est un objet à part entière, pas une jointure calculée.

- **Exemples** : Neo4j, ArangoDB.
- **Force** : parcourir des relations, même en profondeur, est peu coûteux. Le moteur suit des pointeurs au lieu de recalculer des jointures.
- **Limite** : mal adapté aux traitements de masse sur toutes les données (« la somme de tous les achats du mois »).
- **Cas d'usage** : réseaux sociaux, recommandation, détection de fraude, arbres de dépendances.

### Colonnes larges

Des lignes identifiées par une clé, mais chaque ligne peut avoir ses propres colonnes, et le stockage est organisé par colonne, réparti sur de nombreuses machines. Conçues pour écrire énormément.

- **Exemples** : Cassandra, HBase, ScyllaDB.
- **Force** : débit d'écriture massif, distribution native.
- **Limite** : il faut concevoir le modèle **à partir des requêtes** que l'on veut faire ; une requête imprévue peut imposer de dupliquer les données.
- **Cas d'usage** : logs, télémétrie, historiques à très gros volume.

Il n'y aura pas de TP sur cette famille : elle est abordée en ouverture en séance 5.

### Récapitulatif, à recopier

| Famille | Unité stockée | On interroge par | Exemple | Cas d'usage type |
|---|---|---|---|---|
| Clé-valeur | Une valeur opaque | La clé, uniquement | Redis | Cache, classement, session |
| Document | Un document JSON | N'importe quel champ | MongoDB | Catalogue, profil |
| Graphe | Nœuds et relations | Des motifs de relations | Neo4j | Recommandation, réseau social |
| Colonnes larges | Lignes à colonnes variables | La clé de partition | Cassandra | Logs, télémétrie |
| Relationnel | Une ligne typée | SQL, jointures | PostgreSQL | Transactions, facturation |

Chaque famille répond à une **forme de question**, pas à une taille de données.

---

## 5. Le théorème CAP : ce qu'il dit, et ce qu'il ne dit pas

Lisez cette section deux fois. C'est celle où circulent le plus de versions fausses, y compris dans des supports de cours.

### Trois propriétés, dans un système distribué sur plusieurs machines

- **C — Cohérence** (*Consistency*) : toute lecture renvoie l'écriture la plus récente. Tout le monde voit la même chose au même moment.
- **A — Disponibilité** (*Availability*) : toute requête reçoit une réponse, même si des machines sont tombées.
- **P — Tolérance au partitionnement** (*Partition tolerance*) : le système continue de fonctionner même si le réseau se coupe entre deux groupes de machines.

Le théorème énonce que **lorsqu'un partitionnement réseau se produit, il faut choisir entre C et A**. Impossible d'avoir les deux à cet instant.

### Concrètement

Deux serveurs répliquent les mêmes données, un à Lille, un à Marseille. Le câble entre les deux est coupé. Un joueur écrit à Lille. Un autre lit à Marseille. Deux options, pas trois :

- **Option 1.** Marseille répond : « je ne peux pas garantir que ma donnée est à jour, je refuse de répondre. » Cohérence gardée, disponibilité perdue.
- **Option 2.** Marseille répond avec sa version, potentiellement périmée. Disponibilité gardée, cohérence perdue.

Il n'y a pas de troisième porte. C'est tout ce que dit CAP.

### L'erreur classique

On lit souvent « choisissez 2 propriétés sur 3 », comme si l'on pouvait construire un système « CA » qui renoncerait au partitionnement. **C'est trompeur.** Dans un système distribué, les coupures réseau ne sont pas une option que l'on décline : elles arrivent. P n'est donc pas un choix. Le vrai arbitrage est : **cohérence ou disponibilité, quand le réseau casse.**

Et quand tout va bien ? CAP ne dit rien du tout. C'est précisément sa limite.

### PACELC, l'extension qui comble ce vide

*En cas de **P**artitionnement, arbitrer entre **A**vailability et **C**onsistency ; **E**lse (le reste du temps), arbitrer entre **L**atency et **C**onsistency.* La deuxième moitié est souvent la plus utile en pratique : les partitions sont rares, la latence est un problème permanent. Retenez le nom et l'idée, pas plus.

---

## 6. ACID et BASE : deux contrats différents

**ACID**, le contrat du relationnel, que vous connaissez depuis la première année :

- **Atomicité** : tout ou rien.
- **Cohérence** : les contraintes tiennent.
- **Isolation** : les transactions ne se gênent pas.
- **Durabilité** : une fois écrit, c'est écrit.

**BASE**, l'acronyme conçu par contraste :

- **Ba**sically **A**vailable : le système répond, même dégradé.
- **S**oft state : l'état peut changer sans écriture, par propagation.
- **E**ventually consistent : si l'on arrête d'écrire, tous les nœuds convergeront vers la même valeur, au bout d'un moment.

La question n'est pas « lequel est le meilleur », mais **« de quoi cette donnée a-t-elle besoin ? »**

### L'exemple à retenir

Vous postez un commentaire. Un ami le voit tout de suite, un autre ne le voit qu'au bout de deux secondes. Est-ce grave ? Non.

Maintenant : vous achetez un skin à 500 pièces d'or, et vous en avez 500. Vous cliquez deux fois très vite. Sur un système « éventuellement cohérent », les deux achats peuvent partir avant que le solde ne soit à jour, et vous repartez avec deux skins pour 500 pièces. Est-ce grave ? **Oui.**

Le même défaut technique, deux secondes de retard, est anodin dans un cas et grave dans l'autre. La différence ne vient pas de la technique. Elle vient de la nature de la donnée. **La même faiblesse technique est anodine ou grave selon la donnée concernée.** C'est pour cette raison que la monnaie virtuelle de PixelHub restera dans PostgreSQL toute l'année.

### Deux idées fausses à évacuer tout de suite

1. **« NoSQL = pas de transactions. »** Faux. MongoDB gère les transactions multi-documents depuis la version 4.0. La différence n'est pas « transactions ou pas », c'est le **périmètre** et le **coût** de la garantie.
2. **« NoSQL = pas de schéma. »** Imprécis. Il n'y a pas de schéma imposé par le serveur, mais il y a toujours un schéma : il vit dans le code de votre application. On dit *schema-on-read* (le schéma s'applique à la lecture) plutôt que *schema-on-write*. **Le schéma n'a pas disparu, il a changé de responsable.** Et le nouveau responsable, c'est vous : plus personne ne vous empêche d'écrire n'importe quoi.

> **Une question légitime : « pourquoi ne pas simplement stocker du JSON dans une colonne PostgreSQL ? »** Parce que c'est souvent une bonne idée. PostgreSQL a un type `jsonb` performant et indexable, et pour beaucoup de projets réels, c'est le bon choix, plus simple qu'ajouter un moteur. On va quand même étudier MongoDB, parce que l'objectif du module est de comprendre les *paradigmes*, et parce qu'à grande échelle un moteur documentaire natif offre des outils (agrégation, distribution) que `jsonb` n'a pas. Gardez cette question : c'est exactement le réflexe critique attendu en séance 5.

---

## 7. La persistance polyglotte : ce qu'on va construire

Conclusion de tout ce qui précède : ces moteurs ne sont pas des concurrents dont il faudrait élire le meilleur. Ce sont des **outils spécialisés**. Une application sérieuse peut très bien en faire cohabiter plusieurs, chacun sur les données pour lesquelles il est bon. Cela s'appelle la **persistance polyglotte**, et c'est ce que l'on va construire.

| Donnée de PixelHub | Moteur | Pourquoi |
|---|---|---|
| Catalogue de jeux | **MongoDB** (document) | Métadonnées très variables selon le genre |
| Classements, matchmaking, joueurs en ligne | **Redis** (clé-valeur) | Accès très fréquent, données éphémères, structures dédiées |
| Amis, guildes, recommandations | **Neo4j** (graphe) | Parcours de relations en profondeur |
| Monnaie virtuelle, achats | **PostgreSQL** (relationnel) | ACID non négociable : on ne débite pas deux fois un joueur |

Une application, plusieurs bases, chacune sur les données pour lesquelles elle est bonne. Un moteur ajouté par séance, dans la *même* application. Et la séance 5 sera consacrée au **prix à payer** pour cette cohabitation : que se passe-t-il quand un jeu change de nom et qu'il est stocké dans trois bases ?

Comme on va faire tourner quatre bases de données en même temps sur vos machines, on ne va pas les installer une par une. On va utiliser **Docker** : c'est l'objet du TP 1.

---

## 8. Ce qu'il faut retenir

- **Le relationnel n'est pas dépassé.** Il a un domaine de conception. Certaines formes de données en sortent, ce n'est pas la même chose.
- **Quatre familles, quatre formes de données.** Clé-valeur, document, graphe, colonnes larges. Chacune répond à une forme de question, pas à une taille de données.
- **Quand le réseau casse : cohérence ou disponibilité.** CAP ne propose pas trois portes, il en propose deux. Et il ne dit rien du reste du temps.
- **Le même retard est anodin ou grave selon la donnée.** Deux secondes sur un classement, personne ne le voit. Deux secondes sur un solde, on paie deux fois.

Séance 2 : le modèle documentaire, c'est-à-dire la réponse à l'exercice du catalogue.

---

## 9. Vérifiez que vous avez compris

Répondez par écrit, puis comparez avec les réponses plus bas.

1. Citez trois raisons distinctes pour lesquelles on cherche parfois autre chose que du relationnel.
2. Pourquoi la modélisation `Jeu` + `Attribut(jeu_id, cle, valeur)` est-elle une mauvaise solution, alors qu'elle « marche » ?
3. Dans quelle famille rangez-vous : un panier de session web ? un catalogue de produits aux fiches hétérogènes ? « les amis de mes amis » ? les logs d'un parc de capteurs ?
4. Pourquoi ne peut-on pas « demander tous les enregistrements où X > 3 » à un store clé-valeur ?
5. Que signifie exactement le théorème CAP, et pourquoi la formulation « choisissez 2 sur 3 » est-elle trompeuse ?
6. Dans l'exemple Lille / Marseille, quelle option choisiriez-vous pour un solde de monnaie virtuelle ? Pour un compteur de « j'aime » ?
7. Vrai ou faux : « avec MongoDB, il n'y a pas de transactions » ; « avec MongoDB, il n'y a pas de schéma ».
8. Pourquoi la monnaie virtuelle de PixelHub reste-t-elle dans PostgreSQL alors que le reste migre ?

### Réponses

1. Le schéma variable (le catalogue) ; les jointures en profondeur (les amis des amis) ; la montée en charge horizontale (répartir sur plusieurs machines) ; les données éphémères à accès intensif (joueurs en ligne). Trois suffisent.
2. La colonne `valeur` est un `VARCHAR` : plus de typage, plus de comparaison numérique propre, et chaque attribut lu coûte une jointure. C'est le motif Entity-Attribute-Value, ingérable à l'usage.
3. Clé-valeur (Redis) ; document (MongoDB) ; graphe (Neo4j) ; colonnes larges (Cassandra).
4. Parce que la valeur est opaque pour le moteur : il ne sait retrouver une valeur que par sa clé. Sans la clé, il faudrait tout parcourir.
5. Quand un partitionnement réseau se produit, il faut choisir entre cohérence et disponibilité. « 2 sur 3 » laisse croire qu'on peut renoncer à P ; or les coupures arrivent, P n'est pas un choix. Et CAP ne dit rien quand le réseau fonctionne.
6. Solde : option 1, cohérence, quitte à refuser de répondre. Compteur de « j'aime » : option 2, disponibilité, une valeur légèrement périmée est acceptable.
7. Faux (transactions multi-documents depuis MongoDB 4.0 ; ce qui change, c'est le périmètre et le coût). Imprécis (pas de schéma imposé par le serveur, mais un schéma dans le code : *schema-on-read*).
8. Parce qu'un débit doit être atomique et isolé : deux clics rapides ne doivent jamais produire deux achats pour un seul solde. ACID est non négociable sur cette donnée, et le relationnel le garantit.

---

## Et maintenant : le TP 1

1. Si ce n'est pas fait, installez Docker et le SDK .NET avec `TP1_annexe_installation_etudiants.md`.
2. Récupérez le dépôt de départ (archive `pixelhub-seance1-depart.zip`).
3. Suivez `TP1_etudiants_Environnement.md` : lire le `docker-compose.yml` avant de le lancer, démarrer les quatre moteurs, faire tourner PixelHub sur PostgreSQL, et arrêter proprement.

Gardez la feuille de l'exercice du catalogue : vous en aurez besoin en séance 2.
