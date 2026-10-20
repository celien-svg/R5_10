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