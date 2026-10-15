using StackExchange.Redis;

namespace PixelHub.Api.Repositories;

public class RedisMatchmakingQueue
{
    private const string Key = "file:matchmaking";
    private readonly IDatabase _db;

    public RedisMatchmakingQueue(IConnectionMultiplexer redis) => _db = redis.GetDatabase();

    public async Task EnqueueAsync(string pseudo) =>
        await _db.ListLeftPushAsync(Key, pseudo);          // LPUSH

    public async Task<string?> DequeueAsync() =>
        await _db.ListRightPopAsync(Key);                  // RPOP

    public async Task<long> LengthAsync() =>
        await _db.ListLengthAsync(Key);                    // LLEN

    // Apparier deux joueurs : une partie se crée
    public async Task<(string, string)?> TryMatchAsync()
    {
        if (await LengthAsync() < 2) return null;
        var a = await DequeueAsync();
        var b = await DequeueAsync();
        return (a is null || b is null) ? null : (a, b);
    }
}