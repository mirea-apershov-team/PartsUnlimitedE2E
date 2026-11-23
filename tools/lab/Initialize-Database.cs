using System;
using System.Data.Entity;
using System.Linq;
using PartsUnlimited.Models;
using PartsUnlimited.Utils;

internal static class InitializeDatabase
{
    private static void Main()
    {
        Database.SetInitializer(new PartsUnlimitedDbInitializer());
        using (var context = new PartsUnlimitedContext())
        {
            context.Database.Initialize(false);
            var products = context.Products.Count();
            var categories = context.Categories.Count();
            Console.WriteLine("Original EF initializer completed: {0} products, {1} categories", products, categories);
            if (products != 18 || categories != 5)
            {
                throw new InvalidOperationException("Original catalog seed data is missing");
            }
        }
    }
}
