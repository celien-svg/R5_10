# Installer votre environnement — Windows, macOS, Linux

**R5.A.10 — Nouveaux paradigmes de bases de données**
À faire **avant la séance 1** si possible : comptez 30 minutes et un redémarrage. Tout ce qui est téléchargé chez vous ne sera pas téléchargé sur le Wi-Fi de l'IUT.

---

## Ce qu'il vous faut

- **Docker** : Docker Desktop (Windows, macOS) ou Docker Engine (Linux). Gratuit dans un cadre étudiant.
- **Le SDK .NET 10** et un IDE : Visual Studio 2026 Community sous Windows, ou VS Code + extension *C# Dev Kit*, ou JetBrains Rider (licence étudiante gratuite), sur les trois systèmes.
- Environ **5 Go d'espace disque** (les quatre images de bases de données pèsent 2,8 Go) et **8 Go de RAM** recommandés.

Rien d'autre. Les bases de données (PostgreSQL, MongoDB, Redis, Neo4j) ne s'installent pas : elles tournent dans Docker, en une commande. Si vous avez déjà un PostgreSQL ou un Redis installé sur votre machine, il ne gênera pas : le module utilise des ports décalés (15432, 27018, 16379, 17474, 17687).

---

## 1. Windows

1. **Virtualisation.** Sur un PC personnel, elle est presque toujours déjà activée. Vérifiez : Gestionnaire des tâches → Performance → Processeur → « Virtualisation : activée ». Sinon, activez-la dans le BIOS/UEFI (option nommée *Intel VT-x*, *AMD-V* ou *SVM Mode*).
2. **WSL 2.** Dans un terminal PowerShell ouvert **en administrateur** :
   ```powershell
   wsl --install
   wsl --update
   ```
   Puis redémarrez.
3. **Docker Desktop.** Téléchargez-le sur `docker.com` et installez-le en laissant cochée l'option « Use WSL 2 based engine ». Lancez-le et attendez que l'icône indique « Engine running ». La création d'un compte Docker n'est pas nécessaire.
4. **.NET et l'IDE.** Installez **Visual Studio 2026 Community** (`visualstudio.microsoft.com`) en cochant la charge de travail **« Développement ASP.NET et web »** : le SDK .NET est inclus. Alternative plus légère : le SDK .NET 10 seul (`dotnet.microsoft.com`) et VS Code avec l'extension *C# Dev Kit*.
5. Passez à la **vérification commune** ci-dessous.

> Si vous avez déjà **Visual Studio 2022** : il ne sait pas ouvrir un projet .NET 10. Installez le SDK .NET 10 à côté et utilisez VS Code, ou lisez la section 6.

---

## 2. macOS

