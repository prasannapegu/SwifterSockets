// =====================================================================================================================
//
//  File:       SwifterSockets.swift
//  Project:    SwifterSockets
//
//  Version:    0.9.5
//
//  Author:     Marinus van der Lugt
//  Company:    http://balancingrock.nl
//  Website:    http://swiftfire.nl/pages/projects/swiftersockets/
//  Blog:       http://swiftrien.blogspot.com
//  Git:        https://github.com/Swiftrien/SwifterSockets
//
//  Copyright:  (c) 2014-2016 Marinus van der Lugt, All rights reserved.
//
//  License:    Use or redistribute this code any way you like with the following two provision:
//
//  1) You ACCEPT this source code AS IS without any guarantees that it will work as intended. Any liability from its
//  use is YOURS.
//
//  2) You WILL NOT seek damages from the author or balancingrock.nl.
//
//  I also ask you to please leave this header with the source code.
//
//  I strongly believe that the Non Agression Principle is the way for societies to function optimally. I thus reject
//  the implicit use of force to extract payment. Since I cannot negotiate with you about the price of this code, I
//  have choosen to leave it up to you to determine its price. You pay me whatever you think this code is worth to you.
//
//   - You can send payment via paypal to: sales@balancingrock.nl
//   - Or wire bitcoins to: 1GacSREBxPy1yskLMc9de2nofNv2SNdwqH
//
//  I prefer the above two, but if these options don't suit you, you might also send me a gift from my amazon.co.uk
//  whishlist: http://www.amazon.co.uk/gp/registry/wishlist/34GNMPZKAQ0OO/ref=cm_sw_em_r_wsl_cE3Tub013CKN6_wb
//
//  If you like to pay in another way, please contact me at rien@balancingrock.nl
//
//  (It is always a good idea to visit the website/blog/google to ensure that you actually pay me and not some imposter)
//
//  For private and non-profit use the suggested price is the price of 1 good cup of coffee, say $4.
//  For commercial use the suggested price is the price of 1 good meal, say $20.
//
//  You are however encouraged to pay more ;-)
//
//  Prices/Quotes for support, modifications or enhancements can be obtained from: rien@balancingrock.nl
//
// =====================================================================================================================
// PLEASE let me know about bugs, improvements and feature requests. (rien@balancingrock.nl)
// =====================================================================================================================
//
// History
//
// v0.9.5 - Added SocketAddress enum adopted from Marco Masser: http://blog.obdev.at/representing-socket-addresses-in-swift-using-enums
// v0.9.4 - Header update
// v0.9.3 - Changed target to Framework, added public declarations, removed SwifterLog.
// v0.9.2 - Added closeSocket
//        - Added 'logUnixSocketCalls'
//        - Upgraded to Swift 2.2
// v0.9.1 - Changed type of object in 'synchronized' from AnyObject to NSObject
//        - Added EXC_BAD_INSTRUCTION information to fd_set
// v0.9.0 - Initial release
// =====================================================================================================================


import Foundation


// Since the socket functions will often use multi-threading for maximum performance two synchronization functions are defined to ease safe communication between threads. If necessary move or rename these functions as necessary (i.e. if these names are already used in the project)

/**
 Ensures that the closure is only executed when no other thread has a lock on the given object.

 Usage example: let lock = NSString(); let i = synchronized(lock, { () -> Int? in ... })

 - Parameter object: The object to be used as the locking-object.
 - Parameter closure: The closure to be executed when the locking object is not locked.

 - Returns: The result from the closure.

 - Note: Calling this function from within the closure guarantees a deadlock.
 */

public func synchronized<R>(object: NSObject, _ closure: () -> R) -> R {
    objc_sync_enter(object)
    let r = closure()
    objc_sync_exit(object)
    return r
}


/**
 Ensures that the closure is only executed when no other thread has a lock on the given object.
 
 Usage example: let lock = NSString(); synchronized(lock, { ... })

 - Parameter object: The object to be used as the locking-object.
 - Parameter closure: The closure to be executed when the locking object is not locked.
 
 - Note: Calling this function from within the closure guarantees a deadlock.
 */

public func synchronized(object: NSObject, _ closure: () -> Void) {
    objc_sync_enter(object)
    closure()
    objc_sync_exit(object)
}


public final class SwifterSockets {

    
    /**
     A Swift wrapper and extensions for sockaddr.
     This wrapper was described on the blog from Marco Masser: http://blog.obdev.at/representing-socket-addresses-in-swift-using-enums/
     */
    
