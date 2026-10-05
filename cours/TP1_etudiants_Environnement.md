# TP 1 — Mise en place de l'environnement

**R5.A.10 — Nouveaux paradigmes de bases de données**
Durée : 1 h 30 · À rendre : rien aujourd'hui, mais **votre environnement doit fonctionner avant de partir**

---

## Objectif

À la fin de ce TP, vous aurez :

- **quatre moteurs de bases de données** qui tournent sur votre machine, sans en avoir installé aucun ;
- l'application **PixelHub** qui démarre et répond ;
- une première brique fonctionnelle : la gestion des joueurs dans **PostgreSQL**.

C'est le point de départ. Pendant les cinq séances suivantes, vous ajouterez un moteur de plus à *cette même application*.

> **Important** : ne partez pas de la salle avec un environnement cassé. Les 15 heures suivantes reposent sur celui d'aujourd'hui. Si quelque chose ne marche pas, appelez — c'est le but de cette séance.

---

## Avant de commencer

Vérifiez que vous avez tout. Dans un terminal :

```bash
docker --version
docker compose version
dotnet --version
```

Les trois commandes doivent répondre avec un numéro de version. Si l'une échoue, reportez-vous à l'**annexe d'installation** ou appelez l'enseignant.

Récupérez ensuite le **dépôt de départ** (lien fourni par l'enseignant), et placez-vous dans le dossier :

```bash
cd pixelhub
```

---

## Étape 1 — Lire avant de lancer (15 min)

Ouvrez le fichier `docker-compose.yml`. **Ne lancez rien encore.**

Ce fichier décrit quatre services, un par moteur de base de données. Lisez-le, puis répondez à ces questions par écrit (sur papier ou dans un fichier `notes.md`) :

**Q1.** Le fichier déclare quatre services alors que le TP d'aujourd'hui n'en utilise qu'un. Pourquoi, à votre avis ?
        car on as dit 1 patr séance

**Q2.** Trois services ont une section `volumes`, un seul n'en a pas. Lequel, et qu'est-ce que ça implique pour ses données ?
        redis  car c'est donnée ne sont pas fix
**Q3.** Que signifie la ligne `"15432:5432"` ? Les deux nombres ne désignent pas la même chose.
        une adresse pour un loclahost par exemple

**Q4.** Les mots de passe sont écrits en clair dans le fichier. Est-ce acceptable ici ? Le serait-ce sur un serveur de production ?
        la oui c'est un travail sans importance si c'est sur un serveur en prod alors là sa seais grave car les utilisateur pourrais avoir acces a la base
> Ces questions seront reprises à l'oral. Prenez-les au sérieux : la question 3 en particulier vous évitera une demi-heure de blocage plus tard.

---

## Étape 2 — Démarrer les quatre moteurs (20 min)

### 2.1 Lancer

```bash
docker compose up -d
```

`-d` signifie *detached* : les conteneurs tournent en arrière-plan et vous récupérez votre terminal.

**Le premier lancement télécharge plusieurs gigaoctets d'images.** C'est normal que ce soit long. Si vous voyez « Pulling » pendant plusieurs minutes, laissez faire.

### 2.2 Vérifier que les quatre tournent

```bash
docker compose ps
```

Vous devez voir quatre services à l'état `running`. Si l'un est en `exited` ou `restarting`, notez son nom et consultez la section **Problèmes fréquents** à la fin de ce sujet.

### 2.3 Vérifier chaque moteur individuellement

**Ne sautez pas cette étape.** « Le conteneur tourne » ne veut pas dire « le moteur répond ».

```bash
# PostgreSQL → doit répondre "accepting connections"
docker compose exec postgres pg_isready -U pixelhub

# Redis → doit répondre PONG
docker compose exec redis redis-cli ping

# MongoDB → doit répondre { ok: 1 }
docker compose exec mongo mongosh -u pixelhub -p pixelhub_dev  --authenticationDatabase admin --eval "db.runCommand({ping:1})"
```

**Neo4j** : ouvrez `http://localhost:17474` dans votre navigateur, et connectez-vous avec l'utilisateur `neo4j` et le mot de passe `pixelhub_dev`.

> Neo4j met **20 à 40 secondes** à démarrer, bien plus que les autres. Si la page ne répond pas tout de suite, attendez et réessayez. Pour suivre son démarrage : `docker compose logs neo4j`.

### 2.4 À noter dans vos notes

**Q5.** Les commandes ci-dessus utilisent `docker compose exec`. Qu'est-ce que ça fait exactement ? Où s'exécute la commande `redis-cli` ?
exécute une commande dans un conteneur déjà démarré. Ici, redis-cli s’exécute à l’intérieur du conteneur du service redis, et non directement sur votre ordinateur. Il interroge Redis, puis affiche PONG si le serveur répond. Le conteneur reste en marche après la commande.
---

## Étape 3 — L'application PixelHub (40 min)

On part de ce que vous maîtrisez : une API et une base relationnelle. Rien de nouveau aujourd'hui — c'est voulu, c'est la base sur laquelle on va greffer le reste.

### 3.1 Installer les paquets

```bash
cd src/PixelHub.Api
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add package Microsoft.EntityFrameworkCore.Design
```

### 3.2 Le modèle

Créez `Models/Player.cs` :

```csharp
namespace PixelHub.Api.Models;

public class Player
{
    public int Id { get; set; }
    public string Pseudo { get; set; } = "";
    public int Coins { get; set; }          // monnaie virtuelle
}
```

### 3.3 Le contexte

Créez `Data/PixelHubContext.cs` :

```csharp
using Microsoft.EntityFrameworkCore;
using PixelHub.Api.Models;

namespace PixelHub.Api.Data;

public class PixelHubContext : DbContext
{
    public PixelHubContext(DbContextOptions<PixelHubContext> options)
        : base(options) { }

    public DbSet<Player> Players => Set<Player>();
}
```

### 3.4 La chaîne de connexion

Dans `appsettings.json`, ajoutez :

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Port=15432;Database=pixelhub;Username=pixelhub;Password=pixelhub_dev"
  }
}
```

**Q6.** La base de données tourne dans un conteneur Docker, et la chaîne de connexion dit `Host=localhost`. Pourquoi est-ce que ça fonctionne ? (Indice : relisez votre réponse à la Q3.) car l'api est lancé directement sur la machine hote

### 3.5 Program.cs

```csharp
using Microsoft.EntityFrameworkCore;
using PixelHub.Api.Data;
using PixelHub.Api.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<PixelHubContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Postgres")));

