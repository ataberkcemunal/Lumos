// Offline: favorites live in this executable's own defaults domain. No lamps are contacted.
import Foundation

@main struct FavoritesRegression {
    @MainActor static func main() {
        let store = LightStore()
        store.favoriteColors = ["FF0000", "0000FF", "00FF00"]
        store.favoriteTemperatures = [2200, 2700, 3000, 4200, 6500]
        precondition(!store.canAddFavoriteColor && !store.canAddFavoriteTemperature, "Eight favorites fill the list")

        store.toggleFavoriteColor("FFFF00")
        store.toggleFavoriteTemperature(5000)
        precondition(store.favoriteColors == ["FF0000", "0000FF", "00FF00"], "A full list must not drop a color")
        precondition(store.favoriteTemperatures == [2200, 2700, 3000, 4200, 6500], "A full list must not drop a temperature")

        store.toggleFavoriteTemperature(2200)
        precondition(store.canAddFavoriteColor, "Removing one favorite makes room")
        precondition(!store.canAddFavoriteTemperature || store.favoriteTemperatures.count < LightStore.maximumFavoritesPerKind)
        store.toggleFavoriteTemperature(5000)
        precondition(store.favoriteTemperatures == [2700, 3000, 4200, 5000, 6500], "Temperatures stay sorted")
        precondition(!store.canAddFavoriteTemperature, "A card row fits five of one kind")
        print("PASS: favorites — eight in total, five per kind, nothing dropped silently")
    }
}
