using System.Text.Json;
using PixelHub.Api.Models;
using StackExchange.Redis;

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

    public Task<List<Game>> GetByGenreAsync(string genre) => _source.GetByGenreAsync(genre);
    public Task<List<Game>> GetTopRatedAsync(int count) => _source.GetTopRatedAsync(count);
    public Task<List<GenreStats>> GetStatsByGenreAsync() => _source.GetStatsByGenreAsync();
    public Task<Game?> GetByTitleAsync(string titre) => _source.GetByTitleAsync(titre);
    public Task<List<Game>> GetByTitlesAsync(IEnumerable<string> titres) => _source.GetByTitlesAsync(titres);

}
