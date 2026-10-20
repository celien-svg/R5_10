# TP 4 bis — Neo4j, puis PixelHub à quatre moteurs

**R5.A.10 — Nouveaux paradigmes de bases de données**
Durée : 3 h · 1 h de Neo4j, puis 2 h de manipulation de toute l'application · Rien n'est noté aujourd'hui

> **Dernière séance avant l'évaluation.** L'évaluation (3 h, individuelle) comprendra **1 h de QCM et de questions** sur tout le module, puis **2 h de manipulation sur machine** : des requêtes à écrire dans les quatre consoles, du code à compléter, des pannes à observer. **Ce TP en est l'entraînement direct** : mêmes consoles, même format de code « à compléter », mêmes pannes.

---

## Objectif

Votre PixelHub tourne avec PostgreSQL, MongoDB et Redis (et son cache). À la fin de ce TP :

1. il saura répondre à « quels jeux possèdent les amis de mes amis, que je ne possède pas ? » (**Neo4j**) ;
2. il aura une **boutique** : un achat lit le prix dans MongoDB, débite le joueur dans PostgreSQL, et met à jour Neo4j et Redis ;
3. il aura une **fiche joueur** qui interroge les quatre moteurs pour une seule réponse ;
4. vous l'aurez **cassé** volontairement, et vous saurez dire quel moteur détient la vérité, et comment réparer les autres.

---

## Avant de commencer

```bash
cd pixelhub
docker compose up -d
docker compose ps          # les quatre moteurs doivent être "healthy"
```

**Neo4j met 20 à 40 secondes à démarrer** : `docker compose ps` doit afficher `pixelhub-neo4j` en `healthy`. Pour suivre son démarrage (Windows, macOS et Linux) : `docker compose logs --tail 5 neo4j`.

