# TP 3 — Classements, matchmaking et cache avec Redis

**R5.A.10 — Nouveaux paradigmes de bases de données**
Durée : 1 h 55 · Non noté : gardez votre code sur votre dépôt, il resservira

---

## Objectif

PixelHub tourne avec PostgreSQL et MongoDB. À la fin de ce TP, il tournera avec **trois moteurs**.

Vous allez implémenter jusqu'à quatre fonctionnalités, chacune avec la structure Redis qui lui correspond :

| Fonctionnalité | Structure | Statut |
|---|---|---|
| Classement des joueurs | Sorted set | **Obligatoire** |
| Cache du catalogue (et mesure du gain) | String + TTL | **Obligatoire** |
| Joueurs actuellement en ligne | *à vous de trouver — voir partie 2.5* | Recommandé |
| File de matchmaking | List | Bonus |

> **Ordre de travail — important.** Partie 1 → parties 2.1 à 2.4 → **2.6 (le cache)** → partie 3 (la mesure). Sautez 2.4 bis et 2.5 au premier passage ; revenez ensuite à **2.5**, puis à **2.4 bis** s'il vous reste du temps. À 2h45, tout le monde s'arrête : la présence en ligne (2.5) est corrigée en commun, que vous l'ayez codée ou non.

> **Règle inchangée** : `/players` et `/games` doivent continuer à fonctionner à la fin.

> **Calendrier du module.** Il reste après celle-ci une séance (Neo4j, puis la cohabitation des quatre bases) et un **TP final noté, individuel**. Les TP ne sont pas notés, mais ce que vous faites aujourd'hui sera mobilisé à l'évaluation.

---

## Avant de commencer

```bash
cd pixelhub
docker compose up -d
docker compose exec redis redis-cli ping     # doit répondre PONG
```

Si votre projet est cassé ou si vous étiez absent, récupérez l'archive `seance2-fin` auprès de l'enseignant. Ne passez pas la séance à réparer.

---

## Partie 1 — Les structures dans `redis-cli` (20 min) — obligatoire

Comme la séance dernière : d'abord le shell, ensuite le C#.

```bash
docker compose exec redis redis-cli
```

### 1.1 String et compteur

```
SET compteur:parties 0
INCR compteur:parties
INCRBY compteur:parties 10
GET compteur:parties
```

**Q1.** `INCR` est une opération **atomique**. Qu'est-ce que ça veut dire concrètement, et pourquoi est-ce important si mille joueurs terminent une partie en même temps ? Comment auriez-vous fait la même chose en SQL, et quelle différence cela fait-il ?

**Réponse :** Atomique veut dire que l'incrémentation se fait entièrement, sans qu'une autre opération puisse s'intercaler. Si mille joueurs terminent une partie en même temps, Redis ajoute bien 1000 au compteur, sans perdre d'incréments. En SQL, on peut faire `UPDATE compteur SET parties = parties + 1 WHERE id = 1;`. Il faut faire l'incrémentation directement dans la requête, plutôt que lire la valeur puis la modifier dans le code.

```sql
UPDATE compteur
SET parties = parties + 1
WHERE id = 1;
```

### 1.2 Hash — un joueur

```
HSET joueur:7 pseudo "Nova" niveau 12 xp 3400
HGETALL joueur:7
HINCRBY joueur:7 xp 250
HGET joueur:7 xp
```

**Q2.** On aurait pu sérialiser tout le joueur en JSON dans une simple `String`. Décrivez les étapes qu'il aurait alors fallu faire pour ajouter 250 XP, et le problème qui apparaît si deux requêtes le font en même temps. 

**Réponse :** Il aurait fallu lire la `String` Redis, désérialiser le JSON en joueur, ajouter 250 à son champ `xp`, re-sérialiser l'objet, puis réécrire la `String`. Si deux requêtes font cela en même temps, elles peuvent lire toutes les deux la même valeur initiale (par exemple 3400), puis chacune écrire 3650. Au lieu de gagner 500 XP, le joueur n'en gagne que 250 : une mise à jour est perdue. `HINCRBY` évite ce problème en incrémentant directement le champ de façon atomique.
### 1.3 Sorted set — le classement

```
ZADD classement:global 4500 "Nova"
ZADD classement:global 3200 "Krayz"
ZADD classement:global 5100 "Ombre"
ZADD classement:global 1800 "Pixel"

ZREVRANGE classement:global 0 2 WITHSCORES
ZRANGE    classement:global 0 2 WITHSCORES
```

