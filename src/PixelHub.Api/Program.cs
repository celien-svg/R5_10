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

app.Run();
