// SPDX-License-Identifier: BSL-1.0

// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

// =========================================================
// Alternative: https://github.com/apple/swift-binary-parsing
// =========================================================

// =========================================================
// Alternative: https://github.com/apple/swift-protobuf
// =========================================================

import Foundation

// FIXME poor debuggability

// MARK: - Encoder

public enum BinaryEncodingError: Error {
    case invalidValue
    case insufficientSpace
    case streamError(Error?)
    case unexpectedStreamBehavior
}

public protocol BinaryEncodable {
    func encode(to encoder: BinaryEncoder) throws
}

public class BinaryEncoder {
    public private(set) var byteOrder: ByteOrder
    public private(set) var outputStream: OutputStream

    // `outputStream` must be opened before use, and be closed after use.
    // `BinaryEncoder` neither opens nor closes it.
    public init (byteOrder: ByteOrder, outputStream: OutputStream) {
        self.byteOrder = byteOrder
        self.outputStream = outputStream
    }

    public func withTemporary<R, E>(byteOrder: ByteOrder, _ body: () throws(E) -> R) throws(E) -> R {
        let oldByteOrder = self.byteOrder
        defer {
            self.byteOrder = oldByteOrder
        }

        self.byteOrder = byteOrder
        return try body()
    }

    public func pushBack(
        _ bytes: UnsafeRawBufferPointer
    ) throws {
        guard !bytes.isEmpty else {
            return
        }

        let actualLength = outputStream.write(bytes.baseAddress!, maxLength: bytes.count)
        if actualLength == bytes.count {
            return
        }

        if actualLength < -1 {
            throw BinaryEncodingError.unexpectedStreamBehavior
        } else if actualLength == -1 {
            throw BinaryEncodingError.streamError(outputStream.streamError)
        } else if actualLength < bytes.count {
            throw BinaryEncodingError.insufficientSpace
        } else {
            throw BinaryEncodingError.unexpectedStreamBehavior
        }
    }

    @inlinable
    public func pushBack<C>(
        _ data: C
    ) throws where C: ContiguousBytes {
        try data.withUnsafeBytes { try pushBack($0) }
    }

    @inlinable
    public func pushBack(
        _ value: UInt8
    ) throws {
        try withUnsafeBytes(of: value) { try pushBack($0) }
    }

    @inlinable
    public func pushBack<T>(
        _ value: T
    ) throws where T: FixedWidthInteger {
        let rawValue = {
            switch self.byteOrder {
            case .littleEndian:
                return value.littleEndian
            case .bigEndian:
                return value.bigEndian
            }
        }()

        try withUnsafeBytes(of: rawValue) { try pushBack($0) }
    }

    @inlinable
    public func pushBack<T>(
        _ value: T
    ) throws where T: FixedWidthFloatingPoint {
        try pushBack(value.bitPattern)
    }
}

extension BinaryEncoder {
    private static func withTemporaryOutputStream(
        _ body: (OutputStream) throws -> Void
    ) throws -> Data {
        let outputStream = OutputStream.toMemory()

        _ = try {
            outputStream.open()
            defer { outputStream.close() }
            try body(outputStream)
        }()

        guard let data = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            throw BinaryEncodingError.unexpectedStreamBehavior
        }

        return data
    }

    public static func withMemoryBackedEncoder(
        byteOrder: ByteOrder,
        _ body: (BinaryEncoder) throws -> Void
    ) throws -> Data {
        return try withTemporaryOutputStream {
            let encoder = BinaryEncoder(byteOrder: byteOrder, outputStream: $0)
            try body(encoder)
        }
    }

    // Calls `body` and then calls `header`, and lastly, merges the child output to the parent output.
    // This method buffers the child output, so it's not suitable for very large data.
    public func section(
        header: (_ parent: BinaryEncoder, _ child: Data) throws -> Void,
        body: (_ child: BinaryEncoder) throws -> Void
    ) throws {
        let data = try Self.withMemoryBackedEncoder(byteOrder: byteOrder) {
            try body($0)
        }

        try header(self, data)
        try pushBack(data)
    }
}

