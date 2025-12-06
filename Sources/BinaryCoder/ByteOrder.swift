// SPDX-License-Identifier: BSL-1.0

// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

import Foundation

public enum ByteOrder: RawRepresentable {
    case littleEndian
    case bigEndian
    // We won't support other exotic byte orders.

    public init?(rawValue: Int) {
        switch rawValue {
        case NS_LittleEndian: self = .littleEndian
        case NS_BigEndian: self = .bigEndian
        default: return nil
        }
    }

    public var rawValue: Int {
        switch self {
        case .littleEndian: return NS_LittleEndian
        case .bigEndian: return NS_BigEndian
        }
    }

    public static var host: ByteOrder {
        // NSHostByteOrder():
        // The endian format, either NS_LittleEndian or NS_BigEndian.
        return ByteOrder(rawValue: NSHostByteOrder())!
    }
}
