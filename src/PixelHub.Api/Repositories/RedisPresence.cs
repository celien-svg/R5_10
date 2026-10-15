using StackExchange.Redis;

namespace PixelHub.Api.Repositories;

public class RedisPresence
{
    private const string Key = "presence:online";
    private readonly IDatabase _db;

    public RedisPresence(IConnectionMultiplexer redis) => _db = redis.GetDatabase();

    public async Task TouchAsync(string pseudo)
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        await _db.SortedSetAddAsync(Key, pseudo, now);
    }

    public async Task<long> CountOnlineAsync()
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var threshold = now - 60;
        return await _db.SortedSetLengthAsync(Key, threshold, now);
    }

    public async Task CleanupAsync()
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var threshold = now - 60;
        await _db.SortedSetRemoveRangeByScoreAsync(Key, double.NegativeInfinity, threshold);
    }
}
