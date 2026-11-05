// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CalculatorCore", products: [.library(name: "CalculatorCore", targets: ["CalculatorCore"])], targets: [
    .target(name: "CalculatorCore", path: "Sources/Core"),
    .testTarget(name: "CalculatorCoreTests", dependencies: ["CalculatorCore"], path: "Tests")
])
