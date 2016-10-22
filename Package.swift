import PackageDescription

let package = Package(
    name: "Mainecoon",
    dependencies: [
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", majorVersion: 2)
    ]
)
