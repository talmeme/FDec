//
//   ____  ____   ____   ___
//  (  __)(    \ (  __) / __)
//   ) _)  ) D (  ) _) ( (__   Mtrn (C)
//  (__)  (____/ (____) \___)  2023.07.30.
//
//  https://github.com/metatronsw/FDec.git

// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import Synchronization

/// A fixed decimal number format.
///
public struct FDec: Sendable {

	/// The value actually shifted & stored inernaly
	private(set) var value: Int

	// MARK: Init default

	/// Default Zero init
	public init() { value = 0 }

	/// Init from Self.
	public init(_ F: FDec) { value = F.value }

	/// Init from shifted raw value.
	public init(raw: Int) { value = raw }

}

extension FDec {

	// MARK: Private - Helper for concurrency-safety.

        private struct VarGroup {
            let decimalPlaces: Int
            let pow: Int
            let zeroShift: String
            let intMaxDecimals: Int

            init(_ decimalPlaces: Int) {
                self.decimalPlaces = decimalPlaces
                self.pow = decimalPlaces.pow10()
                self.zeroShift = String(repeating: "0", count: decimalPlaces)
                self.intMaxDecimals = 19 - decimalPlaces
            }
        }

	// MARK: Public Static - Project based config & helpers

	/// Project-based setting that lets you set the number of decimal places.
	///
        private static let varGroup: Mutex<VarGroup> = .init(VarGroup(4))
        public static var decimalPlaces: Int {
            get {
                varGroup.withLock { value in
                    value.decimalPlaces
                }
            }
            set {
                varGroup.withLock { value in
                    value = VarGroup(newValue)
                }
            }
        }

	public static var pow: Int {
            get {
                varGroup.withLock { value in
                    value.pow
                }
            }
        }
	public static var zeroShift: String {
            get {
                varGroup.withLock { value in
                    value.zeroShift
                }
            }
        }
	public static var intMaxDecimals: Int {
            get {
                varGroup.withLock { value in
                    value.intMaxDecimals
                }
            }
        }

	public static let zero = FDec()
	public static let infinity = FDec(raw: Int.max)
	public static let nan = FDec(raw: Int.min)

	// MARK: Private Static - Helper numbers, for quick internal operations

	private static let half: Int = 1_000_000_000
	private static let high: Int = 100_000_000_000_000
	private static let full: Int = 1_000_000_000_000_000_000

}

extension FDec {

	// MARK: Computed vars

	/// Shifted & stored internal value { get }
	public var rawValue: Int { value }

	public var isPositive: Bool { value > 0 }
	public var isNegative: Bool { value < 0 }
	public var isZero: Bool { value == 0 }
	public var isOdd: Bool { value & 1 == 1 }
	public var isEven: Bool { value & 1 == 0 }
	public var isDecimal: Bool { value % Self.pow != 0 }
	public var isInfinity: Bool { value == Int.max }
	public var isNan: Bool { value == Int.min }

	private mutating func overflow() {
		value = Int.max
	}

}

extension FDec: ExpressibleByIntegerLiteral {

	public typealias IntegerLiteralType = Int

	public init(integerLiteral value: Int) {
		let (raw, over) = value.multipliedReportingOverflow(by: Self.pow)
		assert(!over, "IntegerLiteral Overflow! \(value)")
		self.value = raw
	}

	public init?<T>(_ source: T) where T: BinaryInteger {
		let (raw, over) = Int(source).multipliedReportingOverflow(by: Self.pow)
		guard !over else { return nil }
		value = raw
	}
	
	public init?<T>(exactly source: T) where T: BinaryInteger {
		self.init(source)
	}

	public init(_ value: Int8) { self.init(integerLiteral: Int(value)) }
	public init(_ value: UInt8) { self.init(integerLiteral: Int(value)) }

	public init(_ value: Int16) { self.init(integerLiteral: Int(value)) }
	public init(_ value: UInt16) { self.init(integerLiteral: Int(value)) }

	public init(_ value: Int32) { self.init(integerLiteral: Int(value)) }
	public init(_ value: UInt32) { self.init(integerLiteral: Int(value)) }

	public init?(_ value: Int) { self.init(integerLiteral: value) }
	public init?(_ value: UInt) { self.init(integerLiteral: Int(value)) }

