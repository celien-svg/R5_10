# TP 2 — Questions bonus

**R5.A.10 — Nouveaux paradigmes de bases de données**
Pour celles et ceux qui ont terminé le TP 2 et validé sa checklist · Durée : 1 h

---

## Les règles

Vous avez le droit d'utiliser une IA, la documentation, vos voisins. En revanche :

1. **Chaque réponse cite la sortie brute de *votre* terminal** ou de *votre* fichier `.http`, copiée telle quelle dans `notes.md`.
2. **L'enseignant tirera au sort deux questions, que vous défendrez à l'oral, sans écran.**
3. Une réponse que votre propre machine contredit vaut zéro, même bien rédigée.

Tout ce que vous ajoutez dans la base est **supprimé à la fin de chaque exercice** : votre collection `jeux` doit retrouver ses 11 documents avant la séance 3.

| Exercice | Thème | Durée |
|---|---|---|
| B1 | Quatre requêtes surprenantes | 8 min |
| B2 | Votre `ObjectId` à vous | 8 min |
| B3 | Une note qui n'est pas un nombre | 12 min |
| B4 | « MongoDB sait faire des transactions » | 7 min |
| B5 | Réimporter sans tout casser | 10 min |
| B6 | Un jeu par son identifiant : `GET /games/{id}` | 10 min |
| B7 | Combien de jeux par plateforme ? | 5 min |

---

## B1 — Quatre requêtes surprenantes (8 min)

Ajoutez ces requêtes à votre fichier `.http`, envoyez-les, et notez le résultat exact (code HTTP, nombre de jeux, lesquels) :

| Requête | Résultat |
|---|---|
| `GET /games/genre/fps` | |
| `GET /games/genre/Roguelike` | |
| `GET /games/top/0` | |
| `GET /games/top/3`, chez vous **et** chez votre voisin | |

**B1.1** Pour chacune des trois premières, expliquez le résultat : qui (ASP.NET Core, le driver, MongoDB) a pris quelle décision ?

**B1.2** Pour `/games/top/3`, regardez les notes : que remarquez-vous sur la 3e place ? Le résultat est-il **garanti** identique sur toutes les machines ? Justifiez avec la documentation de MongoDB sur le tri.

**B1.3** Corrigez l'API pour que :
- `/games/top/0` (et toute valeur négative) réponde `400 Bad Request` ;
- `/games/top/3` renvoie un résultat **déterministe**.

Notez les lignes modifiées.

---

## B2 — Votre `ObjectId` à vous (8 min)

```javascript
db.jeux.find({}, { titre: 1 })
```

**B2.1** Prenez le `_id` de *Valorant*. Ses **8 premiers caractères hexadécimaux** sont un nombre de secondes depuis le 1er janvier 1970. Convertissez-les en décimal, puis en date et heure (à la main ou avec une calculatrice, **pas** avec une fonction MongoDB). À quoi correspond cette date ? Vérifiez ensuite avec `ObjectId("<votre _id>").getTimestamp()`.

**B2.2** Comparez les `_id` des dix jeux importés par `mongoimport`. Quelle partie est identique d'un jeu à l'autre, quelle partie change, et comment ? Comparez avec le `_id` de « Un jeu de test », inséré plus tard depuis `mongosh`.

**B2.3** Votre voisin a importé le même fichier. Pourquoi vos `_id` sont-ils différents ? Comment MongoDB évite-t-il les doublons **sans** demander de compteur au serveur ?

---

## B3 — Une note qui n'est pas un nombre (12 min)

Dans `mongosh`, base `pixelhub` :

```javascript
db.jeux.insertOne({
  titre: "Note piégée", genre: "FPS", note: "0.5",
  anneeSortie: 2026, plateformes: ["PC"], tags: ["test"]
})
```

Remarquez les guillemets autour de `0.5`. Relevez ensuite :
- la `note` de ce jeu dans `/games` ;
- sa place dans `/games/top/3` ;
- la ligne `FPS` de `/games/stats` (moyenne **et** nombre), comparée à celle d'avant l'insertion.

**B3.1** Expliquez chacun des trois résultats. Pour le classement, appuyez-vous sur la documentation MongoDB (*Comparison/Sort Order*). Pourquoi l'API, elle, ne voit-elle rien d'anormal ?

Ajoutez un deuxième document :

```javascript
db.jeux.insertOne({
  titre: "Genre fantôme", genre: "Nouveau", note: "3",
  anneeSortie: 2026, plateformes: ["PC"], tags: ["test"]
})
```

Rappelez `/games`, puis `/games/stats`.

**B3.2** Le même document casse un endpoint et pas l'autre. Expliquez pourquoi, en citant le message d'erreur exact.

**B3.3** Proposez **deux** protections, une côté MongoDB, une côté C#. Écrivez la commande MongoDB, testez-la (une insertion avec `note: "0.5"` doit être refusée), puis **retirez-la** :

```javascript
db.runCommand({ collMod: "jeux", validator: {} })
```

**Nettoyage obligatoire :**

