namespace PixelHub.Api.Models;

// Un achat : la trace qui fait foi (PostgreSQL). Le graphe et le classement des ventes n'en sont que des projections.
public class Purchase
{
    public int Id { get; set; }
    public int PlayerId { get; set; }
    public string Titre { get; set; } = "";
    public int PrixPaye { get; set; }       // le prix du jour de l'achat : celui du catalogue peut changer ensuite (TP 2, Q17)
    public DateTime Date { get; set; }      // en UTC : la colonne est un timestamptz
}