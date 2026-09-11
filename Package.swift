// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarFixer",
    platforms: [.macOS(.v14)],
    targets: [
        // The executable target is deliberately empty and holds only the
        // entry point. Everything else lives in the library, because a module
        // with an entry point cannot be imported from tests.
        .executableTarget(
            name: "GrammarFixer",
            dependencies: ["GrammarFixerCore"],
            path: "Sources/GrammarFixer"
        ),
        .target(
            name: "GrammarFixerCore",
            path: "Sources/GrammarFixerCore"
        ),
        .testTarget(
            name: "GrammarFixerTests",
            dependencies: ["GrammarFixerCore"],
            path: "Tests/GrammarFixerTests"
        ),
    ]
)
