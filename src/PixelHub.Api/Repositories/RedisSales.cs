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
        await _db.SortedSetIncrementAsync(Key, titre, 1);

    // Reconstruction complète depuis la source de vérité : on jette la projection et on la réécrit.
    public async Task ReplaceAllAsync(IEnumerable<GameSales> ventes)
    {
        await _db.KeyDeleteAsync(Key);
        var entries = ventes.Select(v => new SortedSetEntry(v.Titre, v.Ventes)).ToArray();
        if (entries.Length > 0)
            await _db.SortedSetAddAsync(Key, entries);
    }

    public async Task<List<GameSales>> GetTopAsync(int count)
    {
        var entries = await _db.SortedSetRangeByRankWithScoresAsync(Key, 0, count - 1, Order.Descending);
        return entries.Select(e => new GameSales(e.Element!, (long)e.Score)).ToList();
    }

}