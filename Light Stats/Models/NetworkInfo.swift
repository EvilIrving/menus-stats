//
//  NetworkInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

final class NetworkInfo: @unchecked Sendable {

    private var previousBytes: (sent: UInt64, received: UInt64) = (0, 0)
    private var previousTime: Date = Date()

    struct Stats {
        let uploadSpeed: Double
        let downloadSpeed: Double
    }

    func getNetworkStats() -> Stats {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return Stats(uploadSpeed: 0, downloadSpeed: 0)
        }

        defer { freeifaddrs(ifaddr) }

        var totalSent: UInt64 = 0
        var totalReceived: UInt64 = 0

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback {
                if ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                    if let data = ptr.pointee.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        totalSent += UInt64(networkData.ifi_obytes)
                        totalReceived += UInt64(networkData.ifi_ibytes)
                    }
                }
            }

            
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(previousTime)

        var uploadSpeed: Double = 0
        var downloadSpeed: Double = 0

        if elapsed > 0 && previousBytes.sent > 0 {
            if totalSent >= previousBytes.sent && totalReceived >= previousBytes.received {
                uploadSpeed = Double(totalSent - previousBytes.sent) / elapsed
                downloadSpeed = Double(totalReceived - previousBytes.received) / elapsed
            }
        }

        previousBytes = (totalSent, totalReceived)
        previousTime = now

        return Stats(uploadSpeed: max(0, uploadSpeed), downloadSpeed: max(0, downloadSpeed))
    }
}
