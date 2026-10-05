# TP 2 — Le catalogue de jeux dans MongoDB

**R5.A.10 — Nouveaux paradigmes de bases de données**
Durée : 1 h 30 · À rendre : le code sur votre dépôt en fin de séance

---

## Objectif

PixelHub tourne aujourd'hui avec PostgreSQL. À la fin de ce TP, il tournera avec **deux moteurs** : PostgreSQL pour les joueurs, MongoDB pour le catalogue de jeux.

Vous allez :

1. manipuler des documents directement dans le shell MongoDB, sans C# ;
2. modéliser le catalogue et constater ce que la souplesse de schéma permet — et permet de casser ;
3. brancher MongoDB dans l'application, **sans casser** ce qui existe ;
4. écrire une agrégation.

> **Règle de la séance** : `/players` doit continuer à fonctionner à la fin. On ajoute un moteur, on ne remplace rien.

---

## Avant de commencer

```bash
cd pixelhub
docker compose up -d
docker compose ps
```

Vérifiez que `postgres` et `mongo` sont en `running`. Si vous étiez absent la séance dernière, ou si votre projet est cassé, récupérez l'état de départ auprès de l'enseignant (archive `seance1-fin`) — ne perdez pas la séance à réparer.

Récupérez également le fichier **`data/games.json`** fourni dans le dépôt.

> **Vous avez dû lancer l'API avec `dotnet run -p:UseAppHost=false` au TP 1 ?** Rendez ce réglage permanent plutôt que de le retaper à chaque fois : dans `src/PixelHub.Api/PixelHub.Api.csproj`, ajoutez la ligne suivante dans le `<PropertyGroup>` existant (à côté de `<TargetFramework>`).
>
> ```xml
> <UseAppHost>false</UseAppHost>
> ```
>
> `dotnet run` et `dotnet watch run` démarreront alors l'API via `dotnet`, sans fabriquer de `PixelHub.Api.exe` que le poste pourrait bloquer. Voir **Problèmes fréquents**.

---

## Partie 1 — MongoDB sans C# (30 min)

On commence par le shell. Le driver .NET ajoute une couche de sérialisation et de typage qui masque le modèle : vingt minutes de requêtes brutes vous donnent une intuition que le C# ne donnera pas.

### 1.1 Importer le catalogue

```bash
docker compose cp data/games.json mongo:/tmp/games.json

docker compose exec mongo mongoimport \
  -u pixelhub -p pixelhub_dev --authenticationDatabase admin \
  --db pixelhub --collection jeux --jsonArray --file /tmp/games.json
```

> Notez `--authenticationDatabase admin`. Sans lui, l'authentification échoue. La question **Q3** vous demandera pourquoi.

### 1.2 Ouvrir le shell

```bash
docker compose exec mongo mongosh -u pixelhub -p pixelhub_dev --authenticationDatabase admin
```

Puis :

```javascript
use pixelhub
```

### 1.3 Exercices

Écrivez et exécutez les requêtes suivantes. Notez le nombre de résultats de chacune.

```javascript
// 1. Combien de jeux dans la collection ?
db.jeux.countDocuments()

// 2. Afficher un document en entier
db.jeux.findOne()
```

**Q1.** Vous retrouvez le champ `_id`, déjà aperçu au TP 1 (étape 6.2), que personne n'a écrit dans `games.json`. Cette fois, intéressez-vous à **qui l'a fabriqué** : le serveur MongoDB, ou l'outil qui a envoyé les documents (`mongoimport`) ? Comparez avec l'`Id` 4 de *Pixel* au TP 1 (Q8) : qui l'avait choisi, et à quel moment le connaissiez-vous ?

```javascript
// 3. Tous les FPS
db.jeux.find({ genre: "FPS" })

// 4. Les jeux notés au moins 4.5 — titre et note seulement
db.jeux.find({ note: { $gte: 4.5 } }, { titre: 1, note: 1, _id: 0 })

// 5. Les jeux disponibles sur Switch
db.jeux.find({ plateformes: "Switch" }, { titre: 1, _id: 0 })
```

**Q2.** À l'exercice 5, `plateformes` est un tableau et vous avez écrit `{ plateformes: "Switch" }`, sans opérateur particulier. Comment auriez-vous fait la même chose en SQL, avec un modèle relationnel normalisé ?

```javascript
// 6. Les jeux coopératifs (via les tags)
db.jeux.find({ tags: "coopératif" }, { titre: 1, _id: 0 })

// 7. Les jeux qui POSSÈDENT un champ joueursParEquipe
db.jeux.find({ joueursParEquipe: { $exists: true } },
             { titre: 1, joueursParEquipe: 1, _id: 0 })
```