    public enum SocketAddress {
        case Version4(address: sockaddr_in)
        case Version6(address: sockaddr_in6)
        
        public init(addrInfo: addrinfo) {
            switch addrInfo.ai_family {
            case AF_INET:  self = .Version4(address: UnsafePointer(addrInfo.ai_addr).memory)
            case AF_INET6: self = .Version6(address: UnsafePointer(addrInfo.ai_addr).memory)
            default: fatalError("Unknown address family")
            }
        }
        
        public init?(@noescape addressProvider: (UnsafeMutablePointer<sockaddr>, UnsafeMutablePointer<socklen_t>) throws -> Void) rethrows {
            
            var addressStorage = sockaddr_storage()
            var addressStorageLength = socklen_t(sizeofValue(addressStorage))
            
            try withUnsafeMutablePointers(&addressStorage, &addressStorageLength) {
                try addressProvider(UnsafeMutablePointer<sockaddr>($0), $1)
            }
            
            switch Int32(addressStorage.ss_family) {
            case AF_INET:
                self = withUnsafePointer(&addressStorage) { .Version4(address: UnsafePointer<sockaddr_in>($0).memory) }
                
            case AF_INET6:
                self = withUnsafePointer(&addressStorage) { .Version6(address: UnsafePointer<sockaddr_in6>($0).memory) }
                
            default:
                return nil
            }
        }
        
        public func doWithPtr<Result>(@noescape body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result) rethrows -> Result {
            
            func castAndCall<T>(address: T, @noescape _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result) rethrows -> Result {
                var localAddress = address // We need a `var` here for the `&`.
                return try withUnsafePointer(&localAddress) {
                    try body(UnsafePointer<sockaddr>($0), socklen_t(sizeof(T)))
                }
            }
            
            switch self {
            case .Version4(let address): return try castAndCall(address, body)
            case .Version6(let address): return try castAndCall(address, body)
            }
        }
    }

    
    /**
     Returns the (ipAddress, portNumber) tuple for a given sockaddr (if possible)
    
     - Parameter addr: A pointer to a sockaddr structure.
     
     - Returns: (nil, nil) on failure, (ipAddress, portNumber) on success.
     */
    
    public static func sockaddrDescription(addr: UnsafePointer<sockaddr>) -> (ipAddress: String?, portNumber: String?) {
        
        var host : String?
        var service : String?
        
        var hostBuffer = [CChar](count: Int(NI_MAXHOST), repeatedValue: 0)
        var serviceBuffer = [CChar](count: Int(NI_MAXSERV), repeatedValue: 0)
        
        if getnameinfo(
            addr,
            socklen_t(addr.memory.sa_len),
            &hostBuffer,
            socklen_t(hostBuffer.count),
            &serviceBuffer,
            socklen_t(serviceBuffer.count),
            NI_NUMERICHOST | NI_NUMERICSERV)
            
            == 0 {
                
                host = String.fromCString(hostBuffer)
                service = String.fromCString(serviceBuffer)
        }
        return (host, service)
    }
    
    
    /**
     Replacement for FD_ZERO macro.
     
     - Parameter set: A pointer to a fd_set structure.
     
     - Returns: The set that is opinted at is filled with all zero's.
     */
    
