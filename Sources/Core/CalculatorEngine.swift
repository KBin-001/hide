import Foundation

struct CalculatorEngine {
    private(set) var display = "0"
    /// Preserves leading zeroes; nil once an operation/decimal invalidates a PIN attempt.
    private(set) var pinCandidate: String? = ""
    private var accumulator: Double?
    private var operation: String?
    private var fresh = true
    private var repeatOperation: String?
    private var repeatOperand: Double?

    mutating func clear() { self = CalculatorEngine() }

    mutating func press(_ key: String) {
        if key == "AC" { clear(); return }
        if key.count == 1, let digit = key.first, digit.isNumber {
            if let candidate = pinCandidate {
                pinCandidate = candidate.count < 12 ? candidate + key : nil
            }
            if fresh { display = key; fresh = false }
            else if display.count < 16 { display = display == "0" ? key : display + key }
            return
        }
        pinCandidate = nil
        switch key {
        case ".":
            if fresh { display = "0"; fresh = false }
            if !display.contains(".") { display += "." }
        case "+/−":
            if let n = Double(display) { display = format(-n) }
        case "%":
            if let n = Double(display) { display = format(n / 100) }
        case "+", "−", "×", "÷":
            guard let n = Double(display) else { clear(); return }
            if let a = accumulator, let op = operation, !fresh {
                let result = evaluate(a, op, n)
                display = format(result)
                accumulator = result.isFinite ? result : nil
            } else { accumulator = n }
            operation = key; fresh = true
            repeatOperation = nil; repeatOperand = nil
        case "=":
            guard let n = Double(display) else { return }
            if let a = accumulator, let op = operation {
                display = format(evaluate(a, op, n))
                repeatOperation = op; repeatOperand = n
            } else if let op = repeatOperation, let rhs = repeatOperand {
                display = format(evaluate(n, op, rhs))
            }
            accumulator = nil; operation = nil; fresh = true
        default: break
        }
    }

    private func evaluate(_ lhs: Double, _ op: String, _ rhs: Double) -> Double {
        switch op {
        case "+": return lhs + rhs
        case "−": return lhs - rhs
        case "×": return lhs * rhs
        case "÷": return rhs == 0 ? .nan : lhs / rhs
        default: return rhs
        }
    }
    private func format(_ value: Double) -> String {
        guard value.isFinite else { return "错误" }
        return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