**Q3.** Vous tapez `--authenticationDatabase admin` depuis le TP 1 sans qu'on vous ait dit pourquoi. Pourquoi faut-il l'ajouter aux commandes `mongoimport` et `mongosh` ? Où se trouve le compte `pixelhub` ?

### 1.4 L'expérience à faire

```javascript
// 8. Insérer un jeu avec des champs que personne d'autre n'a
db.jeux.insertOne({
  titre: "Un jeu de test",
  genre: "Puzzle",
  note: 3.5,
  nombreNiveaux: 120,
  champCompletementInvente: "ça marche quand même"
})

db.jeux.countDocuments()
```

**Q4.** Personne ne vous a arrêté. Est-ce une bonne nouvelle ou un problème ? Argumentez en imaginant un projet à quatre développeurs, six mois plus tard.

```javascript
// 9. Une faute de frappe volontaire — que se passe-t-il ?
db.Jeux.find({ genre: "FPS" })
```

**Q5.** Le résultat de l'exercice 9 vous surprend-il ? Que s'est-il passé exactement, et pourquoi n'y a-t-il eu **aucun message d'erreur** ?

### 1.5 Modifier et supprimer

```javascript
// 10. Corriger une note
db.jeux.updateOne({ titre: "Valorant" }, { $set: { note: 4.3 } })
db.jeux.find({ titre: "Valorant" }, { titre: 1, note: 1, _id: 0 })

// 11. Ajouter un tag à un jeu (sans écraser les tags existants)
db.jeux.updateOne({ titre: "Terraria" }, { $push: { tags: "sandbox" } })

// 12. Ajouter un champ qui n'existait pas encore sur ce document
db.jeux.updateOne({ titre: "Terraria" }, { $set: { nbVotes: 0 } })

// 13. Incrémenter un compteur
db.jeux.updateOne({ titre: "Terraria" }, { $inc: { nbVotes: 1 } })
db.jeux.updateOne({ titre: "Terraria" }, { $inc: { nbVotes: 1 } })

// 14. Supprimer un champ
db.jeux.updateOne({ titre: "Terraria" }, { $unset: { nbVotes: "" } })

// 15. Marquer tous les FPS d'un coup
db.jeux.updateMany({ genre: "FPS" }, { $set: { competitif: true } })
```

```javascript
// 16. Essayez ceci — sans $set
db.jeux.updateOne({ titre: "Valorant" }, { note: 4.4 })
```

**Q6.** L'exercice 16 échoue. Recopiez le message d'erreur, et expliquez pourquoi MongoDB refuse. Quelle commande utiliseriez-vous si vous vouliez **réellement** remplacer le document en entier ?

**Q7.** À l'exercice 12, vous avez ajouté un champ `nbVotes` à un seul document, alors que les dix autres n'en ont pas. Quelle commande SQL aurait été nécessaire pour faire l'équivalent en relationnel, et quelle en aurait été la conséquence sur les autres lignes ?

---

## Partie 2 — MongoDB dans PixelHub (45 min)

Quittez le shell (`exit`) et ouvrez la solution dans votre IDE.

### 2.1 Le paquet

```bash
cd src/PixelHub.Api
dotnet add package MongoDB.Driver
```

### 2.2 La configuration

Dans `appsettings.json` — **on ajoute, on ne remplace pas** :

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Port=15432;Database=pixelhub;Username=pixelhub;Password=pixelhub_dev",
    "Mongo": "mongodb://pixelhub:pixelhub_dev@localhost:27018/?authSource=admin"
  },
  "Mongo": {
    "Database": "pixelhub"
  }
}
```

### 2.3 Le modèle

Créez `Models/Game.cs` :

```csharp
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace PixelHub.Api.Models;

public class Game
{
    [BsonId]
    public ObjectId Id { get; set; }

    [BsonElement("titre")]
    public string Titre { get; set; } = "";

    [BsonElement("genre")]
    public string Genre { get; set; } = "";

    [BsonElement("note")]
    public double Note { get; set; }

    [BsonElement("anneeSortie")]
    public int AnneeSortie { get; set; }

    [BsonElement("plateformes")]
    public List<string> Plateformes { get; set; } = new();

    [BsonElement("tags")]
    public List<string> Tags { get; set; } = new();
}
```

### 2.4 La couche d'accès, derrière une interface

Créez `Repositories/IGameCatalog.cs` :

```csharp
using PixelHub.Api.Models;