	public init?(_ value: Int64) { self.init(integerLiteral: Int(value)) }
	public init?(_ value: UInt64) { self.init(integerLiteral: Int(value)) }

	
	
	// MARK: Computed variables

	public var asInt: Int { value / Self.pow }

	public var asUInt32: UInt32? { UInt32(value / Self.pow) }

	public var digitCount: Int { Int(log10(Double(asInt))) + 1 }

}

extension Int {
	public init(_ F: FDec) { self = F.asInt }
}

extension FDec: ExpressibleByFloatLiteral {

	public typealias FloatLiteralType = Double

	public init?(_ value: Double) {
		
		guard value <= Double(Int.max / Self.pow).magnitude else { return nil }

		let shifted = value * Double(Self.pow)
		
		guard let raw = Int(exactly: shifted) else {
			print("Failed exactly init! \(value) » \(shifted)")
			return nil
		}

		self.value = raw
	}

	public init(truncating value: Double) {
		let shifted = value * Double(Self.pow)
		let truncated = Int(shifted)
		self.value = truncated
	}

	public init(floatLiteral value: Double) {
		guard let inited = Self(value) else { fatalError("Failed floatLiteral init! \(value)") }

		self.value = inited.value
	}

	public init?(_ value: Float) { self.init(Double(value)) }

	public init?<T>(exactly source: T) where T: BinaryFloatingPoint {
		guard let int = Int(exactly: source) else { return nil }
		let (raw, over) = int.multipliedReportingOverflow(by: Self.pow)
		guard !over else { return nil }
		value = raw
	}
	
	// MARK: Output

	public var asDouble: Double { Double(value) / Double(Self.pow) }
	
	public var asFloat: Float { Float(value) / Float(Self.pow) }

	public var fraction: Double { Double(value % Self.pow) / Double(Self.pow) }

}

extension Double {
	public init(_ F: FDec) { self = F.asDouble }
}

extension Float {
	public init(_ F: FDec) { self = F.asFloat }
}


extension FDec: ExpressibleByStringLiteral, LosslessStringConvertible, CustomDebugStringConvertible {

	public typealias StringLiteralType = String

	public init(stringLiteral: String) {
		let clean = stringLiteral
			.replacingOccurrences(of: "_", with: "")
			.replacingOccurrences(of: " ", with: "")

		guard let inited = Self(clean) else { fatalError("Failed stringLiteral init! \(stringLiteral)") }

		value = inited.value
	}

	public init?(_ description: String) {
		let parts = description
			.replacingOccurrences(of: ",", with: ".")
			.components(separatedBy: ".")

		guard let int = parts.first else { print("Wrong description! \(description)"); return nil }

		var frc: String

		if parts.count > 1 {
			frc = String(parts[1].prefix(Self.decimalPlaces))
			if frc.count < Self.decimalPlaces {
				frc = frc + String(repeating: "0", count: Self.decimalPlaces - frc.count)
			}
		} else {
			frc = Self.zeroShift
		}

		guard let raw = Int(int + frc) else {
			print(#line, "FDec String Init fail! '\(int).\(frc)'")
			return nil
		}

		value = raw
	}

	public init?(int: String, frc: String = Self.zeroShift, sign: String = "") {
		var frc = frc

		if frc.count > Self.decimalPlaces { frc = String(frc.suffix(Self.decimalPlaces)) }
		while frc.count < Self.decimalPlaces {
			frc.append("0")
		}

		guard let raw = Int(sign + int + frc) else { print("Overflow! \(int).\(frc)"); return nil }

		value = raw
	}
	
	public init?(_ substring: Substring) {
		self.init(String(substring))
	}


	// MARK: Output

	public var description: String {
		guard !isZero else { return "0" }

		guard !isInfinity else { return "Infinity" }

		guard isDecimal else { return String(String(value).dropLast(Self.decimalPlaces)) }

		var string: String
		var whole = String(value.magnitude)

		if whole.count <= Self.decimalPlaces {
			string = sign + "0." + String(repeating: "0", count: Self.decimalPlaces - whole.count) + whole
		} else {
			whole.insert(".", at: whole.index(whole.endIndex, offsetBy: -Self.decimalPlaces))
			string = sign + whole
		}

		string.dropLastZeros()

		return string
	}

	public var debugDescription: String {
		"\(description) ➞ \(value) * 10^\(Self.decimalPlaces) ➞ \(asInt) & \(fraction)"
	}

	public func formatted(fullSign: Bool = false,
								 groupingSize: Int = 3,
								 decimalSeparator: String? = nil,
								 groupingSeparator: String? = nil) -> String {
		guard !isZero else { return "0" }

		let decimalSep = decimalSeparator ?? (Locale.current.decimalSeparator ?? ".")
		let groupingSep = groupingSeparator ?? (Locale.current.groupingSeparator ?? " ")

		let whole = String(value.magnitude)
		let signstr = fullSign ? signFull : sign

		guard whole.count > Self.decimalPlaces else {
			var frc = signstr + "0" + decimalSep + String(repeating: "0", count: Self.decimalPlaces - whole.count) + whole
			while frc.hasSuffix("0") {
				frc.removeLast()
			}
			return frc
		}

		let int = String(whole.dropLast(Self.decimalPlaces))
		var frc = String(whole.suffix(Self.decimalPlaces))

		var gapPoint = int.count % groupingSize
		if groupingSize >= int.count { gapPoint = int.count + 2 }
		else if gapPoint == 0 { gapPoint = groupingSize }

		var index = 1
		var string = signstr

		for chr in int {
			if index > gapPoint {
				string.append("\(groupingSep)\(chr)")
				gapPoint += groupingSize - 1
				continue
			}

			string.append(chr)
			index += 1
		}

		frc.dropLastZeros()

		if frc.isEmpty { return string }
		return string + decimalSep + frc
	}

}

extension FDec: SignedNumeric {