**Q3.** Les deux dernières commandes ne renvoient pas la même chose. Expliquez la différence, et dites laquelle vous utiliserez pour afficher un « top 3 ».

**Réponse :** `ZRANGE` affiche les joueurs du plus petit score au plus grand. `ZREVRANGE` fait l'inverse, du plus grand au plus petit. Pour afficher le top 3, j'utilise `ZREVRANGE classement:global 0 2 WITHSCORES`.
```
ZREVRANK classement:global "Krayz"
ZINCRBY  classement:global 2000 "Krayz"
ZREVRANK classement:global "Krayz"
```

**Q4.** `ZREVRANK` renvoie un nombre. Si vous affichez ce nombre tel quel au joueur, que va-t-il lire ? Que faut-il faire ?

**Réponse :** `ZREVRANK` renvoie un index qui commence à 0. Le meilleur joueur verrait donc « 0 ». Pour afficher un rang qui commence à 1, il faut ajouter 1 au résultat.

### 1.4 List — la file de matchmaking

```
LPUSH file:matchmaking "Nova"
LPUSH file:matchmaking "Krayz"
LPUSH file:matchmaking "Ombre"
LLEN   file:matchmaking
LRANGE file:matchmaking 0 -1
RPOP   file:matchmaking
```

**Q5.** Qui sort de la file au `RPOP`, et pourquoi ? Qu'aurait donné `LPOP` à la place ?

**Réponse :** `RPOP` sort Nova, car `LPUSH` place chaque nouveau joueur au début de la liste et Nova est arrivée en premier. C'est donc une file FIFO. `LPOP` aurait sorti Ombre, la dernière arrivée.

### 1.5 TTL

```
c
```

Attendez vraiment 30 secondes, puis :

```
TTL    enligne:Nova
EXISTS enligne:Nova
```

**Q6.** Quelles valeurs obtenez-vous ? Que renvoie `TTL` sur une clé sans expiration (testez avec `compteur:parties`) ? Que signifie chacune des valeurs de retour ?

**Réponse :** Avant l'expiration, `TTL` renvoie le nombre de secondes restantes et `EXISTS` renvoie `1`. Après 30 secondes, la clé a expiré : `TTL` renvoie `-2` et `EXISTS` renvoie `0`. Pour une clé qui n'a pas d'expiration, comme `compteur:parties`, `TTL` renvoie `-1`.

**Q7.** Personne n'a lancé de tâche de nettoyage. Quel code auriez-vous dû écrire pour obtenir le même comportement avec PostgreSQL, et quels risques ce code introduit-il ?

**Réponse :** Il aurait fallu enregistrer la date du dernier signe de vie, puis exécuter régulièrement une tâche qui supprime les joueurs dont cette date a plus de 30 secondes. Cette tâche peut ne pas s'exécuter à temps ou s'arrêter, et les suppressions régulières ajoutent de la charge et peuvent créer des problèmes de concurrence.

Quittez le shell : `exit`.

---

## Partie 2 — Redis dans PixelHub (70 min) — obligatoire : 2.1 à 2.4 et 2.6

### 2.1 Le paquet

```bash
cd src/PixelHub.Api
dotnet add package StackExchange.Redis
```

### 2.2 La configuration

Dans `appsettings.json`, on ajoute une troisième chaîne :

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Port=15432;Database=pixelhub;Username=pixelhub;Password=pixelhub_dev",
    "Mongo": "mongodb://pixelhub:pixelhub_dev@localhost:27018/?authSource=admin",
    "Redis": "localhost:16379"
  }
}
```

### 2.3 L'enregistrement

```csharp
using StackExchange.Redis;

builder.Services.AddSingleton<IConnectionMultiplexer>(_ =>
    ConnectionMultiplexer.Connect(builder.Configuration.GetConnectionString("Redis")!));
```

**Q8.** Ce service est enregistré en **singleton**. Cherchez dans la documentation de StackExchange.Redis ce qu'est un `ConnectionMultiplexer` et ce qui se passerait si on en créait un à chaque requête HTTP. Pourquoi ce bug serait-il **invisible** aujourd'hui en TP ?

**Réponse :** Le `ConnectionMultiplexer` gère et partage les connexions avec Redis. Il est conçu pour être réutilisé. En en créant un à chaque requête, on multiplierait les connexions et leur coût, ce qui pourrait finir par épuiser les ressources. En TP, il y a peu de requêtes, donc le problème risque de ne pas se voir.

### 2.4 Le classement — obligatoire (≈ 40 min avec 2.1 à 2.3)

Créez `Repositories/ILeaderboard.cs` :

```csharp
namespace PixelHub.Api.Repositories;