namespace PixelHub.Api.Repositories;

public interface IGameCatalog
{
    Task<List<Game>> GetAllAsync();
    Task<List<Game>> GetByGenreAsync(string genre);
    Task<List<Game>> GetTopRatedAsync(int count);
}
```

Puis `Repositories/MongoGameCatalog.cs` :

```csharp
using MongoDB.Driver;
using PixelHub.Api.Models;

namespace PixelHub.Api.Repositories;

public class MongoGameCatalog : IGameCatalog
{
    private readonly IMongoCollection<Game> _jeux;

    public MongoGameCatalog(IMongoDatabase database)
    {
        _jeux = database.GetCollection<Game>("jeux");
    }

    public async Task<List<Game>> GetAllAsync() =>
        await _jeux.Find(_ => true).ToListAsync();

    public async Task<List<Game>> GetByGenreAsync(string genre) =>
        await _jeux.Find(g => g.Genre == genre).ToListAsync();

    public async Task<List<Game>> GetTopRatedAsync(int count) =>
        await _jeux.Find(_ => true)
                   .SortByDescending(g => g.Note)
                   .Limit(count)
                   .ToListAsync();
}
```

**Q8.** Lisez `IGameCatalog`. Y a-t-il un seul endroit dans cette interface où le mot « Mongo » apparaît ? Pourquoi est-ce important, à votre avis ?

### 2.5 L'enregistrement

Dans `Program.cs`, **tout en haut du fichier**, à la suite des `using` déjà présents :

```csharp
using MongoDB.Driver;
using PixelHub.Api.Repositories;
```

> Les `using` se placent **avant toute autre instruction**. Collés au milieu du fichier, ils provoquent l'erreur de compilation `CS1529`.

Puis, **après** la configuration PostgreSQL existante (le `AddDbContext`) et **avant** `var app = builder.Build();` :

```csharp
// Le MongoClient est thread-safe et gère son propre pool de connexions :
// on l'enregistre donc en singleton.
builder.Services.AddSingleton<IMongoClient>(_ =>
    new MongoClient(builder.Configuration.GetConnectionString("Mongo")));

builder.Services.AddSingleton<IMongoDatabase>(sp =>
    sp.GetRequiredService<IMongoClient>()
      .GetDatabase(builder.Configuration["Mongo:Database"]));

builder.Services.AddSingleton<IGameCatalog, MongoGameCatalog>();
```

### 2.6 Les endpoints

```csharp
app.MapGet("/games", async (IGameCatalog catalog) =>
    await catalog.GetAllAsync());

app.MapGet("/games/genre/{genre}", async (string genre, IGameCatalog catalog) =>
    await catalog.GetByGenreAsync(genre));

app.MapGet("/games/top/{count:int}", async (int count, IGameCatalog catalog) =>
    await catalog.GetTopRatedAsync(count));
```

Le fichier `PixelHub.Api.http` ne connaît encore que `/players`. Ajoutez-y, à la fin, les trois requêtes du catalogue :

```http
### Séance 2 — MongoDB : catalogue complet
GET {{host}}/games
Accept: application/json

### Séance 2 — filtrage par genre
GET {{host}}/games/genre/FPS
Accept: application/json

### Séance 2 — top 3
GET {{host}}/games/top/3
Accept: application/json
```

Les `###` séparent les requêtes : sans eux, le fichier n'en voit qu'une seule.

### 2.7 Lancer — et lire l'erreur

```bash
dotnet run
```

(ou `dotnet watch run`, comme au TP 1 ; ajoutez `-p:UseAppHost=false` si votre poste l'exige et que vous n'avez pas modifié le `.csproj`.)

Appelez `/games` depuis le fichier `.http`.

**Ça va probablement échouer.** C'est prévu. Lisez le message d'exception attentivement avant de continuer.

**Q9.** Quelle exception obtenez-vous, et sur quel champ ? Expliquez la cause : qu'est-ce que le driver a essayé de faire, et pourquoi n'a-t-il pas su ?

### 2.8 Corriger

Ajoutez l'attribut `[BsonIgnoreExtraElements]` sur la classe `Game` :

```csharp
[BsonIgnoreExtraElements]
public class Game
{
    // ...
}
```

Relancez. `/games` doit maintenant renvoyer le catalogue.