1. **Intel ou Apple Silicon ?** Menu Pomme → *À propos de ce Mac*. Puce « M1 » et suivantes = Apple Silicon ; « Intel Core » = Intel. Les quatre moteurs du module fonctionnent nativement sur les deux, rien à adapter.
2. **Docker.** Au choix :
   - **Docker Desktop** : téléchargez le `.dmg` correspondant à votre architecture (l'erreur classique est de se tromper), glissez-le dans Applications, lancez-le.
   - **Colima**, plus léger, en ligne de commande :
     ```bash
     brew install colima docker docker-compose
     colima start --cpu 2 --memory 4
     ```
   Dans Docker Desktop, donnez au moins **4 Go de RAM** à Docker (*Settings → Resources*) : avec quatre moteurs simultanés, c'est un plancher.
3. **.NET et l'IDE.** Visual Studio pour Mac n'existe plus. Installez le SDK puis un éditeur :
   ```bash
   brew install --cask dotnet-sdk
   dotnet --version
   ```
   puis **VS Code + C# Dev Kit** (gratuit) ou **JetBrains Rider** (licence étudiante gratuite). Le code, les paquets NuGet et les commandes `dotnet` sont identiques à ceux de Windows : seul l'IDE change.
4. Passez à la **vérification commune**.

---

## 3. Linux (Debian / Ubuntu)

1. **Docker Engine**, depuis le dépôt officiel Docker (les paquets de la distribution sont souvent anciens) :
   ```bash
   sudo apt update
   sudo apt install -y ca-certificates curl gnupg
   sudo install -m 0755 -d /etc/apt/keyrings
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
     | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
     https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
     | sudo tee /etc/apt/sources.list.d/docker.list
   sudo apt update
   sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
   ```
2. **Le groupe `docker`**, l'étape que tout le monde oublie :
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker        # ou déconnectez-vous puis reconnectez-vous
   ```
   Sans elle, chaque commande Docker renvoie `permission denied while trying to connect to the Docker daemon socket`. Ne contournez pas en préfixant tout par `sudo` : cela crée des fichiers appartenant à root dans votre projet et provoque des erreurs incompréhensibles plus tard.
3. **.NET et l'IDE.**
   ```bash
   sudo apt install -y dotnet-sdk-10.0
   dotnet --version
   ```
   Si le paquet n'existe pas dans votre distribution, utilisez le dépôt de paquets Microsoft ou le script officiel `dotnet-install.sh`. IDE : **VS Code + C# Dev Kit**, ou **JetBrains Rider**.
4. Passez à la **vérification commune**.

---

## 4. Vérification commune (tous systèmes)

Les quatre commandes doivent répondre sans erreur :

```bash
docker --version
docker compose version
docker run --rm hello-world       # télécharge une image minuscule et affiche "Hello from Docker!"
dotnet --version                  # 10.x attendu
```

Si `hello-world` fonctionne, Docker est prêt : la suite (démarrer les quatre moteurs, lancer l'application) est décrite dans le sujet du TP 1 et se fait à l'identique sur les trois systèmes.

---

## 5. Gagnez du temps : pré-téléchargez les images

Une fois Docker installé, lancez chez vous, sur une bonne connexion :

```bash
docker pull postgres:17
docker pull mongo:8
docker pull redis:7-alpine
docker pull neo4j:5
```

Environ 2,8 Go. Trente personnes qui les téléchargent en même temps sur le Wi-Fi de l'IUT, c'est une demi-heure de TP perdue. Si vous récupérez le dépôt de départ avant la séance, `docker compose pull` dans le dossier `pixelhub` fait la même chose.

---

## 6. Si vous ne pouvez pas installer .NET 10

Le projet cible `net10.0`. Avec seulement le SDK .NET 8 (celui de Visual Studio 2022), deux adaptations, et rien d'autre ne change dans le module :

1. Dans `src/PixelHub.Api/PixelHub.Api.csproj`, remplacez `<TargetFramework>net10.0</TargetFramework>` par `<TargetFramework>net8.0</TargetFramework>`.
2. À l'étape 3.1 du TP, ajoutez les paquets **avec un numéro de version** (sans lui, `dotnet` prend la dernière version, 10.x, incompatible avec .NET 8) :
   ```bash
   dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL --version 8.0.11
   dotnet add package Microsoft.EntityFrameworkCore.Design --version 8.0.11
   ```

---

## 7. Problèmes fréquents

| Symptôme | Cause probable | Solution |
|---|---|---|
| Docker Desktop reste sur « Starting » (Windows) | WSL 2 absent ou ancien | `wsl --update` en administrateur, puis redémarrer |
| Erreur mentionnant la virtualisation | Désactivée au BIOS | Section 1, étape 1 |
| `permission denied … docker.sock` (Linux) | Pas dans le groupe `docker` | Section 3, étape 2 |
| `port already in use` | Un service occupe le port | Modifier le port dans le fichier `.env` du dépôt, et `appsettings.json` si c'est PostgreSQL |
| `Pulling` interminable | Réseau saturé | `docker compose up -d postgres` : seul PostgreSQL sert en séance 1 |
| Neo4j ne répond pas tout de suite | Il met 20 à 40 s à démarrer | Attendre, `docker compose logs neo4j` |
| Mac : conteneurs lents, Neo4j tombe | RAM allouée à Docker trop faible | *Settings → Resources*, 4 Go minimum |
| `dotnet run` : « The current .NET SDK does not support targeting .NET 10.0 » | SDK trop ancien | Installer le SDK 10, ou section 6 |

En cas de blocage persistant, venez quand même en séance : on vous mettra en binôme avec un poste qui fonctionne, et on réglera votre installation à la pause.