var app = builder.Build();

// Crée la base et les tables au démarrage.
// Suffisant en TP ; dans un vrai projet, on utilise les migrations EF Core.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<PixelHubContext>();
    db.Database.EnsureCreated();

    if (!db.Players.Any())
    {
        db.Players.AddRange(
            new Player { Pseudo = "Nova",  Coins = 1200 },
            new Player { Pseudo = "Krayz", Coins = 350  },
            new Player { Pseudo = "Ombre", Coins = 90   }
        );
        db.SaveChanges();
    }
}

app.MapGet("/", () => "PixelHub API — séance 1 OK");

app.MapGet("/players", async (PixelHubContext db) =>
    await db.Players.ToListAsync());

app.Run();
```

### 3.6 Lancer et tester

```bash
dotnet run
```

Notez le **port** affiché au démarrage (une ligne du type `Now listening on: http://localhost:5199`). Il est propre à votre projet.

Pour tester, ouvrez le fichier `PixelHub.Api.http` fourni dans le dépôt, ajustez la ligne `@host` avec votre port, puis cliquez sur **Send request** au-dessus de la requête `GET /players`.

> **Attention** : il n'y a **pas de page Swagger**. Depuis .NET 9, l'interface Swagger n'est plus incluse dans les modèles de projet. On utilise les fichiers `.http`, qui sont intégrés à Visual Studio.

**Résultat attendu** : trois joueurs en JSON.

```json
[
  { "id": 1, "pseudo": "Nova",  "coins": 1200 },
  { "id": 2, "pseudo": "Krayz", "coins": 350  },
  { "id": 3, "pseudo": "Ombre", "coins": 90   }
]
```

### 3.7 Vérifier côté base

Les données sont-elles vraiment dans PostgreSQL, ou seulement en mémoire ? Vérifiez :

```bash
docker compose exec postgres psql -U pixelhub -d pixelhub -c "SELECT * FROM \"Players\";"
```

**Q7.** Arrêtez l'application (Ctrl+C), relancez-la. Les trois joueurs sont-ils dupliqués ? Pourquoi ?

---

## Étape 4 — Arrêter proprement (5 min)

Prenez la bonne habitude dès aujourd'hui :

```bash
docker compose stop
```

Et retenez bien la différence, parce que la confusion vous coûtera vos données en séance 3 ou 4 :

