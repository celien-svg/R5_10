using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;
using System.Text.Json.Serialization;

namespace PixelHub.Api.Models;

[BsonIgnoreExtraElements]
public class Game
{
    [BsonId]
    public ObjectId Id { get; set; }

    [BsonElement("titre")]
    public string Titre { get; set; } = "";

    [BsonElement("genre")]
    public string Genre { get; set; } = "";

    [BsonElement("note")]
    public double Note { get; set; }

    [BsonElement("anneeSortie")]
    public int AnneeSortie { get; set; }

    [BsonElement("plateformes")]
    public List<string> Plateformes { get; set; } = new();

    [BsonExtraElements, JsonIgnore]
    public BsonDocument AutresChamps { get; set; } = new();

    // Côté API : les mêmes champs, convertis en types .NET que le JSON sait écrire.
    [BsonIgnore]
    public Dictionary<string, object> Specifiques => AutresChamps.ToDictionary();
    [BsonElement("tags")]
    public List<string> Tags { get; set; } = new();
}