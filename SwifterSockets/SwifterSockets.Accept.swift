// =====================================================================================================================
//
//  File:       SwifterSockets.Accept.swift
//  Project:    SwifterSockets
//
//  Version:    0.9.7
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
// v0.9.7 - Upgraded to Xcode 8 beta 6
// v0.9.6 - Upgraded to Xcode 8 beta 3 (Swift 3)
// v0.9.5 - Fixed a bug where accepting an IPv6 connection would fill an IPv4 sockaddr structure.
// v0.9.4 - Header update
// v0.9.3 - Adding Carthage support: Changed target to Framework, added public declarations, removed SwifterLog.
// v0.9.2 - Added support for logUnixSocketCalls
//        - Moved closing of sockets to SwifterSockets.closeSocket
//        - Upgraded to Swift 2.2
//        - Added CLOSED as a possible result (this happens when a thread is accepting while another thread closes the
//        associated socket)
//        - Fixed a bug that missed the error return from the select call.
// v0.9.1 AcceptTelemetry now inherits from NSObject
// v0.9.0 Initial release
// =====================================================================================================================

import Foundation


public extension SwifterSockets {
    
    
    /**
     The result for the accept function accept. Possible values are:
     
     - accepted(socket: Int32)
     - error(message: String)
     - timeout
     - aborted
     - closed
     
     */
    
    public enum AcceptResult: CustomStringConvertible, CustomDebugStringConvertible {
        
        
        /// A connection was accepted, the socket descriptor is enclosed
        
        case accepted(socket: Int32)
        
        
        /// An error occured, the error message is enclosed.
        
        case error(message: String)
        
        
        /// A timeout occured.
        
        case timeout
        
        
        /// The wait for a connection request was aborted by writing 'true' to 'stopAccepting'.
        
        case aborted
        
        
        /// The socket the accept runs on is closed
        
        case closed
        
        
        /// The CustomStringConvertible protocol
        
        public var description: String {
            switch self {
            case .timeout: return "Timeout"
            case .aborted: return "Aborted"
            case .closed: return "Closed"
            case let .error(message: msg): return "Error(message: \(msg))"
            case let .accepted(socket: num): return "Accepted(socket: \(num))"
            }
        }
        
        
        /// The CustomDebugStringConvertible protocol
        
        public var debugDescription: String { return description }
    }
    
    
    /// This exception can be thrown by the _OrThrow functions. Notice that the ABORTED case is not an error per se but is always in response to an request to abort.
    
    public enum AcceptException: Error, CustomStringConvertible, CustomDebugStringConvertible {
        
        
        /// The string contains a textual description of the error
        
        case message(String)
        
        
        /// A timeout occured
        
        case timeout
        
        
        /// The accept was aborted throu the abort flag
        
        case aborted
        
        
        /// The socket the accept runs on is closed
        
        case closed

        
        /// The CustomStringConvertible protocol
        
        public var description: String {
            switch self {
            case .timeout: return "Timeout"
            case .aborted: return "Aborted"
            case .closed: return "Closed"
            case let .message(msg): return "Message(\(msg))"
            }
        }
        
        
        /// The CustomDebugStringConvertible protocol
        
        public var debugDescription: String { return description }
    }
    
    
    /// The telemetry that is available from the accept call. The values are read-only.
    
    public class AcceptTelemetry: CustomStringConvertible, CustomDebugStringConvertible {
        
        private var syncQueue = DispatchQueue(label: "Accept Telemetry Synchronization")

        
        /// The number of times the accept loop has been run so far, updated 'life'.
        
        public var loopCounter: Int = 0
        
        
        /// The number of accepted connection requests
        
        public var acceptedConnections: Int32 = 0
        
        
        /// The time the accept was started, set once at the start of the function call.
        
        public var startTime: Date? {
            get {
                return syncQueue.sync(execute: { return self._startTime })
            }
            set {
                syncQueue.sync(execute: { self._startTime = newValue })
            }
        }
        
