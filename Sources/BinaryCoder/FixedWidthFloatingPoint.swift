// SPDX-License-Identifier: BSL-1.0

// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

public protocol FixedWidthFloatingPoint {
    associatedtype BitPattern: FixedWidthInteger
    init(bitPattern: BitPattern)
    var bitPattern: BitPattern { get }
}

@available(macOS 11.0, *)
extension Float16: FixedWidthFloatingPoint {
    public typealias BitPattern = UInt16
}

extension Float32: FixedWidthFloatingPoint {
    public typealias BitPattern = UInt32
}

extension Float64: FixedWidthFloatingPoint {
    public typealias BitPattern = UInt64
}

// Float80 is peculiar to x87 and not used very often.