> Le champ `id` s'affiche sous une forme étrange, `{ "timestamp": …, "creationTime": … }`. C'est normal : le sérialiseur JSON d'ASP.NET Core ne connaît pas le type `ObjectId` et en recopie les propriétés publiques. Ce n'est pas un bug de vos données, on le règle en séance 3. Au passage, `creationTime` confirme votre réponse à la Q1 : un `ObjectId` contient la date de sa fabrication.

**Q10.** `[BsonIgnoreExtraElements]` fait disparaître l'erreur, mais **au prix de quoi** ? Que devient `joueursParEquipe` quand vous appelez `/games` ?

### 2.9 Récupérer quand même les champs spécifiques

Essayez cette variante. Ajoutez en haut de `Models/Game.cs` :

```csharp
using System.Text.Json.Serialization;
```

puis, dans la classe `Game` (gardez `[BsonIgnoreExtraElements]`) :

```csharp
// Côté MongoDB : tous les champs non déclarés atterrissent ici.
[BsonExtraElements, JsonIgnore]
public BsonDocument AutresChamps { get; set; } = new();

// Côté API : les mêmes champs, convertis en types .NET que le JSON sait écrire.
[BsonIgnore]
public Dictionary<string, object> Specifiques => AutresChamps.ToDictionary();
```

Relancez et rappelez `/games` : chaque jeu porte maintenant un objet `specifiques` (`joueursParEquipe`, `cartes`, `nombreCircuits`…).

> **Pourquoi deux propriétés ?** Le `BsonDocument` sait parler à MongoDB, mais pas au sérialiseur JSON d'ASP.NET Core : renvoyé tel quel, il fait planter `/games` avec une `InvalidCastException` (voir **Problèmes fréquents**). `[JsonIgnore]` le cache à l'API, `[BsonIgnore]` cache la copie à MongoDB. Encore un endroit où le typage de C# et la souplesse du moteur se frottent.

**Une fois la Q11 rédigée, retirez ces deux propriétés et le `using` ajouté** : la suite du module (le cache Redis de la séance 3) repart de la classe `Game` de l'étape 2.8.

**Q11.** Comparez les trois approches possibles pour gérer un schéma variable en C# : `[BsonIgnoreExtraElements]`, `[BsonExtraElements]`, et une hiérarchie de classes (`FpsGame : Game`, etc.). Quel est l'avantage et l'inconvénient de chacune ?

### 2.10 Vérification obligatoire

- `/players` fonctionne **toujours** (PostgreSQL intact)
- `/games` renvoie le catalogue
- `/games/genre/FPS` filtre correctement
- `/games/top/3` renvoie les trois mieux notés

---

## Partie 3 — Une agrégation (15 min)

Déclarez d'abord le type du résultat dans `Repositories/IGameCatalog.cs`, **au-dessus de l'interface** (et non à l'intérieur de `MongoGameCatalog`, sinon ni l'interface ni le cache de la séance 3 ne le trouveront) :

```csharp
public record GenreStats(string Genre, double NoteMoyenne, int Nombre);
```

Puis ajoutez dans `MongoGameCatalog` :

```csharp
public async Task<List<GenreStats>> GetStatsByGenreAsync()
{
    return await _jeux.Aggregate()
        .Group(g => g.Genre, group => new GenreStats(
            group.Key,
            group.Average(g => g.Note),
            group.Count()))
        .SortByDescending(s => s.NoteMoyenne)
        .ToListAsync();
}
```

Ajoutez la méthode à l'interface (`Task<List<GenreStats>> GetStatsByGenreAsync();`), puis l'endpoint :

```csharp
app.MapGet("/games/stats", async (IGameCatalog catalog) =>
    await catalog.GetStatsByGenreAsync());
```

Et sa requête, à la fin de `PixelHub.Api.http` :

```http
### Séance 2 — agrégation : note moyenne par genre
GET {{host}}/games/stats
Accept: application/json
```

**Q12.** Écrivez la requête SQL qui produirait le même résultat sur une table `jeux(titre, genre, note)`. Comparez les deux. Est-ce ici que MongoDB apporte quelque chose par rapport à PostgreSQL ? Si non, où l'apport se situe-t-il dans ce TP ?

---

## Avant de partir — checklist

- [ ] `db.jeux.countDocuments()` renvoie 11 (10 jeux + le jeu de test)
- [ ] `/players` fonctionne (rien de cassé côté PostgreSQL)
- [ ] `/games`, `/games/genre/FPS`, `/games/top/3` fonctionnent
- [ ] `/games/stats` renvoie une moyenne par genre
- [ ] Je sais expliquer à quoi sert `[BsonIgnoreExtraElements]` et pourquoi j'en ai eu besoin
- [ ] Je sais dire, sur un exemple, pourquoi j'imbriquerais ou je référencerais
- [ ] Le code est poussé sur mon dépôt