    public static func fdZero(inout set: fd_set) {
        set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
    
    
    /**
     Replacement for FD_SET macro
     
     - Parameter fd: A file descriptor that offsets the bit to be set to 1 in the fd_set pointed at by 'set'.
     - Parameter set: A pointer to a fd_set structure.
     
     - Returns: The given set is updated in place, with the bit at offset 'fd' set to 1.
     
     - Note: If you receive an EXC_BAD_INSTRUCTION at the mask statement, then most likely the socket was already closed.
     */
    
    public static func fdSet(fd: Int32, inout set: fd_set) {
        let intOffset = Int(fd / 32)
        let bitOffset = fd % 32
        let mask = 1 << bitOffset
        switch intOffset {
        case 0: set.fds_bits.0 = set.fds_bits.0 | mask
        case 1: set.fds_bits.1 = set.fds_bits.1 | mask
        case 2: set.fds_bits.2 = set.fds_bits.2 | mask
        case 3: set.fds_bits.3 = set.fds_bits.3 | mask
        case 4: set.fds_bits.4 = set.fds_bits.4 | mask
        case 5: set.fds_bits.5 = set.fds_bits.5 | mask
        case 6: set.fds_bits.6 = set.fds_bits.6 | mask
        case 7: set.fds_bits.7 = set.fds_bits.7 | mask
        case 8: set.fds_bits.8 = set.fds_bits.8 | mask
        case 9: set.fds_bits.9 = set.fds_bits.9 | mask
        case 10: set.fds_bits.10 = set.fds_bits.10 | mask
        case 11: set.fds_bits.11 = set.fds_bits.11 | mask
        case 12: set.fds_bits.12 = set.fds_bits.12 | mask
        case 13: set.fds_bits.13 = set.fds_bits.13 | mask
        case 14: set.fds_bits.14 = set.fds_bits.14 | mask
        case 15: set.fds_bits.15 = set.fds_bits.15 | mask
        case 16: set.fds_bits.16 = set.fds_bits.16 | mask
        case 17: set.fds_bits.17 = set.fds_bits.17 | mask
        case 18: set.fds_bits.18 = set.fds_bits.18 | mask
        case 19: set.fds_bits.19 = set.fds_bits.19 | mask
        case 20: set.fds_bits.20 = set.fds_bits.20 | mask
        case 21: set.fds_bits.21 = set.fds_bits.21 | mask
        case 22: set.fds_bits.22 = set.fds_bits.22 | mask
        case 23: set.fds_bits.23 = set.fds_bits.23 | mask
        case 24: set.fds_bits.24 = set.fds_bits.24 | mask
        case 25: set.fds_bits.25 = set.fds_bits.25 | mask
        case 26: set.fds_bits.26 = set.fds_bits.26 | mask
        case 27: set.fds_bits.27 = set.fds_bits.27 | mask
        case 28: set.fds_bits.28 = set.fds_bits.28 | mask
        case 29: set.fds_bits.29 = set.fds_bits.29 | mask
        case 30: set.fds_bits.30 = set.fds_bits.30 | mask
        case 31: set.fds_bits.31 = set.fds_bits.31 | mask
        default: break
        }
    }
    
    
    /**
     Replacement for FD_CLR macro
    
     - Parameter fd: A file descriptor that offsets the bit to be cleared in the fd_set pointed at by 'set'.
     - Parameter set: A pointer to a fd_set structure.
    
     - Returns: The given set is updated in place, with the bit at offset 'fd' cleared to 0.
     */

    public static func fdClr(fd: Int32, inout set: fd_set) {
        let intOffset = Int(fd / 32)
        let bitOffset = fd % 32
        let mask = ~(1 << bitOffset)
        switch intOffset {
        case 0: set.fds_bits.0 = set.fds_bits.0 & mask
        case 1: set.fds_bits.1 = set.fds_bits.1 & mask
        case 2: set.fds_bits.2 = set.fds_bits.2 & mask
        case 3: set.fds_bits.3 = set.fds_bits.3 & mask
        case 4: set.fds_bits.4 = set.fds_bits.4 & mask
        case 5: set.fds_bits.5 = set.fds_bits.5 & mask
        case 6: set.fds_bits.6 = set.fds_bits.6 & mask
        case 7: set.fds_bits.7 = set.fds_bits.7 & mask
        case 8: set.fds_bits.8 = set.fds_bits.8 & mask
        case 9: set.fds_bits.9 = set.fds_bits.9 & mask
        case 10: set.fds_bits.10 = set.fds_bits.10 & mask
        case 11: set.fds_bits.11 = set.fds_bits.11 & mask
        case 12: set.fds_bits.12 = set.fds_bits.12 & mask
        case 13: set.fds_bits.13 = set.fds_bits.13 & mask
        case 14: set.fds_bits.14 = set.fds_bits.14 & mask
        case 15: set.fds_bits.15 = set.fds_bits.15 & mask
        case 16: set.fds_bits.16 = set.fds_bits.16 & mask
        case 17: set.fds_bits.17 = set.fds_bits.17 & mask
        case 18: set.fds_bits.18 = set.fds_bits.18 & mask
        case 19: set.fds_bits.19 = set.fds_bits.19 & mask
        case 20: set.fds_bits.20 = set.fds_bits.20 & mask
        case 21: set.fds_bits.21 = set.fds_bits.21 & mask
        case 22: set.fds_bits.22 = set.fds_bits.22 & mask
        case 23: set.fds_bits.23 = set.fds_bits.23 & mask
        case 24: set.fds_bits.24 = set.fds_bits.24 & mask
        case 25: set.fds_bits.25 = set.fds_bits.25 & mask
        case 26: set.fds_bits.26 = set.fds_bits.26 & mask
        case 27: set.fds_bits.27 = set.fds_bits.27 & mask
        case 28: set.fds_bits.28 = set.fds_bits.28 & mask
        case 29: set.fds_bits.29 = set.fds_bits.29 & mask
        case 30: set.fds_bits.30 = set.fds_bits.30 & mask
        case 31: set.fds_bits.31 = set.fds_bits.31 & mask
        default: break
        }
    }
    
    
    /**
    Replacement for FD_ISSET macro
    
     - Parameter fd: A file descriptor that offsets the bit to be tested in the fd_set pointed at by 'set'.
     - Parameter set: A pointer to a fd_set structure.
    
     - Returns: 'true' if the bit at offset 'fd' is 1, 'false' otherwise.
     */

    public static func fdIsSet(fd: Int32, inout set: fd_set) -> Bool {
        let intOffset = Int(fd / 32)
        let bitOffset = fd % 32
        let mask = 1 << bitOffset
        switch intOffset {
        case 0: return set.fds_bits.0 & mask != 0
        case 1: return set.fds_bits.1 & mask != 0
        case 2: return set.fds_bits.2 & mask != 0
        case 3: return set.fds_bits.3 & mask != 0
        case 4: return set.fds_bits.4 & mask != 0
        case 5: return set.fds_bits.5 & mask != 0
        case 6: return set.fds_bits.6 & mask != 0
        case 7: return set.fds_bits.7 & mask != 0
        case 8: return set.fds_bits.8 & mask != 0
        case 9: return set.fds_bits.9 & mask != 0
        case 10: return set.fds_bits.10 & mask != 0
        case 11: return set.fds_bits.11 & mask != 0
        case 12: return set.fds_bits.12 & mask != 0
        case 13: return set.fds_bits.13 & mask != 0
        case 14: return set.fds_bits.14 & mask != 0
        case 15: return set.fds_bits.15 & mask != 0
        case 16: return set.fds_bits.16 & mask != 0
        case 17: return set.fds_bits.17 & mask != 0
        case 18: return set.fds_bits.18 & mask != 0
        case 19: return set.fds_bits.19 & mask != 0
        case 20: return set.fds_bits.20 & mask != 0
        case 21: return set.fds_bits.21 & mask != 0
        case 22: return set.fds_bits.22 & mask != 0
        case 23: return set.fds_bits.23 & mask != 0
        case 24: return set.fds_bits.24 & mask != 0
        case 25: return set.fds_bits.25 & mask != 0
        case 26: return set.fds_bits.26 & mask != 0
        case 27: return set.fds_bits.27 & mask != 0
        case 28: return set.fds_bits.28 & mask != 0
        case 29: return set.fds_bits.29 & mask != 0
        case 30: return set.fds_bits.30 & mask != 0
        case 31: return set.fds_bits.31 & mask != 0
        default: return false
        }
    }
    
    
    /**
     Returns all IP addresses in the addrinfo structure as a String.
     
     - Parameter infoPtr: A pointer to an addrinfo structure of which the IP addresses should be logged.
     - Parameter source: The source to be logged for the log entry, defaults to "SwifterSockets.logAddrInfoIPAddresses".
     
     - Returns: A string with the IP Addresses of all entries in the infoPtr addrinfo structure chain.
     */
    
    public static func logAddrInfoIPAddresses(infoPtr: UnsafeMutablePointer<addrinfo>) -> String
    {
        var count = 0
        var info = infoPtr
        var str = ""
        while info != nil {
            let (clientIp, service) = sockaddrDescription(info.memory.ai_addr)
            str += "No: \(count), HostIp: " + (clientIp ?? "?") + " at port: " + (service ?? "?") + "\n"
            count += 1
            info = info.memory.ai_next
        }
        
        return str
    }
    
    
    /**
     A string with all socket options.
     
     - Parameter socket: The socket of which to log the options.
     - Parameter atLogLevel: The logleven at which the options will be logged.
     
     - Returns: A string with all socket options of the given socket.
     */
    
    public static func logSocketOptions(socket: Int32) -> String {
        
        
        // To identify the logging source
        
        var res = ""
        
        
        // Assist functions do the actual logging
        
        func forFlagOptionAtLevel(level: Int32, withName name: Int32, str: String) {
            var optionValueFlag: Int32 = 0
            var ovFlagLength: socklen_t = 4
            _ = getsockopt(socket, level, name, &optionValueFlag, &ovFlagLength)
            res += "\(str) = " + (optionValueFlag == 0 ? "No" : "Yes")
        }
        
        func forIntOptionAtLevel(level: Int32, withName name: Int32, str: String) {
            var optionValueInt: Int32 = 0
            var ovIntLength: socklen_t = 4
            _ = getsockopt(socket, level, name, &optionValueInt, &ovIntLength)
            res += "\(str) = \(optionValueInt)"
        }
        
        func forLingerOptionAtLevel(level: Int32, withName name: Int32, str: String) {
            var optionValueLinger = linger(l_onoff: 0, l_linger: 0)
            var ovLingerLength: socklen_t = 8
            _ = getsockopt(socket, level, name, &optionValueLinger, &ovLingerLength)
            res += "\(str) onOff = \(optionValueLinger.l_onoff), linger = \(optionValueLinger.l_linger)"
        }
        
        func forTimeOptionAtLevel(level: Int32, withName name: Int32, str: String) {
            var optionValueTime = time_value(seconds: 0, microseconds: 0)
            var ovTimeLength: socklen_t = 8
            _ = getsockopt(socket, level, name, &optionValueTime, &ovTimeLength)
            res += "\(str) seconds = \(optionValueTime.seconds), microseconds = \(optionValueTime.microseconds)"
        }
        
        
        // Call the assist functions for the available options
        
        forFlagOptionAtLevel(SOL_SOCKET, withName: SO_BROADCAST, str: "SO_BROADCAST")
        forFlagOptionAtLevel(SOL_SOCKET, withName: SO_DEBUG, str: "SO_DEBUG")
        forFlagOptionAtLevel(SOL_SOCKET, withName: SO_DONTROUTE, str: "SO_DONTROUTE")
        forIntOptionAtLevel(SOL_SOCKET, withName: SO_ERROR, str: "SO_ERROR")
        forFlagOptionAtLevel(SOL_SOCKET, withName: SO_KEEPALIVE, str: "SO_KEEPALIVE")
        forLingerOptionAtLevel(SOL_SOCKET, withName: SO_LINGER, str: "SO_LINGER")
        forFlagOptionAtLevel(SOL_SOCKET, withName: SO_OOBINLINE, str: "SO_OOBINLINE")
        forIntOptionAtLevel(SOL_SOCKET, withName: SO_RCVBUF, str: "SO_RCVBUF")
        forIntOptionAtLevel(SOL_SOCKET, withName: SO_SNDBUF, str: "SO_SNDBUF")
        forIntOptionAtLevel(SOL_SOCKET, withName: SO_RCVLOWAT, str: "SO_RCVLOWAT")
        forIntOptionAtLevel(SOL_SOCKET, withName: SO_SNDLOWAT, str: "SO_SNDLOWAT")
        forTimeOptionAtLevel(SOL_SOCKET, withName: SO_RCVTIMEO, str: "SO_RCVTIMEO")
        forTimeOptionAtLevel(SOL_SOCKET, withName: SO_SNDTIMEO, str: "SO_SNDTIMEO")
        forFlagOptionAtLevel(SOL_SOCKET, withName: SO_REUSEADDR, str: "SO_REUSEADDR")
        forFlagOptionAtLevel(SOL_SOCKET, withName: SO_REUSEPORT, str: "SO_REUSEPORT")
        forIntOptionAtLevel(SOL_SOCKET, withName: SO_TYPE, str: "SO_TYPE")
        forFlagOptionAtLevel(SOL_SOCKET, withName: SO_USELOOPBACK, str: "SO_USELOOPBACK")
        forIntOptionAtLevel(IPPROTO_IP, withName: IP_TOS, str: "IP_TOS")
        forIntOptionAtLevel(IPPROTO_IP, withName: IP_TTL, str: "IP_TTL")
        forIntOptionAtLevel(IPPROTO_IPV6, withName: IPV6_UNICAST_HOPS, str: "IPV6_UNICAST_HOPS")
        forFlagOptionAtLevel(IPPROTO_IPV6, withName: IPV6_V6ONLY, str: "IPV6_V6ONLY")
        forIntOptionAtLevel(IPPROTO_TCP, withName: TCP_MAXSEG, str: "TCP_MAXSEG")
        forFlagOptionAtLevel(IPPROTO_TCP, withName: TCP_NODELAY, str: "TCP_NODELAY")
        
        return res
    }
    
    
    /**
     Closes the given socket if not nil. This entry point is supplied to have a single point that closes all your sockets. Durng debugging it is often good to have some logging facility that logs all calls on the unix sockets. This function allows to have a single point for that logging without having to look through your code to find all occurances of the close call.
     
     - Returns: True if the port was closed, nil if it was closed already and false if an error occured (errno will contain an error reason).
     */
    
    public static func closeSocket(socket: Int32?) -> Bool? {
        
        guard let s = socket else { return nil }
        
        return close(s) == 0
    }
}