	// MARK: Questions

	public var magnitude: FDec {
		var mag = self
		mag.value = Int(value.magnitude)
		return mag
	}

	public mutating func negate() { value *= -1 }

	public static var isSigned: Bool { true }

	public var sign: String { (value < 0) ? "-" : "" }

	public var signFull: String { (value < 0) ? "-" : "+" }

	// MARK: (+) Addition

	public static func + (lhs: FDec, rhs: FDec) -> FDec {
		let (value, over) = lhs.value.addingReportingOverflow(rhs.value)

		guard !over else { return .infinity }

		return FDec(raw: value)
	}

	public static func + (lhs: FDec, rhs: Int32) -> FDec { lhs + FDec(rhs) }
	public static func + (lhs: Int32, rhs: FDec) -> FDec { FDec(lhs) + rhs }
	public static func += (lhs: inout FDec, rhs: FDec) { lhs = lhs + rhs }
	public static func += (lhs: inout FDec, rhs: Int32) { lhs = lhs + FDec(rhs) }

	// MARK: (-) Subtraction

	public static func - (lhs: FDec, rhs: FDec) -> FDec { lhs + -rhs }

	public static func - (lhs: FDec, rhs: Int32) -> FDec { lhs + FDec(-rhs) }
	public static func - (lhs: Int32, rhs: FDec) -> FDec { FDec(lhs) + -rhs }
	public static func -= (lhs: inout FDec, rhs: FDec) { lhs = lhs + -rhs }
	public static func -= (lhs: inout FDec, rhs: Int32) { lhs = lhs + FDec(-rhs) }

	// MARK: (*) Multiplication

	public static func * (lhs: FDec, rhs: FDec) -> FDec {
		let (high, low) = mulSplit(lhs.value, rhs.value)
		let (top, over) = high.multipliedReportingOverflow(by: Self.high)

		guard !over else { return .infinity }

		return FDec(raw: top + (low / Self.pow))
	}

	public static func *= (lhs: inout FDec, rhs: FDec) { lhs = lhs * rhs }
	public static func *= (lhs: inout FDec, rhs: Int32) { lhs = lhs * FDec(rhs) }

	// MARK: (/) Divison

	public static func / (lhs: FDec, rhs: FDec) -> FDec {
		guard !rhs.isZero else { return .nan }

		let (raw, over) = lhs.value.multipliedReportingOverflow(by: Self.pow)

		guard !over else { return .infinity }

		return FDec(raw: raw / (rhs.value))
	}

	public static func /= (lhs: inout FDec, rhs: FDec) { lhs = lhs / rhs }
	public static func /= (lhs: inout FDec, rhs: Int32) { lhs = lhs / FDec(rhs) }

