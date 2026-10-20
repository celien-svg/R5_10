using PixelHub.Api.Models;

namespace PixelHub.Api.Repositories;

public record GenreStats(string Genre, double NoteMoyenne, int Nombre);
public interface IGameCatalog
{
    Task<List<Game>> GetAllAsync();
    Task<List<Game>> GetByGenreAsync(string genre);
    Task<List<Game>> GetTopRatedAsync(int count);
    Task<List<GenreStats>> GetStatsByGenreAsync();
    Task<Game?> GetByTitleAsync(string titre);                        // la boutique
    Task<List<Game>> GetByTitlesAsync(IEnumerable<string> titres);     // la fiche joueur : une seule requête
}