public record LeaderboardEntry(string Pseudo, double Score, long Rang);

public interface ILeaderboard
{
    Task AddPointsAsync(string pseudo, double points);
    Task<List<LeaderboardEntry>> GetTopAsync(int count);
    Task<long?> GetRankAsync(string pseudo);
}
```

Puis `Repositories/RedisLeaderboard.cs` :

```csharp
using StackExchange.Redis;

namespace PixelHub.Api.Repositories;

public class RedisLeaderboard : ILeaderboard
{
    private const string Key = "classement:global";
    private readonly IDatabase _db;

    public RedisLeaderboard(IConnectionMultiplexer redis) => _db = redis.GetDatabase();

    public async Task AddPointsAsync(string pseudo, double points) =>
        await _db.SortedSetIncrementAsync(Key, pseudo, points);

    public async Task<List<LeaderboardEntry>> GetTopAsync(int count)
    {
        var entries = await _db.SortedSetRangeByRankWithScoresAsync(
            Key, 0, count - 1, Order.Descending);

        return entries
            .Select((e, i) => new LeaderboardEntry(e.Element!, e.Score, i + 1))
            .ToList();
    }

    public async Task<long?> GetRankAsync(string pseudo)
    {
        var rang = await _db.SortedSetRankAsync(Key, pseudo, Order.Descending);
        return rang.HasValue ? rang.Value + 1 : null;
    }
}
```

Enregistrez le service et ajoutez les endpoints :

```csharp
builder.Services.AddSingleton<ILeaderboard, RedisLeaderboard>();
```

```csharp
app.MapPost("/leaderboard/{pseudo}/points/{points:double}",
    async (string pseudo, double points, ILeaderboard lb) =>
    { await lb.AddPointsAsync(pseudo, points); return Results.Ok(); });

app.MapGet("/leaderboard/top/{count:int}",
    async (int count, ILeaderboard lb) => await lb.GetTopAsync(count));

app.MapGet("/leaderboard/rank/{pseudo}",
    async (string pseudo, ILeaderboard lb) => await lb.GetRankAsync(pseudo));
```

**Testez** : ajoutez des points à trois ou quatre joueurs, puis appelez `/leaderboard/top/5`.

**Q9.** Supprimez `Order.Descending` des deux méthodes, relancez, et regardez `/leaderboard/top/5`. Le résultat est-il visiblement faux ? Pourquoi ce bug est-il particulièrement dangereux ?

**Réponse :** Sans `Order.Descending`, le classement est lu du score le plus faible au plus élevé : le « top » affiche donc les moins bons scores en premier. Le résultat peut pourtant sembler normal et ne provoquer aucune erreur ; c'est dangereux parce que le classement est faux sans que l'application le signale.

Remettez `Order.Descending` avant de continuer.

### 2.4 bis La file de matchmaking — bonus

> **À faire en dernier**, seulement si 2.6, la partie 3 et 2.5 sont terminées. Passez directement à 2.6.

Créez `Repositories/RedisMatchmakingQueue.cs` — c'est la transposition directe des commandes de la partie 1.4 :

```csharp
using StackExchange.Redis;

namespace PixelHub.Api.Repositories;

public class RedisMatchmakingQueue
{
    private const string Key = "file:matchmaking";
    private readonly IDatabase _db;

    public RedisMatchmakingQueue(IConnectionMultiplexer redis) => _db = redis.GetDatabase();

    public async Task EnqueueAsync(string pseudo) =>
        await _db.ListLeftPushAsync(Key, pseudo);          // LPUSH

    public async Task<string?> DequeueAsync() =>
        await _db.ListRightPopAsync(Key);                  // RPOP

    public async Task<long> LengthAsync() =>
        await _db.ListLengthAsync(Key);                    // LLEN

    // Apparier deux joueurs : une partie se crée
    public async Task<(string, string)?> TryMatchAsync()
    {
        if (await LengthAsync() < 2) return null;
        var a = await DequeueAsync();
        var b = await DequeueAsync();
        return (a is null || b is null) ? null : (a, b);
    }
}
```

```csharp
builder.Services.AddSingleton<RedisMatchmakingQueue>();
```

```csharp
app.MapPost("/matchmaking/{pseudo}", async (string pseudo, RedisMatchmakingQueue file) =>
{
    await file.EnqueueAsync(pseudo);
    return Results.Ok(new { enAttente = await file.LengthAsync() });
});