// MARK: - Decoder

public enum BinaryDecodingError: Error {
    case noMoreData
    case insufficientData
    case dataCorrupted
    case streamError(Error?)
    case unexpectedStreamBehavior
}

public protocol BinaryDecodable {
    init (from decoder: BinaryDecoder) throws
}

public class BinaryDecoder {
    public private(set) var byteOrder: ByteOrder
    public private(set) var inputStream: InputStream
    public private(set) var maxLength: Int?

    // `inputStream` must be opened before use, and be closed after use.
    // `BinaryDecoder` neither opens nor closes it.
    public init (byteOrder: ByteOrder, inputStream: InputStream, maxLength: Int? = nil) {
        self.byteOrder = byteOrder
        self.inputStream = inputStream
        self.maxLength = maxLength
    }

    public func withTemporary<R, E>(byteOrder: ByteOrder, _ body: () throws(E) -> R) throws(E) -> R {
        let oldByteOrder = self.byteOrder
        defer {
            self.byteOrder = oldByteOrder
        }

        self.byteOrder = byteOrder
        return try body()
    }

    public func popFront(
        into bytes: UnsafeMutableRawBufferPointer
    ) throws {
        guard !bytes.isEmpty else {
            return
        }

        let requestedLength = min(bytes.count, maxLength ?? Int.max)
        let actualLength = inputStream.read(bytes.baseAddress!, maxLength: requestedLength)
        if 0 < actualLength && actualLength <= requestedLength {
            if let maxLength {
                self.maxLength = maxLength - actualLength
            }
        }

        if actualLength < -1 || requestedLength < actualLength {
            throw BinaryDecodingError.unexpectedStreamBehavior
        } else if actualLength == -1 {
            throw BinaryDecodingError.streamError(inputStream.streamError)
        } else if actualLength == 0 {
            throw BinaryDecodingError.noMoreData
        } else if actualLength < requestedLength {
            throw BinaryDecodingError.insufficientData
        }
    }

    @inlinable
    public func popFront(
        count: Int
    ) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { try popFront(into: .init($0)) }
        return data
    }

    @inlinable
    public func popFront(
    ) throws -> UInt8 {
        return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 1) {
            try popFront(into: .init($0))
            return $0[0]
        }
    }

    @inlinable
    public func popFront<T>(
    ) throws -> T where T: FixedWidthInteger {
        let rawValue = try withUnsafeTemporaryAllocation(of: T.self, capacity: 1) {
            try popFront(into: .init($0))
            return $0[0]
        }

        switch byteOrder {
        case .littleEndian:
            return T(littleEndian: rawValue)
        case .bigEndian:
            return T(bigEndian: rawValue)
        }
    }

    @inlinable
    public func popFront<T>(
    ) throws -> T where T: FixedWidthFloatingPoint {
        let rawValue: T.BitPattern = try self.popFront()
        return T(bitPattern: rawValue)
    }
}

extension BinaryDecoder {
    @inlinable
    public func popFront<T>(
        count: Int,
        as: T.Type,
        _ body: (Int, T) throws -> Void
    ) throws where T: BinaryDecodable {
        for i in 0..<count {
            try body(i, try .init(from: self))
        }
    }

    @inlinable
    public func popFront<T>(
        count: Int,
    ) throws -> [T] where T: BinaryDecodable {
        return try [T](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            try popFront(count: count, as: T.self) { index, value in
                buffer[index] = value
                initializedCount += 1
            }
        }
    }
}

extension BinaryDecoder {
    private static func withMemoryBackedInputStream<R, E>(
        data: Data,
        _ body: (InputStream) throws(E) -> R
    ) throws(E) -> R {
        let inputStream = InputStream(data: data)

        inputStream.open()
        defer { inputStream.close() }

        return try body(inputStream)
    }

    public static func withMemoryBackedDecoder<R, E>(
        byteOrder: ByteOrder,
        data: Data,
        _ body: (BinaryDecoder) throws(E) -> R
    ) throws(E) -> R {
        return try withMemoryBackedInputStream(data: data) { (inputStream) throws(E) -> R in
            let decoder = BinaryDecoder(byteOrder: byteOrder, inputStream: inputStream)
            return try body(decoder)
        }
    }
}