```javascript
db.jeux.deleteMany({ titre: { $in: ["Note piégée", "Genre fantôme"] } })
db.jeux.countDocuments()   // 11
```

---

## B4 — « MongoDB sait faire des transactions » (7 min)

C'est vrai depuis la version 4.0, et le cours le dit. Essayez, dans `mongosh` :

```javascript
const s = db.getMongo().startSession()
s.startTransaction()
s.getDatabase("pixelhub").jeux.insertOne({ titre: "Dans une transaction" })
```

Terminez par `s.endSession()`, puis vérifiez que `db.jeux.countDocuments()` vaut toujours 11.

**B4.1** Recopiez le message d'erreur. Que faudrait-il changer dans le `docker-compose.yml` de PixelHub pour que ces trois lignes fonctionnent ? (Cherchez ; vous n'avez **pas** à le faire.)

**B4.2** En cinq lignes au plus : pourquoi PixelHub garde-t-il la monnaie virtuelle dans PostgreSQL ? Donnez au moins un argument **autre que** « MongoDB ne sait pas faire de transactions », puisque c'est faux en général.

---

## B5 — Réimporter sans tout casser (10 min)

On travaille dans une base à part, **`bonus`**, pour ne pas toucher à `pixelhub`. Lancez **deux fois** de suite :

```bash
docker compose exec mongo mongoimport \
  -u pixelhub -p pixelhub_dev --authenticationDatabase admin \
  --db bonus --collection jeux --jsonArray --file /tmp/games.json
```

**B5.1** Combien de documents dans `bonus.jeux` ? Pourquoi n'y a-t-il eu aucune erreur ?

Repartez d'une collection vide, réimportez **une seule fois** (10 documents), puis modifiez *Terraria* comme le feraient les joueurs :

```javascript
use bonus
db.jeux.deleteMany({})
// … réimport unique depuis le terminal …
db.jeux.updateOne({ titre: "Terraria" }, { $set: { note: 1.0, nbVotes: 42 } })
```

**B5.2** `mongoimport` propose `--drop`, `--mode upsert` et `--mode merge` (ces deux derniers avec `--upsertFields titre`). Essayez les trois, en refaisant l'`updateOne` entre deux essais. Pour chacune, relevez ce que deviennent `note` et `nbVotes` de *Terraria*.

**B5.3** Le catalogue est mis à jour chaque nuit à partir d'un fichier de l'éditeur, et les joueurs votent pendant la journée (`nbVotes`). Quelle option choisissez-vous, et que faudrait-il ajouter sur `titre` pour que ce soit sûr ?

**Nettoyage obligatoire :**

```javascript
db.getSiblingDB("bonus").dropDatabase()
```

---

## B6 — Un jeu par son identifiant : `GET /games/{id}` (10 min)

Ajoutez à l'API un endpoint `GET /games/{id}` qui renvoie un seul jeu, en passant par `IGameCatalog` comme les autres.

Testez-le avec trois valeurs, et notez le code HTTP de chacune :
- le `_id` réel de *Hades II* (récupérez-le dans `mongosh` : pourquoi pas dans `/games` ?) ;
- `abc` ;
- `000000000000000000000000`.

**B6.1** La méthode que vous avez ajoutée à `IGameCatalog` prend-elle un `string` ou un `ObjectId` ? Relisez votre réponse à la **Q8** : qu'est-ce que ce choix change ? Où faites-vous la conversion, et que doit répondre l'API pour `abc` : `400` ou `404` ? Défendez votre choix.

**B6.2** `/games/stats` fonctionne-t-il toujours ? Pourquoi ASP.NET Core ne prend-il pas `stats` pour un identifiant ?

> En séance 3, une deuxième classe implémentera `IGameCatalog` : elle devra elle aussi fournir cette méthode.

---

## B7 — Combien de jeux par plateforme ? (5 min)

Dans `mongosh` :

```javascript
db.jeux.aggregate([
  { $unwind: "$plateformes" },
  { $group: { _id: "$plateformes", nombre: { $sum: 1 } } },
  { $sort: { nombre: -1 } }
])
```

Puis remplacez les deux dernières étapes par `{ $count: "lignes" }`.

**B7.1** Combien de documents sortent de `$unwind`, et pourquoi plus que de jeux ? « Un jeu de test » est-il compté ? Pourquoi ?

**B7.2** Écrivez la requête SQL équivalente avec le modèle relationnel de votre réponse à la **Q2** (`Jeu`, `Plateforme`, `JeuPlateforme`). Que fait `$unwind`, dit en vocabulaire relationnel ? Pour **cette** question précise, quel modèle est le plus naturel ?

---

## Avant de rendre

- [ ] `notes.md` contient, pour chaque question, **la sortie brute et l'explication**
- [ ] `db.jeux.countDocuments()` renvoie 11 dans `pixelhub`, aucun validateur sur `jeux`, la base `bonus` est supprimée
- [ ] Les corrections de B1.3 et l'endpoint de B6 sont dans le code, et `/players`, `/games`, `/games/stats` fonctionnent toujours
- [ ] Je suis prêt à défendre deux de ces questions à l'oral, sans écran
