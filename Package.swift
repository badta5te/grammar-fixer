// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarFixer",
    platforms: [.macOS(.v14)],
    targets: [
        // Исполняемый таргет намеренно пустой: в нём только точка входа.
        // Всё остальное живёт в библиотеке, потому что модуль с точкой входа
        // нельзя импортировать из тестов.
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