        private var _startTime: Date?
        
        
        /// The time the timeout (if used) will terminate the accept call, set once at the start of the function call.
        
        public var timeoutTime: Date? {
            get {
                return syncQueue.sync(execute: { return self._timeoutTime })
            }
            set {
                syncQueue.sync(execute: { self._timeoutTime = newValue })
            }
        }
        
        private var _timeoutTime: Date?

        
        
        /// The time the accept function exited, set once at the exit of the call.
        
        public var endTime: Date? {
            get {
                return syncQueue.sync(execute: { return self._endTime })
            }
            set {
                syncQueue.sync(execute: { self._endTime = newValue })
            }
        }
        
        private var _endTime: Date?

        
        /// A copy of the result of the return parameter.
        
        public var result: AcceptResult? {
            get {
                return syncQueue.sync(execute: { return self._result })
            }
            set {
                syncQueue.sync(execute: { self._result = newValue })
            }
        }
        
        private var _result: AcceptResult?
        
        
        /// Remote IP address
        
        public var clientAddress: String? {
            get {
                return syncQueue.sync(execute: { return self._clientAddress })
            }
            set {
                syncQueue.sync(execute: { self._clientAddress = newValue })
            }
        }
        
        private var _clientAddress: String?
        
        
        /// Remote port number
        
        public var clientPort: String? {
            get {
                return syncQueue.sync(execute: { return self._clientPort })
            }
            set {
                syncQueue.sync(execute: { self._clientPort = newValue })
            }
        }
        
        private var _clientPort: String?
        
        
        /// The CustomStringConvertible protocol
        
        public var description: String {
            var str = ""
            str += "loopCounter = \(loopCounter)\n"
            str += "acceptedConnections = \(acceptedConnections)\n"
            str += "startTime = \(startTime)\n"
            str += "timeoutTime = \(timeoutTime)\n"
            str += "endTime = \(endTime)\n"
            str += "result = \(result)\n"
            str += "clientAddress = \(clientAddress)\n"
            str += "clientPort = \(clientPort)\n"
            return str
        }
        
        
        /// The CustomDebugStringConvertible protocol
        
        public var debugDescription: String { return description }
    }

    
    /**
     Waits for a connection request to arrive on the given socket descriptor. The function returns when a connection has been accepted, when an error occured, when a timeout occured or when the static variable 'abortFlag' is set to 'true'. This function does not close any socket. This function is the basis for all other SwifterSockets.acceptXXX calls.
     
     - Parameter onSocket: The socket descriptor on which accept will listen for connection requests. This socket descriptor should have been initialized with "InitServerSocket" previously.
     - Parameter abortFlag: The function will terminate as soon as possible (see polling interval) when this variable is set to 'true'. This variable must be set to 'false' before the call, otherwise the function will terminate immediately.
     - Parameter abortFlagPollInterval: In the default mode (i.e. timeout == nil) the function will poll the inout variable abortFlag to abort the accept procedure. The interval is the time between evaluations of the abortFlag. If the argument is nil, the timeout argument *must* be non-nil. When used, the argument must be > 0. Setting this argument to an extremely low value wil result in high CPU loads, recommended minimum value is at least 1 second.
     - Parameter timeout: The maximum duration this function will wait for a connection request to arrive. When nil the abortFlag controls how long the accept loop will run (see also pollInterval). PollInterval and timeout can be used simultaniously.
     - Parameter telemetry: This class can be used if the callee wishes to monitor the accept function. See class description for details. If argument errors are found, the telemetry will not be updated.

     - Returns: ACCEPTED with a socket descriptor, ERROR with an error message, TIMEOUT or ABORTED. When a socket descriptor is returned its SIGPIPE exception is disabled.
     */
    