// Un tuple C# ne se sérialise pas en JSON (Item1/Item2 sont des champs) : on le nomme.
app.MapPost("/matchmaking/match", async (RedisMatchmakingQueue file) =>
    await file.TryMatchAsync() is (string joueur1, string joueur2)
        ? Results.Ok(new { joueur1, joueur2 })
        : Results.NoContent());
```

**Testez** : mettez Nova, Krayz puis Ombre dans la file, appelez `/matchmaking/match` : c'est **Nova et Krayz** qui doivent sortir. Un second appel renvoie 204 (Ombre attend seule).

### 2.5 Les joueurs en ligne — à vous de concevoir (recommandé)

> **À faire après 2.6 et la partie 3.** Si vous n'avez pas le temps, lisez quand même l'énoncé et préparez une réponse à Q10 : la solution est construite en commun à 2h45.

**Ne recopiez rien pour cette partie. Cherchez d'abord.**

Objectif : savoir combien de joueurs sont actuellement en ligne. Un joueur est « en ligne » si l'application a reçu un signe de vie de sa part **il y a moins de 60 secondes**.

**Étape 1.** Écrivez une première version avec un `Set` (`SetAddAsync`, `SetLengthAsync`). Testez : ajoutez trois joueurs, comptez.

**Q10.** Comment un joueur sort-il de cet ensemble quand il ferme son navigateur sans se déconnecter ? Cherchez la commande Redis qui ferait expirer **un seul membre** d'un Set. Que trouvez-vous ?

**Réponse :** Un `Set` Redis ne permet pas de donner une expiration à un seul membre : l'expiration s'applique à la clé entière. Sans déconnexion explicite, le joueur resterait donc dans l'ensemble. Il faut choisir une structure qui permette de repérer les membres dont le signe de vie est trop ancien.

**Étape 2.** Votre première version ne marche pas. Reprenez le tableau des cinq structures du cours, et trouvez-en une qui permette de « supprimer tous les éléments plus vieux qu'une certaine date ».

**Indice** : le score d'un sorted set est un nombre quelconque. Rien n'oblige à ce que ce soit un score de jeu.

**Q11.** Décrivez votre solution avant de la coder : quelle structure, quelle clé, que met-on dans le score, et quelles commandes pour compter et pour purger ?

**Réponse :** J'utiliserais un sorted set, par exemple `presence:online`, avec le pseudo comme membre et l'heure du dernier signe de vie comme score. À chaque signe de vie, `ZADD` met à jour le score du joueur. Pour compter ceux vus dans les 60 dernières secondes, j'utilise `ZCOUNT` avec le seuil correspondant à maintenant moins 60 secondes. Pour supprimer les anciens membres, j'utilise `ZREMRANGEBYSCORE` jusqu'à ce seuil.

Implémentez-la dans une classe `RedisPresence` (enregistrée en singleton, avec une méthode `TouchAsync(pseudo)` pour le signe de vie et `CountOnlineAsync()` pour le comptage), puis ajoutez les endpoints :

```csharp
builder.Services.AddSingleton<RedisPresence>();
```

```csharp
app.MapPost("/online/{pseudo}", async (string pseudo, RedisPresence p) =>
{ await p.TouchAsync(pseudo); return Results.Ok(); });

app.MapGet("/online/count", async (RedisPresence p) => await p.CountOnlineAsync());
```

Testez avec un TTL raccourci à 10 secondes pour ne pas attendre une minute.

### 2.6 Le cache du catalogue — obligatoire (≈ 30 min)

**Avant tout, un préalable.** Le cache va sérialiser les jeux en JSON puis les relire. Or `System.Text.Json` ne sait pas relire un `ObjectId` : sans précaution, l'`id` revient **à zéro** (horodatage de 1970) à chaque lecture depuis le cache — sans aucune erreur. Faites voyager l'`Id` sous forme de texte :

```csharp
// Models/ObjectIdJsonConverter.cs
using System.Text.Json;
using System.Text.Json.Serialization;
using MongoDB.Bson;

namespace PixelHub.Api.Models;

public class ObjectIdJsonConverter : JsonConverter<ObjectId>
{
    public override ObjectId Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        ObjectId.Parse(reader.GetString());