| Commande | Effet |
|---|---|
| `docker compose stop` | Éteint les conteneurs. **Données conservées.** À utiliser en fin de séance. |
| `docker compose down` | Supprime les conteneurs. Données conservées (elles vivent dans les volumes). |
| `docker compose down -v` | Supprime les conteneurs **et les volumes**. ⚠️ **Tout est perdu.** |

`down -v` est parfois la solution à un problème (voir plus bas), mais ne l'utilisez jamais « pour faire propre ».

---

## Avant de partir — checklist

Faites valider par l'enseignant :

- [ ] `docker compose ps` affiche les services attendus en `running`
- [ ] `docker compose exec redis redis-cli ping` répond `PONG`
- [ ] `http://localhost:17474` affiche le Neo4j Browser
- [ ] L'application démarre sans erreur
- [ ] `/players` renvoie les trois joueurs en JSON
- [ ] Je sais dire la différence entre `docker compose stop` et `down -v`
- [ ] **Mon travail est sauvegardé ailleurs qu'en local** (dépôt Git, ou archive personnelle)

Le dernier point est important : sur un poste de salle, un profil réinitialisé entre deux séances fait perdre tout le travail.

---

## Problèmes fréquents

### `port already in use` / un conteneur refuse de démarrer

Un service occupe déjà le port sur votre machine — typiquement un PostgreSQL installé en dur.

Pour identifier le coupable :
```bash
# Windows (PowerShell)
netstat -ano | findstr :15432
# macOS / Linux
lsof -i :15432
```

**Solution** : modifiez le port dans le fichier `.env` (par exemple `PG_PORT=15433`), **et n'oubliez pas de modifier `appsettings.json` en conséquence.** L'incohérence entre les deux fichiers est la première cause d'erreur de connexion.

### `permission denied ... docker.sock` (Linux)

Votre compte n'est pas dans le groupe `docker`.

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Ne préfixez pas vos commandes par `sudo` pour contourner : ça crée des fichiers appartenant à `root` dans votre projet, et ça vous causera des erreurs incompréhensibles plus tard.

### Docker Desktop reste bloqué sur « Starting » (Windows)

```powershell
wsl --update
```
puis redémarrez. Si le problème persiste, la virtualisation est peut-être désactivée dans le BIOS — dans ce cas, signalez-le à l'enseignant, vous ne pouvez pas le résoudre seul sur un poste de l'IUT.

### `Failed to connect to 127.0.0.1:15432`

À vérifier dans cet ordre :

1. les conteneurs tournent-ils ? → `docker compose ps`
2. PostgreSQL est-il prêt ? → `docker compose exec postgres pg_isready -U pixelhub`
3. le port de `appsettings.json` correspond-il à celui du `.env` ?
4. le mot de passe est-il le même dans les deux fichiers ?
5. si vous avez fait un essai précédent avec un **autre mot de passe** : les variables du compose ne s'appliquent qu'à la *première* initialisation du volume. Il faut réinitialiser :
   ```bash
   docker compose down -v
   docker compose up -d
   ```

### Neo4j refuse le mot de passe

Neo4j 5 exige un mot de passe d'au moins 8 caractères. Utilisez celui du fichier compose. Si le volume a déjà été initialisé avec un mot de passe refusé : `docker compose down -v`.

### Le téléchargement des images n'en finit pas

30 postes qui téléchargent en même temps saturent le réseau. Aujourd'hui, **seul PostgreSQL est réellement nécessaire** :

```bash
docker compose up -d postgres
```

Vous tirerez les trois autres en fin de séance ou avant la prochaine.

---

## Pour aller plus loin (optionnel)

Si vous avez terminé en avance :

1. Connectez-vous à Neo4j Browser et exécutez `CREATE (n:Test {nom: 'coucou'}) RETURN n`. Observez le résultat affiché sous forme de graphe. Puis supprimez : `MATCH (n:Test) DELETE n`.
2. Dans `redis-cli`, essayez `SET essai "bonjour"` puis `GET essai`, puis `SET temporaire "vite" EX 10` et interrogez `TTL temporaire` plusieurs fois de suite. Que se passe-t-il au bout de 10 secondes ?
3. Ajoutez un endpoint `POST /players` qui crée un joueur, et testez-le depuis le fichier `.http`.

---

## Pour la prochaine séance

Gardez sous les yeux la modélisation relationnelle du catalogue de jeux faite en début de séance — celle avec les colonnes vides ou les tables par genre. La séance 2 en est la résolution directe, et on la comparera à ce que vous aurez produit.