    public static func acceptNoThrow(
        onSocket socket: Int32,
        abortFlag: inout Bool,
        abortFlagPollInterval: TimeInterval?,
        timeout: TimeInterval? = nil,
        telemetry: AcceptTelemetry? = nil)
        -> AcceptResult
    {
        // Protect against illegal argument values
        
        guard let _ = timeout ?? abortFlagPollInterval else {
            return .error(message: "At least one of timeout or abortFlagPollInterval must be specified")
        }
        
        if abortFlagPollInterval != nil {
            if abortFlagPollInterval! == 0.0 {
                return .error(message: "abortFlagPollInterval may not be 0")
            }
        }
        
        
        // Set a timeout if necessary
        
        let startTime = Date()
        telemetry?.startTime = startTime
        
        var timeoutTime: Date?
        if timeout != nil {
            timeoutTime = startTime.addingTimeInterval(timeout!)
            telemetry?.timeoutTime = timeoutTime
        }
        
        
        // =====================
        // Start the accept loop
        // =====================
        
        ACCEPT_LOOP: while abortFlag == false {
            
            
            // ===========================================================================
            // Calculate time to wait until either the pollInterval or the timeout expires
            // ===========================================================================
            
            let localTimeout: TimeInterval! = timeoutTime?.timeIntervalSinceNow ?? abortFlagPollInterval
            
            if localTimeout < 0.0 {
                telemetry?.endTime = Date()
                telemetry?.result = .timeout
                return .timeout
            }
            
            let availableSeconds = Int(localTimeout)
            let availableUSeconds = Int32((localTimeout - Double(availableSeconds)) * 1_000_000.0)
            var availableTimeval = timeval(tv_sec: availableSeconds, tv_usec: availableUSeconds)
            
            
            // =====================================================================================
            // Use the select API to wait for data to arrive on our socket within the timeout period
            // =====================================================================================
            
            let numOfFd:Int32 = socket + 1
            var readSet:fd_set = fd_set(fds_bits: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            
            fdSet(socket, set: &readSet)
            let status = select(numOfFd, &readSet, nil, nil, &availableTimeval)
            
            // Because we only specify 1 FD, we do not need to check on which FD the event was received
            
            
            // =====================================================================================
            // Evaluate the result of the select call
            // =====================================================================================
            
            if status == 0 { // nothing happened
                
                
                // Check for timeout
                
                if let t = timeoutTime?.timeIntervalSinceNow, t < 0.0 {
                    telemetry?.endTime = Date()
                    telemetry?.result = .timeout
                    return .timeout
                }
                
                
                // Increment the accept loop counter as a "sign of life"
                
                telemetry?.loopCounter += 1
                
                
                // Test for abort
                
                continue
            }
            
            // =====================================================================================
            // Exit in case of an error
            // =====================================================================================
            
            if status == -1 {
                
                switch errno {
                    
                case EBADF:
                    // Case 1: In a multi-threaded environment it can happen that one thread closes a socket while another thread is waiting for accept on the same socket.
                    // In that case this is not really an error, but simply a signal that the accepting thread should be terminated.
                    // Case 2: Of course it could also happen that the programmer made a mistake and is using a socket that is not initialized.
                    // The first case is more important, so as to avoid uneccesary error messages we return the CLOSED result case.
                    // If the programmer made an error, it is presumed that this error will become appearant in other ways (during testing!).
                    telemetry?.endTime = Date()
                    telemetry?.result = .closed
                    return .closed
                    
                case EINVAL, EAGAIN, EINTR: fallthrough // These are the other possible error's
                    
                default: // Catch-all to satisfy the compiler
                    let errString = String(validatingUTF8: strerror(errno)) ?? "Unknown error code"
                    telemetry?.endTime = Date()
                    telemetry?.result = .error(message: errString)
                    return .error(message: errString)
                }
            }

            
            // =======================================
            // Accept the incoming connection request
            // =======================================
            
            var clientSocket: Int32 = 0
            let clientSocketAddress = SocketAddress { sockAddrPointer, sockAddrLength in
                clientSocket = accept(socket, sockAddrPointer, sockAddrLength)
            }
            
            // Evalute the result of the accept call
            
            if clientSocket == -1 { // Error
                
                let strerr = String(validatingUTF8: strerror(errno)) ?? "Unknown error code"
                telemetry?.endTime = Date()
                telemetry?.result = .error(message: strerr)
                return .error(message: strerr)
                
                
            } else {  // Success, return the accepted socket
                
                
                // ================================================
                // Set the socket option: prevent SIGPIPE exception
                // ================================================
                
                var optval = 1;
                
                let status = setsockopt(
                    clientSocket,
                    SOL_SOCKET,
                    SO_NOSIGPIPE,
                    &optval,
                    socklen_t(MemoryLayout<Int>.size))
                
                if status == -1 {
                    let strError = String(validatingUTF8: strerror(errno)) ?? "Unknown error code"
                    closeSocket(clientSocket)
                    return .error(message: strError)
                }

                
                // ===========================================
                // get Ip Addres and Port number of the client
                // ===========================================
                
                if let (ipOrNil, portOrNil) = clientSocketAddress?.doWithPtr(body: { addr, _ in sockaddrDescription(addr) }) {
                    telemetry?.clientAddress = ipOrNil ?? "Unknown client address"
                    telemetry?.clientPort = portOrNil ?? "Unknown client port"
                } else {
                    telemetry?.clientAddress = "Unknown client address"
                    telemetry?.clientPort = "Unknown client port"
                }
                telemetry?.endTime = Date()
                telemetry?.result = .accepted(socket: clientSocket)
                telemetry?.acceptedConnections += 1
                
                return .accepted(socket: clientSocket)
            }
        }
        
        // ==================
        // Accept was aborted
        // ==================
        
        telemetry?.endTime = Date()
        telemetry?.result = .aborted

        return .aborted
    }

    
    /**
     Waits for a connection request to arrive on the given socket descriptor. The function returns when a connection has been accepted, when an error occured, when a timeout occured or when the static variable 'abortFlag' is set to 'true'. This function does not close any socket. This function is excepection based a wrapper for accept.
     
     - Parameter onSocket: The socket descriptor on which accept will listen for connection requests. This socket descriptor should have been initialized with "InitServerSocket" previously.
     - Parameter abortFlag: The function will terminate as soon as possible (see polling interval) when this variable is set to 'true'. This variable must be set to 'false' before the call, otherwise the function will terminate immediately.
     - Parameter abortFlagPollInterval: In the default mode (i.e. timeout == nil) the function will poll the inout variable abortFlag to abort the accept procedure. The interval is the time between evaluations of the abortFlag. If the argument is nil, the timeout argument *must* be non-nil. When used, the argument must be > 0. Setting this argument to an extremely low value wil result in high CPU loads, recommended minimum value is at least 1 second.
     - Parameter timeout: The maximum duration this function will wait for a connection request to arrive. When nil the abortFlag controls how long the accept loop will run (see also pollInterval). PollInterval and timeout can be used simultaniously.
     - Parameter telemetry: This class can be used if the callee wishes to monitor the accept function. See class description for details. If argument errors are found, the telemetry will not be updated.
     
     - Returns: The socket descriptor on which data can be received. This will be an 'accept'-ed socket, i.e. different from the socket argument. The callee is responsible for closing this socket.
     
     - Throws: The AcceptException when something fails.
     */
    
    public static func acceptOrThrow(
        onSocket socket: Int32,
        abortFlag: inout Bool,
        abortFlagPollInterval: TimeInterval?,
        timeout: TimeInterval? = nil,
        telemetry: AcceptTelemetry?) throws -> Int32
    {
        let result = acceptNoThrow(onSocket: socket, abortFlag: &abortFlag, abortFlagPollInterval: abortFlagPollInterval, timeout: timeout, telemetry: telemetry)
        
        switch result {
        case .timeout: throw AcceptException.timeout
        case .aborted: throw AcceptException.aborted
        case .closed: throw AcceptException.closed
        case let .error(message: msg): throw AcceptException.message(msg)
        case let .accepted(socket: socket):
            return socket
        }
    }
}