    public override void Write(Utf8JsonWriter writer, ObjectId value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString());
}
```

Et dans `Models/Game.cs`, sur l'`Id` (ajoutez `using System.Text.Json.Serialization;`) :

```csharp
[BsonId]
[JsonConverter(typeof(ObjectIdJsonConverter))]
public ObjectId Id { get; set; }
```

Bonus visible immédiatement : `/games` affiche désormais `"id": "66f1…"` au lieu d'un objet `{ timestamp, creationTime }`.

Créez ensuite `Repositories/CachedGameCatalog.cs`. Il implémente **la même interface** que `MongoGameCatalog` :

```csharp
using System.Text.Json;
using StackExchange.Redis;
using PixelHub.Api.Models;

namespace PixelHub.Api.Repositories;

public class CachedGameCatalog : IGameCatalog
{
    private const string KeyAll = "cache:catalogue:tous";
    private static readonly TimeSpan Ttl = TimeSpan.FromSeconds(60);

    private readonly IGameCatalog _source;
    private readonly IDatabase _cache;

    public CachedGameCatalog(IGameCatalog source, IConnectionMultiplexer redis)
    {
        _source = source;
        _cache = redis.GetDatabase();
    }

    public async Task<List<Game>> GetAllAsync()
    {
        var cached = await _cache.StringGetAsync(KeyAll);
        if (cached.HasValue)
            return JsonSerializer.Deserialize<List<Game>>((string)cached!)!;

        var jeux = await _source.GetAllAsync();
        await _cache.StringSetAsync(KeyAll, JsonSerializer.Serialize(jeux), Ttl);
        return jeux;
    }

    public Task<List<Game>> GetByGenreAsync(string genre) => _source.GetByGenreAsync(genre);
    public Task<List<Game>> GetTopRatedAsync(int count) => _source.GetTopRatedAsync(count);
    public Task<List<GenreStats>> GetStatsByGenreAsync() => _source.GetStatsByGenreAsync();
}
```

Modifiez l'enregistrement — **l'ordre compte** :

```csharp
builder.Services.AddSingleton<MongoGameCatalog>();
builder.Services.AddSingleton<IGameCatalog>(sp =>
    new CachedGameCatalog(
        sp.GetRequiredService<MongoGameCatalog>(),
        sp.GetRequiredService<IConnectionMultiplexer>()));
