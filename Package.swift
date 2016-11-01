import PackageDescription

let package = Package(
    name: "Mainecoon",
    dependencies: [
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", "3.0.0-alpha")
    ]
)