Ouvrez ensuite `http://localhost:17474` (attention au port, ce n'est pas 7474). L'écran de connexion propose **trois** champs, et le premier est piégé :

| Champ | Valeur |
|---|---|
| **Connect URL** | `neo4j://localhost:17687` — le Browser propose `7687` : **corrigez-le en `17687`** |
| **Username** | `neo4j` |
| **Password** | `pixelhub_dev` |

Avec `7687`, la connexion échoue, et le message ressemble à un mot de passe refusé : ce n'est pas le mot de passe, c'est le port.

Si votre projet ne compile pas ou si votre cache Redis ne fonctionne pas, demandez l'archive `seance3-fin`.

**Les quatre consoles** (à garder sous la main, elles serviront aussi à l'évaluation) :

| Moteur | Commande, depuis le dossier `pixelhub` |
|---|---|
| PostgreSQL | `docker compose exec postgres psql -U pixelhub -d pixelhub` |
| MongoDB | `docker compose exec mongo mongosh -u pixelhub -p pixelhub_dev --authenticationDatabase admin pixelhub` |
| Redis | `docker compose exec redis redis-cli` |
| Neo4j | le Browser, `http://localhost:17474` |

**Les durées sont strictes.** À **1h00**, on quitte Neo4j pour l'application complète, même si la partie 1 n'est pas finie : prenez alors l'archive `seance4-fin`.

---

# Partie 1 — Neo4j (1 h)

## 1.1 Importer le graphe (5 min)

Collez le contenu de `data/graph-import.cypher` dans la barre de commande du Browser, et exécutez. Le script utilise `MERGE` partout : vous pouvez le relancer sans risque.

```cypher
MATCH (n) RETURN count(n)
```

Vous devez obtenir **22 nœuds** (10 joueurs, 10 jeux, 2 guildes).

**Q1.** Le script utilise `MERGE` et non `CREATE`. Que se passerait-il si vous le lanciez deux fois avec `CREATE` ? À quoi servent les trois `CREATE CONSTRAINT` du début ?
si on lance create a lors que la table existe déja alors ça bug, les contrainte évite les doublon

## 1.2 La direction (5 min) — à faire attentivement

```cypher
// Les amis de Krayz — SANS flèche
MATCH (:Joueur {pseudo:'Krayz'})-[:AMI_DE]-(a:Joueur)
RETURN a.pseudo

// Les amis de Krayz — AVEC flèche
MATCH (:Joueur {pseudo:'Krayz'})-[:AMI_DE]->(a:Joueur)
RETURN a.pseudo
```

**Q2.** Combien de résultats pour chacune ? Ouvrez le script d'import et expliquez l'écart. Laquelle est correcte, et **pourquoi aucune erreur ne vous a prévenu** ?
2 puis 1 car l'un est a sens unique et l'autre prend les deux de la relation les deux sont bonne en fonction de ce que l'on recherche
## 1.3 Parcourir et recommander (10 min)

```cypher
// Amis et amis d'amis de Nova
MATCH (moi:Joueur {pseudo:'Nova'})-[:AMI_DE*1..2]-(a:Joueur)
WHERE a <> moi
RETURN DISTINCT a.pseudo
```

```cypher
// LA recommandation
MATCH (moi:Joueur {pseudo:'Nova'})-[:AMI_DE*1..2]-(ami:Joueur)-[:POSSEDE]->(j:Jeu)
WHERE ami <> moi AND NOT (moi)-[:POSSEDE]->(j)
RETURN j.titre, count(DISTINCT ami) AS nbAmis
ORDER BY nbAmis DESC
```

**Q3.** Remplacez `count(DISTINCT ami)` par `count(*)` : que compte chacune des deux versions ? Passez ensuite de `*1..2` à `*1..4` : combien de lignes changez-vous, et combien de CTE auriez-vous ajoutées en SQL ?

j'obtiens 7 jeux avec le nobre d'ami de de nova qui ont le jeux puis j'obtiens le nombre d'amis d'amis d'amis qui ont le jeux également. avec postgresql j'aurais dufaire pluisieur inner join pour avoir ce résultat

**Q4.** Pourquoi *Stardew Valley* n'apparaît-il jamais dans les recommandations de Nova ?

car il a déja le jeux

## 1.4 Neo4j dans PixelHub (35 min)

### Le paquet et la configuration

```bash
cd src/PixelHub.Api
dotnet add package Neo4j.Driver --version 6.3.0
```

Dans `appsettings.json` :

```json
{
  "Neo4j": {
    "Uri": "bolt://localhost:17687",
    "User": "neo4j",
    "Password": "pixelhub_dev"
  }
}
```

**Q5.** Le Browser est sur le port 17474, et l'application utilise 17687. Pourquoi deux ports pour le même serveur ?

### L'interface — `Repositories/ISocialGraph.cs`

```csharp
namespace PixelHub.Api.Repositories;

public record GameRecommendation(string Titre, int NbAmis);
public record FriendSuggestion(string Pseudo, int AmisCommuns);

public interface ISocialGraph
{
    Task<List<string>> GetFriendsAsync(string pseudo);
    Task<List<GameRecommendation>> RecommendGamesAsync(string pseudo, int profondeur = 2);
    Task<List<FriendSuggestion>> SuggestFriendsAsync(string pseudo);
}
```

### L'implémentation — `Repositories/Neo4jSocialGraph.cs`

```csharp
using Neo4j.Driver;

namespace PixelHub.Api.Repositories;

public class Neo4jSocialGraph : ISocialGraph
{
    private readonly IDriver _driver;

    public Neo4jSocialGraph(IDriver driver) => _driver = driver;

    // -[:AMI_DE]- SANS flèche : l'amitié est stockée dans un seul sens, mais elle est symétrique (Q4).
    public async Task<List<string>> GetFriendsAsync(string pseudo)
    {
        await using var session = _driver.AsyncSession();

        return await session.ExecuteReadAsync(async tx =>
        {
            var cursor = await tx.RunAsync(
                @"MATCH (:Joueur {pseudo: $pseudo})-[:AMI_DE]-(a:Joueur)
                  RETURN a.pseudo AS pseudo",
                new { pseudo });

            return await cursor.ToListAsync(r => r["pseudo"].As<string>());
        });
    }

    public async Task<List<GameRecommendation>> RecommendGamesAsync(string pseudo, int profondeur = 2)
    {
        // La profondeur ne peut pas être un paramètre Cypher : elle est interpolée,
        // donc bornée strictement avant (Q11).
        if (profondeur < 1 || profondeur > 4)
            throw new ArgumentOutOfRangeException(nameof(profondeur), "Profondeur attendue entre 1 et 4.");

        await using var session = _driver.AsyncSession();

        return await session.ExecuteReadAsync(async tx =>
        {
            var cursor = await tx.RunAsync(
                $@"MATCH (moi:Joueur {{pseudo: $pseudo}})-[:AMI_DE*1..{profondeur}]-(ami:Joueur)
                         -[:POSSEDE]->(j:Jeu)
                   WHERE ami <> moi AND NOT (moi)-[:POSSEDE]->(j)
                   RETURN j.titre AS titre, count(DISTINCT ami) AS nbAmis
                   ORDER BY nbAmis DESC",
                new { pseudo });

            return await cursor.ToListAsync(r =>
                new GameRecommendation(r["titre"].As<string>(), r["nbAmis"].As<int>()));
        });
    }

    public async Task<List<FriendSuggestion>> SuggestFriendsAsync(string pseudo)
    {
        await using var session = _driver.AsyncSession();

        return await session.ExecuteReadAsync(async tx =>
        {
            var cursor = await tx.RunAsync(
                @"MATCH (moi:Joueur {pseudo: $pseudo})-[:AMI_DE]-(c:Joueur)-[:AMI_DE]-(s:Joueur)
                  WHERE s <> moi AND NOT (moi)-[:AMI_DE]-(s)
                  RETURN s.pseudo AS pseudo, count(DISTINCT c) AS communs
                  ORDER BY communs DESC",
                new { pseudo });

            return await cursor.ToListAsync(r =>
                new FriendSuggestion(r["pseudo"].As<string>(), r["communs"].As<int>()));
        });
    }
}
```

**Q6.** Le pseudo est passé en paramètre (`$pseudo` + `new { pseudo }`), mais la profondeur est **interpolée** dans la chaîne. Pourquoi ? Quelle précaution le code prend-il, et que risquerait-on sans elle ?

Le code vérifie qu’elle est comprise entre 1 et 4 avant l’interpolation. Sans cette limite, une profondeur trop grande pourrait rendre le parcours du graphe très coûteux, voire surcharger le service. La validation empêche aussi les valeurs hors plage de produire une requête invalide. Comme la profondeur est typée int, ce contrôle limite surtout les valeurs incorrectes ou excessives ; le paramétrage de $pseudo, lui, protège contre l’injection via le pseudo.

### L'enregistrement — `Program.cs`

En haut du fichier :

```csharp
using Neo4j.Driver;
```

Avec les autres services, avant `builder.Build()` :

```csharp
// ---------- Neo4j (séance 4) ----------
// Le driver est partagé (singleton) ; la session, elle, est jetable, une par opération (Q12).
builder.Services.AddSingleton<IDriver>(_ =>
    GraphDatabase.Driver(
        builder.Configuration["Neo4j:Uri"],
        AuthTokens.Basic(
            builder.Configuration["Neo4j:User"],
            builder.Configuration["Neo4j:Password"])));

builder.Services.AddSingleton<ISocialGraph, Neo4jSocialGraph>();
```

**Q7.** `IDriver` en singleton, mais une **session** par méthode avec `await using` : pourquoi ? Quelle règle commune avec le `MongoClient` et le `ConnectionMultiplexer` ?
La même règle s’applique aux clients MongoDB et Redis : réutiliser un client partagé à longue durée de vie, plutôt que d’en créer un par requête ou méthode. Ces clients gèrent leurs connexions et leur pool en interne.
### Les endpoints

```csharp
// ---------- Séance 4 — Neo4j ----------
app.MapGet("/social/{pseudo}/friends",
    async (string pseudo, ISocialGraph g) => await g.GetFriendsAsync(pseudo));

app.MapGet("/social/{pseudo}/recommendations",
    async (string pseudo, int? depth, ISocialGraph g) =>
        await g.RecommendGamesAsync(pseudo, depth ?? 2));

app.MapGet("/social/{pseudo}/friend-suggestions",
    async (string pseudo, ISocialGraph g) => await g.SuggestFriendsAsync(pseudo));
```

Testez dans votre `.http` : `/social/Krayz/friends` doit renvoyer **Nova et Pixel** ; `/social/Nova/recommendations` puis `?depth=3` doivent différer.

> **1h00 : on s'arrête ici.** Si votre API ne répond pas sur `/social/Krayz/friends`, prenez l'archive `seance4-fin` et décompressez-la **à la place** de votre dossier `pixelhub` (vos données Docker sont conservées : elles sont dans les volumes, pas dans le dossier). Toute la suite part de cet état.

---

# Partie 2 — PixelHub ouvre sa boutique (2 h)

**Le scénario.** PixelHub vend désormais des jeux contre sa monnaie virtuelle. Un achat touche les **quatre** moteurs :

| Étape | Moteur | Pourquoi lui |
|---|---|---|
| Le jeu existe-t-il, et combien coûte-t-il ? | MongoDB | Le prix est un champ de la fiche du jeu, dans le catalogue |
| Le joueur paie, l'achat est tracé | PostgreSQL | **On ne débite pas deux fois un joueur** : transaction ACID |
| Le joueur possède le jeu | Neo4j | Pour que la recommandation ne le lui propose plus |
| Les meilleures ventes | Redis | Un classement, mis à jour à chaque vente |

Le code à écrire est donné, avec des **trous** numérotés `/* ① */`, `/* ② */`… : c'est le format de l'évaluation. Chaque trou fait **une ligne ou moins**, et l'indice est toujours dans le code que vous avez déjà écrit.

---

## Mission 1 — L'état des lieux, une console après l'autre (20 min)

Ouvrez les quatre consoles. Recopiez **chaque commande et son résultat** : c'est exactement ce qu'on vous demandera à l'évaluation.

### 1.1 PostgreSQL

```sql
SELECT "Pseudo", "Coins" FROM "Players" ORDER BY "Coins" DESC;
```

**Q8.** Pourquoi les guillemets doubles ? Que répond PostgreSQL si vous écrivez `SELECT * FROM players;` ?

Les guillemets doubles rendent les noms sensibles aux majuscules/minuscules. EF Core a créé la table et les colonnes avec leurs majuscules (`"Players"`, `"Pseudo"`, `"Coins"`). Sans guillemets, PostgreSQL convertit `players` en minuscules et cherche une table nommée `players` ; si seule `"Players"` existe, il renvoie une erreur du type `relation "players" does not exist`. Il faut donc écrire `SELECT * FROM "Players";`.

La boutique a besoin d'une table des achats. **EF Core ne la créera pas pour vous** : `EnsureCreated()` ne fait rien si la base existe déjà. Créez-la à la main, dans `psql` :

```sql
CREATE TABLE IF NOT EXISTS "Purchases" (
    "Id"       integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    "PlayerId" integer     NOT NULL REFERENCES "Players"("Id"),
    "Titre"    text        NOT NULL,
    "PrixPaye" integer     NOT NULL CHECK ("PrixPaye" >= 0),
    "Date"     timestamptz NOT NULL,
    UNIQUE ("PlayerId", "Titre")
);
ALTER TABLE "Players" ADD CONSTRAINT coins_positifs CHECK ("Coins" >= 0);
```

(Si PostgreSQL répond que la contrainte `coins_positifs` existe déjà, c'est que vous l'avez gardée du TP 1 : tant mieux.)

**Q9.** Que garantit la ligne `UNIQUE ("PlayerId", "Titre")` ? Et la contrainte `coins_positifs` ? Essayez : `UPDATE "Players" SET "Coins" = -1 WHERE "Pseudo" = 'Ombre';`
on s'assure que chaque joueur est sa money et qu'il ne peux pas etre en négatif

### 1.2 MongoDB — poser les prix

```javascript
db.jeux.updateMany({}, { $set: { prix: 800 } })
db.jeux.updateMany({ note: { $gte: 4.7 } }, { $set: { prix: 1200 } })
db.jeux.updateMany({ genre: "FPS" }, { $set: { prix: 0 } })
db.jeux.find({}, { titre: 1, prix: 1, _id: 0 }).sort({ prix: -1 })
```

**Q10.** Relevez le `modifiedCount` de chacune des trois commandes. Combien de documents avez-vous réécrits en entier ? Qu'aurait-il fallu faire en SQL ? Et si on lançait la **première** commande **en dernier** ?

Avec les 10 jeux du jeu de données et en exécutant les commandes dans l'ordre :

- Première commande : `modifiedCount: 10` ; elle ajoute `prix: 800` aux 10 jeux.
- Deuxième commande : `modifiedCount: 4` ; quatre jeux ont une note supérieure ou égale à 4,7 (*Stardew Valley*, *Hades II*, *Baldur's Gate 3* et *Terraria*), et leur prix passe à 1200.
- Troisième commande : `modifiedCount: 2` ; les deux jeux FPS (*Counter-Strike 2* et *Valorant*) passent à 0.

Les commandes ne remplacent pas les documents : `$set` modifie seulement le champ `prix`, donc aucun document entier n'est réécrit logiquement. En SQL, il aurait fallu ajouter une colonne `prix` avec `ALTER TABLE`, puis faire des `UPDATE` pour fixer le prix de tous les jeux et appliquer les exceptions. Si la première commande était lancée en dernier, elle remettrait le prix de tous les jeux à 800 : six documents seraient modifiés (les quatre jeux à 1200 et les deux FPS à 0), et les prix spéciaux seraient perdus.

### 1.3 Le cache vous ment (5 min)

Juste après la mission 1.2, appelez `GET /games` : le champ `prix` n'apparaît pas encore (vous n'avez pas encore modifié la classe `Game`), mais regardez surtout **la clé du cache** dans `redis-cli` :

```
TTL cache:catalogue:tous
GET cache:catalogue:tous
```

**Q11.** La valeur en cache contient-elle les prix ? Pendant combien de temps, au plus, l'API servira-t-elle un catalogue sans prix ? Quelle commande Redis force la mise à jour **tout de suite** ? (Faites-la.)

Non : la classe `Game` ne possède pas encore de propriété `Prix`, donc le JSON mis en cache ne contient pas ce champ. Le cache expire au bout de 60 secondes au maximum. Pour le supprimer immédiatement et forcer le prochain `GET /games` à relire MongoDB, exécutez `DEL cache:catalogue:tous` dans `redis-cli`.

### 1.4 Redis et Neo4j

```
ZREVRANGE classement:global 0 2 WITHSCORES
KEYS *
```

```cypher
MATCH (j:Joueur)-[:POSSEDE]->(:Jeu {titre:'Terraria'}) RETURN j.pseudo
```

**Q12.** `KEYS *` liste toutes les clés : relevez-les, et dites à quoi sert chacune. (Sur un serveur de production avec des millions de clés, `KEYS *` est à proscrire : il bloque Redis le temps de tout parcourir.)

La liste exacte dépend des commandes déjà lancées : Redis n'affiche que les clés qui existent à cet instant. Dans cette application, les clés possibles sont :

- `cache:catalogue:tous` : catalogue complet des jeux mis en cache, avec une expiration de 60 secondes.
- `classement:global` : classement Redis des joueurs et de leurs scores.
- `file:matchmaking` : joueurs actuellement en attente d'une partie.
- `presence:online` : scores de présence des joueurs, utilisés pour compter ceux vus dans la dernière minute.

Une clé de classement ou de présence n'apparaît que si l'API a reçu des données pour elle ; la file peut disparaître lorsqu'elle est vide. Il faut recopier les clés effectivement retournées par `KEYS *` dans votre console.

**Q13.** Comparez les joueurs de PostgreSQL et ceux de Neo4j. *Luna* existe-t-elle dans les deux ? Que se passera-t-il si *Luna* essaie d'acheter un jeu ?

PostgreSQL contient initialement Nova, Krayz et Ombre, tandis que Neo4j contient dix joueurs, dont Luna. Luna existe donc dans le graphe Neo4j, mais pas dans la table `"Players"` de PostgreSQL. L'achat vérifie d'abord l'existence du joueur dans PostgreSQL : il sera refusé avec le statut `JoueurInconnu` et l'API renverra **404 Not Found**. Aucun débit ni achat ne sera enregistré.

---

## Mission 2 — La boutique (45 min)

### 2.1 Les modèles

Dans `Models/Game.cs`, ajoutez à la fin de la classe :

```csharp
    // Séance 4 bis : le prix courant, en pièces. Ajouté par un updateMany : aucun document n'a été réécrit.
    // Un document sans prix donne 0 (jeu gratuit) : c'est le prix d'un schéma souple.
    [BsonElement("prix")]
    public int Prix { get; set; }
```

Créez `Models/Purchase.cs` :

```csharp
namespace PixelHub.Api.Models;

// Un achat : la trace qui fait foi (PostgreSQL). Le graphe et le classement des ventes n'en sont que des projections.
public class Purchase
{
    public int Id { get; set; }
    public int PlayerId { get; set; }
    public string Titre { get; set; } = "";
    public int PrixPaye { get; set; }       // le prix du jour de l'achat : celui du catalogue peut changer ensuite (TP 2, Q17)
    public DateTime Date { get; set; }      // en UTC : la colonne est un timestamptz
}
```

Remplacez `Data/PixelHubContext.cs` :

```csharp
using Microsoft.EntityFrameworkCore;
using PixelHub.Api.Models;

namespace PixelHub.Api.Data;

public class PixelHubContext : DbContext
{
    public PixelHubContext(DbContextOptions<PixelHubContext> options)
        : base(options) { }

    public DbSet<Player> Players => Set<Player>();
    public DbSet<Purchase> Purchases => Set<Purchase>();

    // Ces règles ne valent que pour une base créée par EnsureCreated.
    // Sur une base qui existe déjà, on les pose à la main en SQL (TP, mission 1).
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Filet de sécurité : même si le code se trompe, la base refuse un solde négatif (TP 1, Q11).
        modelBuilder.Entity<Player>()
            .ToTable(t => t.HasCheckConstraint("coins_positifs", "\"Coins\" >= 0"));

        modelBuilder.Entity<Purchase>(achat =>
        {
            achat.HasOne<Player>().WithMany().HasForeignKey(a => a.PlayerId);
            // Un jeu ne s'achète qu'une fois : c'est la base qui le garantit, pas un test en C#.
            achat.HasIndex(a => new { a.PlayerId, a.Titre }).IsUnique();
            achat.ToTable(t => t.HasCheckConstraint("prix_paye_positif", "\"PrixPaye\" >= 0"));
        });
    }
}
```

### 2.2 MongoDB : trouver un jeu par son titre

Dans `IGameCatalog`, ajoutez :

```csharp
    Task<Game?> GetByTitleAsync(string titre);                        // la boutique
```

Dans `MongoGameCatalog` :

```csharp
    public async Task<Game?> GetByTitleAsync(string titre) =>
        await _jeux.Find(/* ① */).FirstOrDefaultAsync();
```

Et dans `CachedGameCatalog` (sinon : erreur **CS0535**, la classe n'implémente plus l'interface) — le cache ne s'occupe que du catalogue complet, il **délègue** :

```csharp
    public Task<Game?> GetByTitleAsync(string titre) => _source.GetByTitleAsync(titre);
```

### 2.3 Neo4j : la projection de l'achat

Dans `ISocialGraph` :

```csharp
    Task AddOwnershipAsync(string pseudo, string titre, int annee);        // la boutique : projection d'un achat
```

Dans `Neo4jSocialGraph` :

```csharp
    // MERGE partout : rejouer la projection d'un même achat ne crée aucun doublon (mission 4, resynchronisation).
    // MERGE et non MATCH sur le joueur : un joueur créé par POST /players n'existe pas encore dans le graphe,
    // et un MATCH qui ne trouve rien ne lève aucune erreur — l'achat disparaîtrait du graphe en silence.
    public async Task AddOwnershipAsync(string pseudo, string titre, int annee)
    {
        await using var session = _driver.AsyncSession();

        await session.ExecuteWriteAsync(async tx =>
        {
            await tx.RunAsync(
                @"MERGE (j:Joueur {pseudo: $pseudo})
                  MERGE (g:Jeu {titre: $titre})
                  /* ② : la relation POSSEDE, avec sa propriété depuis = $annee à la création */",
                new { pseudo, titre, annee });
        });
    }
```

Indice pour ② : le script d'import crée les mêmes relations ; ici, `depuis` ne doit être posé **que si** la relation est nouvelle.

### 2.4 Redis : les meilleures ventes

Créez `Repositories/RedisSales.cs` :

```csharp
using StackExchange.Redis;

namespace PixelHub.Api.Repositories;

public record GameSales(string Titre, long Ventes);

// Les meilleures ventes : un sorted set titre → nombre de ventes, comme le classement des joueurs.
// Ce n'est qu'une projection : la table "Purchases" de PostgreSQL permet de le reconstruire (mission 4).
public class RedisSales
{
    private const string Key = "ventes:jeux";
    private readonly IDatabase _db;

    public RedisSales(IConnectionMultiplexer redis) => _db = redis.GetDatabase();

    public async Task RecordSaleAsync(string titre) =>
        await /* ③ */;

    public async Task<List<GameSales>> GetTopAsync(int count)
    {
        var entries = await _db.SortedSetRangeByRankWithScoresAsync(Key, 0, count - 1, Order.Descending);
        return entries.Select(e => new GameSales(e.Element!, (long)e.Score)).ToList();
    }
}
```

Indice pour ③ : relisez `AddPointsAsync` dans `RedisLeaderboard`.

### 2.5 Le service de la boutique — PostgreSQL au centre

Créez `Services/ShopService.cs` :

```csharp
using Microsoft.EntityFrameworkCore;
using Npgsql;
using PixelHub.Api.Data;
using PixelHub.Api.Models;
using PixelHub.Api.Repositories;

namespace PixelHub.Api.Services;

public enum AchatStatut { Ok, JeuInconnu, JoueurInconnu, SoldeInsuffisant, DejaPossede }
public record AchatRecu(string Pseudo, string Titre, int PrixPaye, int Solde, bool ProjectionsAJour);
public record AchatResultat(AchatStatut Statut, AchatRecu? Recu = null);

// Une action métier, quatre moteurs : on lit le prix (MongoDB), on encaisse (PostgreSQL),
// puis on met à jour les projections (Neo4j, Redis). L'ordre n'est pas un détail (mission 4).
public class ShopService
{
    private readonly PixelHubContext _db;
    private readonly IGameCatalog _catalog;
    private readonly ISocialGraph _graph;
    private readonly RedisSales _ventes;
    private readonly ILogger<ShopService> _log;

    public ShopService(PixelHubContext db, IGameCatalog catalog, ISocialGraph graph,
                       RedisSales ventes, ILogger<ShopService> log)
    {
        _db = db;
        _catalog = catalog;
        _graph = graph;
        _ventes = ventes;
        _log = log;
    }

    public async Task<AchatResultat> BuyAsync(string pseudo, string titre)
    {
        // 1. MongoDB — le catalogue est la référence du prix COURANT
        var jeu = await _catalog.GetByTitleAsync(titre);
        if (jeu is null) return new(AchatStatut.JeuInconnu);

        var joueur = await _db.Players.SingleOrDefaultAsync(p => p.Pseudo == pseudo);
        if (joueur is null) return new(AchatStatut.JoueurInconnu);

        // Message clair pour le cas courant (le joueur réessaie). Ce test ne GARANTIT rien :
        // deux requêtes simultanées le passent toutes les deux. La garantie, c'est l'index unique, plus bas.
        if (await _db.Purchases.AnyAsync(a => a.PlayerId == joueur.Id && a.Titre == jeu.Titre))
            return new(AchatStatut.DejaPossede);

        // 2. PostgreSQL — le débit et la trace de l'achat : tout ou rien (ACID)
        await using (var tx = await _db.Database.BeginTransactionAsync())
        {
            // Le test du solde et la soustraction dans le MÊME UPDATE : deux achats simultanés
            // ne peuvent pas lire tous les deux « 1200 » puis débiter tous les deux (TP 1, Q10).
            var lignes = await _db.Players
                .Where(p => /* ④ */)
                .ExecuteUpdateAsync(s => s.SetProperty(p => p.Coins, p => p.Coins - jeu.Prix));
            if (lignes == 0)
                return new(AchatStatut.SoldeInsuffisant);   // pas de commit : la transaction est annulée

            _db.Purchases.Add(new Purchase
            {
                PlayerId = joueur.Id,
                Titre = jeu.Titre,
                PrixPaye = jeu.Prix,
                Date = DateTime.UtcNow
            });
            try
            {
                await _db.SaveChangesAsync();
            }
            catch (DbUpdateException e) when (e.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
            {
                return new(AchatStatut.DejaPossede);        // l'index unique a refusé : le débit est annulé avec le reste
            }
            /* ⑤ */
        }
        var solde = await _db.Players.Where(p => p.Id == joueur.Id).Select(p => p.Coins).SingleAsync();

        // 3. Les projections : Neo4j, puis Redis
        await _graph.AddOwnershipAsync(pseudo, jeu.Titre, DateTime.UtcNow.Year);
        await _ventes.RecordSaleAsync(jeu.Titre);

        return new(AchatStatut.Ok, new AchatRecu(pseudo, jeu.Titre, jeu.Prix, solde, true));
    }
}
```

Indices : ④ l'`UPDATE` ne doit toucher que **ce** joueur, et **seulement s'il a de quoi payer**. ⑤ sans cette ligne, tout ce qui précède est annulé à la sortie du bloc `using`, **sans aucune erreur**.

**Q14.** Expliquez ce que traduit l'`ExecuteUpdateAsync` en SQL (écrivez la requête). Pourquoi est-ce plus sûr que de lire `joueur.Coins` en C#, de tester `if (joueur.Coins >= jeu.Prix)`, puis de faire `joueur.Coins -= jeu.Prix` ?

**Q15.** Le code teste « déjà acheté ? » avec `AnyAsync`, **et** il rattrape la violation de l'index unique. Le premier test ne suffit-il pas ? Imaginez deux requêtes identiques qui arrivent à la même milliseconde. Et pourquoi ne pas faire ce test dans Neo4j, où l'on voit pourtant qui possède quoi ?

### 2.6 Enregistrement et endpoints — `Program.cs`

En haut du fichier :

```csharp
using PixelHub.Api.Services;
```

Avec les autres services :

```csharp
// ---------- Séance 4 bis — l'application à quatre moteurs ----------
builder.Services.AddSingleton<RedisSales>();
// Scoped, et non singleton : ces services utilisent le DbContext, qui est scoped (une instance par requête).
builder.Services.AddScoped<ShopService>();
builder.Services.AddScoped<PlayerProfileService>();
```

(Commentez la ligne `PlayerProfileService` tant que vous n'avez pas fait la mission 3.)

Avant `app.Run()` :

```csharp
// ---------- Séance 4 bis — la boutique (mission 2) ----------
app.MapPost("/shop/{pseudo}/buy/{titre}", async (string pseudo, string titre, ShopService shop) =>
{
    var r = await shop.BuyAsync(pseudo, titre);
    return r.Statut switch
    {
        AchatStatut.Ok               => Results.Ok(r.Recu),
        AchatStatut.JeuInconnu       => Results.NotFound(new { erreur = $"Jeu inconnu : {titre}" }),
        AchatStatut.JoueurInconnu    => Results.NotFound(new { erreur = $"Joueur inconnu : {pseudo}" }),
        AchatStatut.SoldeInsuffisant => Results.Conflict(new { erreur = "Solde insuffisant" }),
        AchatStatut.DejaPossede      => Results.Conflict(new { erreur = "Jeu déjà acheté" }),
        _                            => Results.StatusCode(500)
    };
});

app.MapGet("/shop/bestsellers", async (RedisSales ventes) => await ventes.GetTopAsync(3));
```
--------------------------------------------------------------------------------------------------------------------------------------------- je suis là !!!!!!!!!!!!!!!!!! 
### 2.7 Acheter

Ajoutez à votre `PixelHub.Api.http` (un titre avec des espaces ou une apostrophe s'**encode** dans l'URL : espace → `%20`, apostrophe → `%27`) :

```http
### Séance 4 bis — boutique : Nova achète Terraria (1200 pièces)
POST {{host}}/shop/Nova/buy/Terraria

### Séance 4 bis — boutique : un titre avec espaces et apostrophe s'encode dans l'URL
POST {{host}}/shop/Nova/buy/Baldur%27s%20Gate%203

### Séance 4 bis — boutique : jeu gratuit (FPS à 0 pièce)
POST {{host}}/shop/Nova/buy/Valorant

### Séance 4 bis — boutique : jeu inconnu (404)
POST {{host}}/shop/Nova/buy/Tetris

### Séance 4 bis — meilleures ventes (Redis)
GET {{host}}/shop/bestsellers
Accept: application/json
```

Jouez-les **dans l'ordre**, puis renvoyez une seconde fois l'achat de *Valorant*, puis tentez un achat pour `Luna`. Après chaque appel, notez le code HTTP et **vérifiez dans la console du moteur concerné** :

| Appel | Code HTTP attendu | À vérifier dans… |
|---|---|---|
| Nova achète *Terraria* | | `psql` : solde de Nova, contenu de `"Purchases"` |
| Nova achète *Baldur's Gate 3* | | `psql` : le solde a-t-il bougé ? |
| Nova achète *Valorant* (2 fois) | | `psql` : combien de lignes `"Purchases"` ? |
| Nova achète *Tetris* | | — |
| Luna achète *Terraria* | | |
| — | | Browser : `MATCH (:Joueur {pseudo:'Nova'})-[r:POSSEDE]->(j) RETURN j.titre, r.depuis` |
| — | | `redis-cli` : `ZREVRANGE ventes:jeux 0 -1 WITHSCORES` |
| `GET /social/Nova/recommendations` | | *Terraria* y est-il encore ? |

**Q16.** Krayz « possède » *Valorant* dans le graphe depuis l'import. Faites-le acheter `POST /shop/Krayz/buy/Valorant` : l'achat passe-t-il ? Qui a raison, PostgreSQL ou Neo4j ? Qu'est-ce que ça dit des données importées à la main dans le graphe ?

**Q17 (bonus, terminal bash ou Git Bash).** Donnez 800 pièces à Krayz (`UPDATE "Players" SET "Coins" = 800 WHERE "Pseudo" = 'Krayz';`), puis lancez **deux achats en même temps** :

```bash
curl -s -X POST "http://localhost:5199/shop/Krayz/buy/Mario%20Kart%208%20Deluxe" &
curl -s -X POST "http://localhost:5199/shop/Krayz/buy/Cities:%20Skylines%20II" &
wait
```

Combien d'achats passent ? Quel est le solde final ? Qu'aurait donné la version « lire, tester en C#, écrire » ?

---

## Mission 3 — La fiche joueur : quatre moteurs, une réponse (20 min)

On veut `GET /players/{pseudo}/profile` : le solde (PostgreSQL), le nombre d'achats (PostgreSQL), le rang (Redis), les amis (Neo4j), et la **fiche complète** des jeux possédés (Neo4j sait **lesquels**, MongoDB sait **ce qu'ils sont**).

### 3.1 Deux méthodes de plus

Dans `ISocialGraph` :

```csharp
    Task<List<string>> GetOwnedGamesAsync(string pseudo);                  // la fiche joueur
```

Dans `Neo4jSocialGraph` :

```csharp
    public async Task<List<string>> GetOwnedGamesAsync(string pseudo)
    {
        await using var session = _driver.AsyncSession();

        return await session.ExecuteReadAsync(async tx =>
        {
            var cursor = await tx.RunAsync(
                @"/* ⑥ */
                  RETURN j.titre AS titre ORDER BY titre",
                new { pseudo });

            return await cursor.ToListAsync(r => r["titre"].As<string>());
        });
    }
```

Dans `IGameCatalog` :

```csharp
    Task<List<Game>> GetByTitlesAsync(IEnumerable<string> titres);    // la fiche joueur : une seule requête
```

Dans `MongoGameCatalog` :

```csharp
    // { titre: { $in: [...] } } : un aller-retour, quel que soit le nombre de jeux (pas un Find par titre).
    public async Task<List<Game>> GetByTitlesAsync(IEnumerable<string> titres) =>
        await _jeux.Find(/* ⑦ */).ToListAsync();
```

Et dans `CachedGameCatalog` :

```csharp
    public Task<List<Game>> GetByTitlesAsync(IEnumerable<string> titres) => _source.GetByTitlesAsync(titres);
```

Indices : ⑥ relisez la requête 2 de la partie 1 (« les jeux de Nova »), avec `$pseudo`. ⑦ `Builders<Game>.Filter` propose `Eq`, `Gt`, `In`…

### 3.2 Le service — `Services/PlayerProfileService.cs`

```csharp
using Microsoft.EntityFrameworkCore;
using StackExchange.Redis;
using PixelHub.Api.Data;
using PixelHub.Api.Models;
using PixelHub.Api.Repositories;

namespace PixelHub.Api.Services;

public record ProfilJoueur(string Pseudo, int Solde, int NbAchats, long? Rang, List<string> Amis, List<Game> Jeux);

// La fiche d'un joueur : une réponse, quatre moteurs interrogés (composition côté API).
public class PlayerProfileService
{
    private readonly PixelHubContext _db;
    private readonly ILeaderboard _classement;
    private readonly ISocialGraph _graph;
    private readonly IGameCatalog _catalog;

    public PlayerProfileService(PixelHubContext db, ILeaderboard classement,
                                ISocialGraph graph, IGameCatalog catalog)
    {
        _db = db;
        _classement = classement;
        _graph = graph;
        _catalog = catalog;
    }

    public async Task<ProfilJoueur?> GetAsync(string pseudo)
    {
        // 1. PostgreSQL — l'identité et le solde font foi ici
        var joueur = await _db.Players.SingleOrDefaultAsync(p => p.Pseudo == pseudo);
        if (joueur is null) return null;
        var nbAchats = await _db.Purchases.CountAsync(a => a.PlayerId == joueur.Id);

        // 2. Redis — le rang
        long? rang = await _classement.GetRankAsync(pseudo);

        // 3. Neo4j — les amis et les jeux possédés
        var amis = await _graph.GetFriendsAsync(pseudo);
        var titres = await _graph.GetOwnedGamesAsync(pseudo);

        // 4. MongoDB — les fiches de ces jeux, en UNE requête ($in)
        var jeux = await _catalog.GetByTitlesAsync(titres);

        return new ProfilJoueur(joueur.Pseudo, joueur.Coins, nbAchats, rang, amis, jeux);
    }
}
```

Décommentez son enregistrement, puis ajoutez l'endpoint :

```csharp
// ---------- Séance 4 bis — la fiche joueur (mission 3) ----------
app.MapGet("/players/{pseudo}/profile", async (string pseudo, PlayerProfileService profils) =>
    await profils.GetAsync(pseudo) is { } profil ? Results.Ok(profil) : Results.NotFound());
```

```http
### Séance 4 bis — fiche joueur (4 moteurs dans une réponse)
GET {{host}}/players/Nova/profile
Accept: application/json
```

**Q18.** Combien de requêtes envoie une fiche joueur, et à quels moteurs ? Si Nova possédait 200 jeux, combien de requêtes MongoDB feriez-vous avec `GetByTitlesAsync`, et combien avec une boucle de `GetByTitleAsync` ?

**Q19.** `GET /players/Luna/profile` répond 404, alors que Luna a des amis et des jeux dans le graphe. Quel moteur a décidé que Luna « n'existe pas » ? Est-ce le bon choix ?

> **Contrôle de votre poste pour l'évaluation.** Une fiche joueur qui répond **200** prouve que vos quatre moteurs fonctionnent et que votre API les joint. **Montrez-la à l'enseignant**, qui coche votre nom (voir aussi la partie « Avant de partir »).

---

## Mission 4 — Casser, constater, réparer (25 min)

### 4.1 Neo4j tombe pendant un achat

Donnez 1000 pièces à Ombre, puis arrêtez Neo4j :

```sql
UPDATE "Players" SET "Coins" = "Coins" + 1000 WHERE "Pseudo" = 'Ombre';
```

```bash
docker compose stop neo4j
```

```http
### Mission 4 — Ombre achète Rocket League, Neo4j arrêté
POST {{host}}/shop/Ombre/buy/Rocket%20League
```

La réponse met **une trentaine de secondes** à arriver : patientez.

**Q20.** Quel code HTTP obtenez-vous ? Regardez **dans `psql`** : Ombre a-t-il été débité ? L'achat est-il dans `"Purchases"` ? Que croit Ombre, qui ne voit que la réponse de l'API ? Pourquoi trente secondes ?

**Q21.** Ombre, prudent, réessaie. Que se passe-t-il ? Est-il débité une seconde fois ? Grâce à quoi ?

Redémarrez Neo4j (`docker compose start neo4j`, puis attendez qu'il soit `healthy`) et appelez `GET /players/Ombre/profile` et `GET /social/Ombre/recommendations`.

**Q22.** La fiche d'Ombre est-elle cohérente avec elle-même ? Qu'est-ce qui est faux, et dans quel moteur ?

### 4.2 Réparer : la vérité d'abord, les projections ensuite

Deux décisions, et elles vont ensemble :

1. **Un achat payé et tracé ne doit pas répondre 500.** L'argent est encaissé dans PostgreSQL : c'est **lui** qui dit si l'achat a eu lieu. Si une projection échoue, on le signale (`projectionsAJour: false`), on ne l'annule pas.
2. **Une projection doit pouvoir se reconstruire** à partir de la vérité.

Dans `ShopService`, remplacez la fin de `BuyAsync` (à partir de `// 3.`) par :

```csharp
        // 3. Les projections. L'achat est payé et tracé : si une projection échoue, on ne l'annule pas,
        //    on le signale. POST /admin/resync reconstruira les projections depuis PostgreSQL (mission 4).
        var projectionsAJour = true;
        try
        {
            await _graph.AddOwnershipAsync(pseudo, jeu.Titre, DateTime.UtcNow.Year);   // Neo4j
            await _ventes.RecordSaleAsync(jeu.Titre);                                   // Redis
        }
        catch (Exception e)
        {
            _log.LogWarning("Achat {Titre} par {Pseudo} enregistré, projections en retard : {Message}",
                jeu.Titre, pseudo, e.Message);
            projectionsAJour = false;
        }

        return new(AchatStatut.Ok, new AchatRecu(pseudo, jeu.Titre, jeu.Prix, solde, projectionsAJour));
    }
```

Dans `RedisSales`, ajoutez :

```csharp
    // Reconstruction complète depuis la source de vérité : on jette la projection et on la réécrit.
    public async Task ReplaceAllAsync(IEnumerable<GameSales> ventes)
    {
        await _db.KeyDeleteAsync(Key);
        var entries = ventes.Select(v => new SortedSetEntry(v.Titre, v.Ventes)).ToArray();
        if (entries.Length > 0)
            await _db.SortedSetAddAsync(Key, entries);
    }
```

Et l'endpoint de resynchronisation, avant `app.Run()` :

```csharp
// ---------- Séance 4 bis — reconstruire les projections depuis la source de vérité (mission 4) ----------
app.MapPost("/admin/resync", async (PixelHubContext db, ISocialGraph g, RedisSales ventes) =>
{
    var achats = await db.Purchases
        .Join(db.Players, a => a.PlayerId, p => p.Id, (a, p) => new { p.Pseudo, a.Titre, a.Date })
        .ToListAsync();

    foreach (var a in achats)                                      // MERGE : rejouable sans doublon
        await g.AddOwnershipAsync(a.Pseudo, a.Titre, a.Date.Year);

    await ventes.ReplaceAllAsync(achats
        .GroupBy(a => a.Titre)
        .Select(groupe => new GameSales(groupe.Key, groupe.Count())));

    return Results.Ok(new { achatsRejoues = achats.Count });
});
```

```http
### Séance 4 bis — mission 4 : reconstruire Neo4j et Redis depuis PostgreSQL
POST {{host}}/admin/resync
```

Appelez `/admin/resync` **deux fois**, puis revérifiez la fiche d'Ombre et `MATCH (:Joueur {pseudo:'Ombre'})-[r:POSSEDE]->(j) RETURN j.titre, count(r)`.

**Q23.** Pourquoi peut-on rejouer `/admin/resync` autant de fois qu'on veut sans créer de doublon ? Qu'arriverait-il si `AddOwnershipAsync` utilisait `CREATE` ?

**Q24.** Complétez :

| Donnée | Système de référence | Projection(s) | Se reconstruit à partir de… | Retard acceptable ? |
|---|---|---|---|---|
| Solde de monnaie | | | | |
| « Ombre a acheté Rocket League » | | | | |
| Prix courant d'un jeu | | | | |
| Prix payé par Ombre | | | | |
| Meilleures ventes | | | | |
| Catalogue complet | | | | |

### 4.3 Redis tombe

```bash
docker compose stop redis
```

Appelez `GET /games` puis `GET /players/Nova/profile`.

**Q25.** MongoDB fonctionne parfaitement, et pourtant `/games` échoue. Pourquoi ? Qu'est devenu le cache dans votre architecture ?

Corrigez `GetAllAsync` dans `CachedGameCatalog` : si Redis est indisponible, on sert MongoDB directement.

```csharp
    public async Task<List<Game>> GetAllAsync()
    {
        // Mission 4 : un cache en panne ne doit pas faire tomber le catalogue.
        // Redis n'est qu'une copie : sans lui, on sert MongoDB directement (plus lent, mais juste).
        try
        {
            var cached = await _cache.StringGetAsync(KeyAll);
            if (cached.HasValue)                                   // cache hit
                // (string) explicite : avec StackExchange.Redis 3.x, RedisValue se convertit aussi
                // en ReadOnlySpan<byte>, et `Deserialize(cached!)` devient ambigu (CS0121).
                return JsonSerializer.Deserialize<List<Game>>((string)cached!)!;
        }
        catch (Exception e) when (e is RedisException or RedisTimeoutException)
        {
            // Dans un vrai projet, on journaliserait la panne ici : un repli silencieux masque l'incident.
            return await _source.GetAllAsync();
        }

        var jeux = await _source.GetAllAsync();                // cache miss
        await _cache.StringSetAsync(KeyAll,
            JsonSerializer.Serialize(jeux), Ttl);
        return jeux;
    }
```

Et dans `PlayerProfileService`, remplacez l'étape 2 :

```csharp
        // 2. Redis — le rang est secondaire : sans Redis, la fiche s'affiche quand même, sans rang
        long? rang = null;
        try
        {
            rang = await _classement.GetRankAsync(pseudo);
        }
        catch (Exception e) when (e is RedisException or RedisTimeoutException) { }
```

Relancez l'API (Redis toujours arrêté), rappelez `/games` et la fiche de Nova, puis redémarrez Redis (`docker compose start redis`).

**Q26.** Pourquoi a-t-on le droit de « rattraper » silencieusement une panne de Redis dans le cache et la fiche joueur, alors qu'on n'aurait **jamais** le droit de le faire pour une panne de PostgreSQL dans la boutique ?

---

## Avant de partir — checklist

- [ ] `/social/Krayz/friends` renvoie **Nova et Pixel**
- [ ] Un achat débite le joueur **et** crée une ligne dans `"Purchases"`
- [ ] Un second achat du même jeu répond **409**, et le joueur n'est pas débité
- [ ] `/shop/bestsellers` répond
- [ ] `/players/Nova/profile` répond **200** — **montré à l'enseignant**
- [ ] Neo4j arrêté : l'achat répond 200 avec `projectionsAJour: false` ; `/admin/resync` répare
- [ ] Redis arrêté : `/games` répond quand même
- [ ] **Mise en cache des paquets de l'évaluation** (1 min, réseau nécessaire). Dans un dossier **hors** de votre dépôt, créez un projet jetable qui télécharge les versions exactes utilisées le jour de l'évaluation, puis supprimez le dossier (les paquets restent dans le cache NuGet de votre machine) :
  ```bash
  dotnet new web -o precache-eval
  cd precache-eval
  dotnet add package MongoDB.Driver --version 3.12.0
  dotnet add package StackExchange.Redis --version 3.3.1
  dotnet add package Neo4j.Driver --version 6.3.0
  dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL --version 10.0.3
  dotnet add package Microsoft.EntityFrameworkCore.Design --version 10.0.12
  cd ..
  ```
- [ ] Code poussé sur le dépôt

**D'ici l'évaluation :** ne supprimez aucune image Docker (pas de `docker system prune`), ne désinstallez pas le SDK .NET 10, ne changez pas les ports de votre `.env`, ne videz pas le cache NuGet. Venez avec un poste **chargé**, et son chargeur.

---

## Problèmes fréquents

### `relation "Purchases" does not exist`
Vous n'avez pas lancé le `CREATE TABLE` de la mission 1.1 : `EnsureCreated()` ne crée rien dans une base qui existe déjà.

### `CS0535 : 'CachedGameCatalog' n'implémente pas le membre d'interface…`
Chaque méthode ajoutée à `IGameCatalog` doit l'être aussi dans `CachedGameCatalog`, qui délègue à `_source`.

### L'achat répond 200 mais le solde ne bouge pas
Le trou ⑤ : sans `CommitAsync`, la transaction est annulée à la sortie du `using`, sans erreur.

### `Cannot write DateTime with Kind=Local to PostgreSQL type 'timestamp with time zone'`
Utilisez `DateTime.UtcNow`, pas `DateTime.Now`.

### `/shop/Nova/buy/Baldur's Gate 3` répond 404
Encodez l'URL : `Baldur%27s%20Gate%203`.

### Le champ `prix` vaut 0 dans `/games` alors qu'il est bien dans MongoDB
Le cache : il contient le catalogue d'avant les prix. `DEL cache:catalogue:tous` dans `redis-cli`, ou attendez 60 s.

### L'achat met 30 secondes à répondre
Neo4j est arrêté ou pas encore prêt : le driver réessaie pendant 30 s avant d'abandonner. `docker compose ps`.

### Le Browser refuse la connexion, « mot de passe incorrect »
Neuf fois sur dix, c'est le **Connect URL** : remplacez `7687` par `17687` (`neo4j://localhost:17687`). Si vous avez changé `NEO4J_BOLT_PORT` dans `.env`, utilisez votre port. Si le port est bon et que le mot de passe `pixelhub_dev` est vraiment refusé, le volume Neo4j a été créé avec un autre mot de passe : `docker compose stop neo4j`, `docker compose rm -f neo4j`, `docker volume ls` pour trouver le volume `…_neo4j_data`, `docker volume rm <ce volume>`, puis `docker compose up -d` et réimportez le graphe (1.1). Les autres bases ne sont pas touchées.

### `MATCH (j:joueur)` renvoie zéro résultat
Étiquettes et types de relations sont **sensibles à la casse** : `:joueur` ≠ `:Joueur`, sans aucune erreur.

---

## Pour l'évaluation

**Individuelle, 3 h, sans réseau si l'enseignant le demande** (tout ce dont vous aurez besoin sera déjà sur votre poste).

1. **1 h — QCM et questions courtes, sur papier, sans document ni appareil**, noté /20. Tout le module : familles de bases, ACID, PostgreSQL, MongoDB, Redis, Neo4j, cohabitation.
2. **2 h — manipulation sur machine**, sur un dépôt PixelHub distribué au début de l'épreuve, avec **vos propres données** : requêtes à écrire dans les quatre consoles et **résultats à reporter** sur une feuille réponse, code à compléter (comme les trous de ce TP), bugs silencieux à trouver, et surtout (la moitié des points) **l'architecture dans son ensemble** : retrouver où les moteurs se contredisent, tracer un achat dans les quatre, mesurer qui dépend de qui, réparer après une panne. Noté /20, il compte double. Documentation autorisée : un **aide-mémoire** fourni dans le dépôt.

**Pour réviser** : refaites ce TP **sans regarder les trous corrigés**, relisez vos réponses Q1 à Q26, et entraînez-vous à taper les commandes des quatre consoles de mémoire.
