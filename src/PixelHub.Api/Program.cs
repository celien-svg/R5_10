using Microsoft.EntityFrameworkCore;
using PixelHub.Api.Data;
using PixelHub.Api.Models;
using MongoDB.Driver;
using PixelHub.Api.Repositories;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<PixelHubContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Postgres")));

// Le MongoClient est thread-safe et gère son propre pool de connexions :
// on l'enregistre donc en singleton.
builder.Services.AddSingleton<IMongoClient>(_ =>
    new MongoClient(builder.Configuration.GetConnectionString("Mongo")));

builder.Services.AddSingleton<IMongoDatabase>(sp =>
    sp.GetRequiredService<IMongoClient>()
      .GetDatabase(builder.Configuration["Mongo:Database"]));

builder.Services.AddSingleton<IGameCatalog, MongoGameCatalog>();

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
            new Player { Pseudo = "Nova", Coins = 1200 },
            new Player { Pseudo = "Krayz", Coins = 350 },
            new Player { Pseudo = "Ombre", Coins = 90 }
        );
        db.SaveChanges();
    }
}

app.MapGet("/", () => "PixelHub API — séance 1 OK");

// ---------- Séance 1 — PostgreSQL ----------
app.MapGet("/players", async (PixelHubContext db) =>
    await db.Players.ToListAsync());

// Bonus du TP 1 : c'est PostgreSQL qui attribue l'Id (repris en Q1 du TP 2).
app.MapPost("/players", async (Player player, PixelHubContext db) =>
{
    db.Players.Add(player);
    await db.SaveChangesAsync();
    return Results.Created($"/players/{player.Id}", player);
});

app.MapGet("/games", async (IGameCatalog catalog) =>
    await catalog.GetAllAsync());

app.MapGet("/games/genre/{genre}", async (string genre, IGameCatalog catalog) =>
    await catalog.GetByGenreAsync(genre));

app.MapGet("/games/top/{count:int}", async (int count, IGameCatalog catalog) =>
    await catalog.GetTopRatedAsync(count));

app.MapGet("/games/stats", async (IGameCatalog catalog) =>
    await catalog.GetStatsByGenreAsync());

app.Run();