**Question orale de l'enseignant** : *« Les avis d'un jeu : tu imbriques ou tu référencies ? »*

---

## Problèmes fréquents

### L'API ne démarre pas sur un poste de l'IUT (`PixelHub.Api.exe` bloqué)

**Symptôme** : `dotnet run` compile, puis échoue au moment de lancer l'API ; le message met en cause `PixelHub.Api.exe`. C'est le blocage déjà rencontré au TP 1.

**Cause** : par défaut, `dotnet run` fabrique un exécutable `PixelHub.Api.exe` et le lance. Sur certains postes, cet `.exe` est bloqué.

**Solution** : `dotnet run -p:UseAppHost=false`, qui démarre l'API via `dotnet` sans produire d'`.exe`. Pour ne plus y penser, ajoutez `<UseAppHost>false</UseAppHost>` dans le `<PropertyGroup>` du `.csproj` (voir **Avant de commencer**) : le réglage vaut alors aussi pour `dotnet watch run`.

### `CS1529: A using clause must precede all other elements`

Les `using` de l'étape 2.5 ont été collés au milieu de `Program.cs`. Remontez-les tout en haut du fichier, avec les autres.

### `InvalidCastException: Unable to cast object of type 'MongoDB.Bson.BsonInt32' to type 'MongoDB.Bson.BsonBoolean'`

**Symptôme** : à l'étape 2.9, `/games` répond `500` dès que la propriété `[BsonExtraElements]` est ajoutée.

**Cause** : la propriété `BsonDocument` est renvoyée telle quelle à l'API. Le sérialiseur JSON d'ASP.NET Core ne connaît pas ce type : il en lit toutes les propriétés, dont `AsBoolean`, qui lève une exception sur un champ qui n'est pas un booléen.

**Solution** : la version de l'étape 2.9, avec `[JsonIgnore]` sur le `BsonDocument` et la propriété `Specifiques` en dictionnaire.

### `MongoAuthenticationException` / « Authentication failed »

Le mot de passe est bon, mais il manque `?authSource=admin` dans la chaîne de connexion (ou `--authenticationDatabase admin` dans les commandes du shell). Voir la Q3.

### `A timeout occurred after 30000ms selecting a server`

Trente secondes d'attente puis une erreur qui ne mentionne pas le port : c'est presque toujours le **port**. Vérifiez que la chaîne utilise bien `27018` et non `27017`, et que `.env` et `appsettings.json` sont cohérents.

### `FormatException: Element '...' does not match any field`

C'est l'erreur attendue à l'étape 2.7. Voir Q9 et Q10.

### `db.jeux.find()` renvoie un tableau vide alors que les données sont là

Vérifiez l'orthographe **et la casse** du nom de la collection, et que vous avez bien fait `use pixelhub`. MongoDB est sensible à la casse et ne signale rien. Voir Q5.

### Erreur de sérialisation autour de l'`Id`

`ObjectId` n'est pas une chaîne. Soit vous déclarez `ObjectId Id` avec `[BsonId]`, soit :

```csharp
[BsonId]
[BsonRepresentation(BsonType.ObjectId)]
public string Id { get; set; } = "";
```

---

## Pour aller plus loin (optionnel)

1. **Index et mesure.** Lancez `db.jeux.find({ genre: "FPS" }).explain("executionStats")` et relevez le nombre de documents examinés. Créez `db.jeux.createIndex({ genre: 1 })`, relancez, comparez. Que constatez-vous sur dix documents, et pourquoi ?

2. **Modéliser les avis.** Ajoutez des avis à un jeu, en **imbriqué**, puis écrivez la requête qui renvoie les jeux dont au moins un avis a la note 5.

3. **Validation de schéma.** Cherchez dans la documentation MongoDB comment imposer qu'un document de la collection `jeux` ait obligatoirement un champ `titre` de type chaîne. Testez, puis essayez d'insérer un document sans titre.

---

## Pour la prochaine séance

Une question à laquelle vous ne saurez pas répondre aujourd'hui, et c'est normal :

> PixelHub doit afficher le nombre de joueurs actuellement en ligne, mis à jour chaque seconde. Vous le stockez dans PostgreSQL, ou dans MongoDB ?

Réfléchissez-y. La réponse ouvre la séance 3.