```

**Q12.** Combien de lignes avez-vous modifiées dans vos **endpoints** pour ajouter ce cache ? Pourquoi ? Quel choix de la séance 2 rend cela possible ?

**Réponse :** Aucune ligne d'endpoint n'est à modifier. Les endpoints utilisent déjà l'interface `IGameCatalog` ; on peut donc remplacer l'implémentation enregistrée par la version avec cache sans changer les endpoints. C'est le choix de dépendre d'une interface plutôt que directement de `MongoGameCatalog` qui le permet.

---

## Partie 3 — Mesurer, et se méfier de la mesure (10 min) — obligatoire

Ajoutez :

```csharp
app.MapGet("/games/timed", async (IGameCatalog catalog) =>
{
    var chrono = System.Diagnostics.Stopwatch.StartNew();
    var jeux = await catalog.GetAllAsync();
    chrono.Stop();
    return new { nombre = jeux.Count, millisecondes = chrono.Elapsed.TotalMilliseconds };
});
```

Protocole :
1. appelez une première fois — c'est un *cache miss*, on va jusqu'à MongoDB ;
2. appelez quatre ou cinq fois de suite — ce sont des *cache hits* ;
3. attendez 60 secondes, rappelez.

**Q13.** Relevez vos mesures. Le gain est-il spectaculaire ? Quelle conclusion honnête pouvez-vous en tirer, et dans quelles conditions un cache devient-il réellement décisif ?


**Réponse :**{"nombre":11,"millisecondes":76.9591}/{"nombre":11,"millisecondes":2.1472} je gagne 74 milli seconde ce qui est enorme en temp de pourcentage d'efficacité mais à l'échelle humaine cette différence n'est pas visible.

**Q14.** Un administrateur corrige le titre d'un jeu directement dans MongoDB. Combien de temps les joueurs verront-ils l'ancien titre, et pourquoi ? Proposez deux stratégies pour réduire ce délai, avec leur inconvénient.

**Réponse :** Avec un TTL de 60 secondes, les joueurs peuvent voir l'ancien titre jusqu'à l'expiration du cache, donc au maximum environ 60 secondes après son remplissage. On peut supprimer ou mettre à jour la clé Redis dès qu'un jeu est modifié, mais il faut que toutes les modifications passent par ce mécanisme. On peut aussi raccourcir le TTL, mais cela augmente les lectures vers MongoDB et réduit l'efficacité du cache.

---

## Avant de partir — checklist

**Obligatoire :**

- [ ] `/players` et `/games` fonctionnent toujours ; au deuxième appel de `/games` (servi par le cache), les `id` sont corrects
- [ ] `/leaderboard/top/5` est trié **du meilleur au pire**
- [ ] `/leaderboard/rank/{pseudo}` renvoie un rang commençant à 1
- [ ] Le second appel à `/games/timed` est plus rapide que le premier
- [ ] Je sais expliquer **pourquoi** un sorted set pour la présence en ligne (même si je ne l'ai pas codée)
- [ ] Je sais dire ce que je perdrais si Redis redémarrait, et si c'est grave
- [ ] Code poussé sur le dépôt

**Recommandé :** `/online/count` décroît tout seul après le délai.
**Bonus :** la file de matchmaking apparie bien en FIFO.

**Question orale de l'enseignant** : *« Le solde de monnaie virtuelle d'un joueur : tu le mettrais dans Redis ? »*

---

## Problèmes fréquents

### Le « top 10 » affiche les plus mauvais scores
Un sorted set est trié par score **croissant** par défaut. Il faut `Order.Descending`. Voir Q9.

### Le meilleur joueur est affiché « 0e »
`ZREVRANK` renvoie un index, pas un rang d'affichage. Voir Q4.

### `RedisConnectionException: It was not possible to connect`
Le port. Vérifiez `localhost:16379` et non `6379`, et la cohérence entre `.env` et `appsettings.json`.

### Erreur de compilation autour de `StringGetAsync`
La méthode renvoie un `RedisValue`, pas une `string`. Testez `.HasValue` puis convertissez explicitement : `(string)cached!`. Sans le `(string)`, `JsonSerializer.Deserialize(cached!)` est **ambigu** (erreur CS0121) : un `RedisValue` se convertit aussi en `ReadOnlySpan<byte>`. Le test `.HasValue` est **le** test du cache miss.

### Les `id` valent tous `{"timestamp":0, "creationTime":"1970-01-01…"}` au deuxième appel
Vous avez sauté le préalable de la partie 2.6. `System.Text.Json` écrit un `ObjectId` sous forme d'objet et ne sait pas le relire : il le remplace **silencieusement** par un `ObjectId` vide. Aucune exception, un 200 parfaitement formé — un piège silencieux de plus. Ajoutez le `ObjectIdJsonConverter`, puis videz le cache (`DEL cache:catalogue:tous` dans `redis-cli`).

### « J'ai fait `docker compose down` et j'ai tout perdu »
C'est normal, et c'est voulu. Demandez-vous : **qu'avez-vous perdu exactement, et est-ce grave ?**

---

## Pour aller plus loin (optionnel)

1. **Rate limiting.** Implémentez une limite de 5 messages par minute et par joueur, avec une clé `limite:{pseudo}` et un TTL de 60 s. Quelle commande vous donne à la fois l'incrément et la valeur ?

2. **Classement par jeu.** Ajoutez `classement:jeu:{id}` en plus du classement global. Que devient votre convention de nommage ?

3. **`SCAN` contre `KEYS`.** Créez une trentaine de clés `test:1` à `test:30`, puis comparez `KEYS test:*` et `SCAN 0 MATCH test:* COUNT 10`. Que renvoie `SCAN` comme premier élément, et à quoi sert-il ?

4. **Appariement atomique.** La méthode qui apparie deux joueurs de la file a un défaut de concurrence. Identifiez-le, et cherchez comment Redis permet de le corriger.

---

## Pour la prochaine séance

**Ce qui vous attend.** Neo4j, le dernier moteur, puis, en fin de séance, la question que le cache a soulevée aujourd'hui : que se passe-t-il quand une même donnée vit dans plusieurs bases ? La séance se termine par un **contrôle de votre poste** avant le TP final noté : venez avec PixelHub qui fonctionne, et **ne supprimez aucune image Docker** d'ici là (pas de `docker system prune`). Si votre projet est cassé, l'archive `seance3-fin` vous sera donnée en début de séance.

Un problème à préparer mentalement :

> On veut recommander des jeux à Nova : ceux que possèdent ses amis **et les amis de ses amis**, et qu'elle n'a pas.
> Vous avez les tables `Joueur(id, pseudo)`, `Amitie(joueur_a, joueur_b)` et `Possede(joueur_id, jeu_id)`.
> Écrivez la requête SQL.

On la corrigera au tableau en début de séance 4. Essayez vraiment : c'est plus difficile qu'il n'y paraît.