extension BinaryDecoder {
    public func discard(count: Int) throws {
        let _ = try popFront(count: count) // XXX
    }

    // If `maxLength` is not `nil`, bytes which `body` didn't consume are considered leftovers.
    // This method discards leftover bytes after calling `body` if `ignoreLeftover` is `false`.
    public func withSubDecoder(
        count: Int,
        ignoreLeftover: Bool,
        _ body: (BinaryDecoder) throws -> Void
    ) throws {
        if let maxLength {
            guard count <= maxLength else {
                throw BinaryDecodingError.insufficientData
            }
            self.maxLength = maxLength - count
        }

        let subDecoder = BinaryDecoder(byteOrder: self.byteOrder, inputStream: inputStream, maxLength: count)
        try body(subDecoder)

        if !ignoreLeftover {
            try subDecoder.discard(count: subDecoder.maxLength ?? 0)
        }
    }

    public func section(
        ignoreLeftover: Bool,
        header: (BinaryDecoder) throws -> Int?,
        body: (BinaryDecoder) throws -> Void
    ) throws -> Void {
        guard let count = try header(self) else {
            return
        }

        try withSubDecoder(count: count, ignoreLeftover: ignoreLeftover) {
            try body($0)
        }
    }

    public func section<Context>(
        ignoreLeftover: Bool,
        header: (BinaryDecoder) throws -> (Int, Context)?,
        body: (BinaryDecoder, Context) throws -> Void
    ) throws -> Void {
        let h = try header(self)
        guard let (count, context) = h else {
            return
        }

        try withSubDecoder(count: count, ignoreLeftover: ignoreLeftover) {
            try body($0, context)
        }
    }
}

// MARK: - Extensions

public protocol BinaryCodable: BinaryEncodable, BinaryDecodable {}

public extension FixedWidthInteger {
    @inlinable
    func encode(to encoder: BinaryEncoder) throws {
        try encoder.pushBack(self)
    }

    @inlinable
    init (from decoder: BinaryDecoder) throws {
        self = try decoder.popFront()
    }
}

extension UInt8: BinaryCodable {}
extension UInt16: BinaryCodable {}
extension UInt32: BinaryCodable {}
extension UInt64: BinaryCodable {}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension UInt128: BinaryCodable {}

extension Int8: BinaryCodable {}
extension Int16: BinaryCodable {}
extension Int32: BinaryCodable {}
extension Int64: BinaryCodable {}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Int128: BinaryCodable {}

public extension FixedWidthFloatingPoint {
    @inlinable
    func encode(to encoder: BinaryEncoder) throws {
        try encoder.pushBack(self)
    }

    @inlinable
    init (from decoder: BinaryDecoder) throws {
        self = try decoder.popFront()
    }
}

@available(macOS 11.0, *)
extension Float16: BinaryCodable {}
extension Float32: BinaryCodable {}
extension Float64: BinaryCodable {}

//
// We can't automatically decode sequences because the length is not known.
//
public extension Data {
    @inlinable
    func encode(to encoder: BinaryEncoder) throws {
        try encoder.pushBack(self)
    }
}
public extension Sequence where Element: BinaryEncodable {
    @inlinable
    func encode(to encoder: BinaryEncoder) throws {
        for element in self {
            try element.encode(to: encoder)
        }
    }
}

extension Data: BinaryEncodable {}
extension Array: BinaryEncodable where Element: BinaryEncodable {}

extension UUID: BinaryCodable {
    @inlinable
    public func encode(to encoder: BinaryEncoder) throws {
        try withUnsafeBytes(of: self.uuid) {
            try encoder.pushBack($0)
        }
    }

    @inlinable
    public init(from decoder: BinaryDecoder) throws {
        let rawValue = try withUnsafeTemporaryAllocation(of: uuid_t.self, capacity: 1) {
            try decoder.popFront(into: .init($0))
            return $0[0]
        }

        self.init(uuid: rawValue)
    }
}
