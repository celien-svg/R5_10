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