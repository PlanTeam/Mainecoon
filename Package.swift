import PackageDescription

let package = Package(
    name: "Mainecoon",
    dependencies: [
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", "3.0.0-alpha3"),
        .Package(url: "https://github.com/Zewo/Reflection.git", majorVersion: 0, minor: 14)
    ]
)