	// MARK: (%) Modulus

	public static func % (lhs: FDec, rhs: FDec) -> FDec {
		let (raw, over) = lhs.value.multipliedReportingOverflow(by: Self.pow)

		guard !over else { return .infinity }

		return FDec(raw: raw % (rhs.value))
	}

	// MARK: Internal functions

	public func quotientAndRemainder(dividingBy rhs: FDec) -> (quotient: FDec, remainder: FDec) {
		let (quotient, remainder) = value.quotientAndRemainder(dividingBy: rhs.value)

		return (FDec(raw: quotient), FDec(raw: remainder))
	}

	// MARK: Static functions

	static func mulSplit(_ lhs: Int, _ rhs: Int) -> (high: Int, low: Int) {
		let (lLo, lHi) = (lhs % Self.half, lhs / Self.half)
		let (rLo, rHi) = (rhs % Self.half, rhs / Self.half)

		let K = (lHi * rLo) + (rHi * lLo)

		var resHi = (lHi * rHi) + (K / Self.half)
		var resLo = (lLo * rLo) + ((K % Self.half) * Self.half)

		if resLo >= Self.full {
			resLo -= Self.full
			resHi += 1
		}

		return (resHi, resLo)
	}

	public static func random(_ rangeInt: ClosedRange<Int>, _ rangeFraction: ClosedRange<Int>? = nil, decimals: Int = Self.decimalPlaces) -> FDec? {
		let rnd = Int.random(in: rangeInt)
		let (int, overInt) = rnd.multipliedReportingOverflow(by: decimals.pow10())
		if overInt { return nil }

		let dec = rangeFraction == nil ? 0 : Int.random(in: rangeFraction!)
		let raw = int + dec

		return FDec(raw: raw)
	}

}

extension FDec: Strideable {

	public typealias Stride = FDec

	public func distance(to other: FDec) -> FDec {
		other - self
	}

	public func advanced(by n: FDec) -> FDec {
		self + n
	}

}

extension FDec: Hashable, Comparable {

	// MARK: Compare

	public static func == (lhs: FDec, rhs: FDec) -> Bool { lhs.value == rhs.value }

	public static func < (lhs: FDec, rhs: FDec) -> Bool { lhs.value < rhs.value }

	public static func > (lhs: FDec, rhs: FDec) -> Bool { !(lhs < rhs) }

	public static func != (lhs: FDec, rhs: FDec) -> Bool { !(lhs == rhs) }

	// MARK: Hashable

	public func hash(into hasher: inout Hasher) {
		hasher.combine(value)
	}

}

extension FDec: Codable {

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(value)
	}

	/// For correct decoding of the private pow variable,
	/// check the static value of the FDec structure: 'decimalPlaces'
	///
	public init(from decoder: Decoder) throws {
		let value = try decoder.singleValueContainer()
		self.value = try value.decode(Int.self)
	}

}

public extension FDec {
	func sqrt() -> FDec {
#if canImport(Darwin)
		let root = Darwin.sqrt(asDouble)
#endif
#if canImport(SwiftGlibc)
		let root = SwiftGlibc.sqrt(asDouble)
#endif
		return FDec(truncating: root)
	}
}

public func sqrt(_ value: FDec) -> FDec { value.sqrt() }

private extension Int {
	func pow10() -> Int {
		switch self {
			case 0: return 1
			case 1: return 10
			case 2: return 100
			case 3: return 1000
			case 4: return 10000
			case 5: return 100_000
			case 6: return 1_000_000
			case 7: return 10_000_000
			case 8: return 100_000_000
			case 9: return 1_000_000_000
			case 10: return 10_000_000_000
			case 11: return 100_000_000_000
			case 12: return 1_000_000_000_000
			case 13: return 10_000_000_000_000
			case 14: return 100_000_000_000_000
			case 15: return 1_000_000_000_000_000
			case 16: return 10_000_000_000_000_000
			case 17: return 100_000_000_000_000_000
			case 18: return 1_000_000_000_000_000_000
			default: fatalError()
		}
	}
}

private extension String {
	mutating func dropLastZeros() {
		while hasSuffix("0") {
			removeLast()
		}
	}
}
