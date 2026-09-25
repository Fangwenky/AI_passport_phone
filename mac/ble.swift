import Foundation
import CoreBluetooth

let serviceID = CBUUID(string: "b0c6a200-83c8-477a-a051-d567ebc13d01")
let authID = CBUUID(string: "b0c6a201-83c8-477a-a051-d567ebc13d01")
let configID = CBUUID(string: "b0c6a202-83c8-477a-a051-d567ebc13d01")
let pinID = CBUUID(string: "b0c6a203-83c8-477a-a051-d567ebc13d01")

guard CommandLine.arguments.count == 6 else {
    fputs("Usage: ble <host> <port> <token> <certificate sha256> <pairing code>\n", stderr)
    exit(2)
}

final class PassportPeripheral: NSObject, CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager!
    private var service: CBMutableService!
    private var auth: CBMutableCharacteristic!
    private var config: CBMutableCharacteristic!
    private var pin: CBMutableCharacteristic!
    private let host: String
    private let port: String
    private let token: String
    private let fingerprint: String
    private let code: String
    private var permitted = Set<UUID>()
    private var failedAttempts = 0
    private var retryAfter = Date.distantPast

    init(host: String, port: String, token: String, fingerprint: String, code: String) {
        self.host = host; self.port = port; self.token = token; self.fingerprint = fingerprint; self.code = code
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
        fputs("Bluetooth authorization: \(CBPeripheralManager.authorization.rawValue)\n", stderr)
        fputs("Redmi pairing code: \(code)\n", stderr)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            fputs("Bluetooth state: \(peripheral.state.rawValue)\n", stderr)
            return
        }
        auth = CBMutableCharacteristic(type: authID, properties: [.write], value: nil,
                                       permissions: [.writeable])
        config = CBMutableCharacteristic(type: configID, properties: [.read], value: nil,
                                         permissions: [.readable])
        pin = CBMutableCharacteristic(type: pinID, properties: [.read], value: nil,
                                      permissions: [.readable])
        service = CBMutableService(type: serviceID, primary: true)
        service.characteristics = [auth, config, pin]
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { fputs("Bluetooth service failed: \(error)\n", stderr); return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceID],
                                     CBAdvertisementDataLocalNameKey: "Redmi AI Passport"])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        fputs(error == nil ? "Bluetooth ready\n" : "Bluetooth advertising failed: \(error!)\n", stderr)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if Date() < retryAfter {
                peripheral.respond(to: request, withResult: .insufficientAuthentication)
                continue
            }
            guard request.characteristic.uuid == authID,
                  let value = request.value,
                  let entered = String(data: value, encoding: .utf8),
                  entered == code else {
                failedAttempts += 1
                if failedAttempts >= 5 { retryAfter = Date().addingTimeInterval(60); failedAttempts = 0 }
                peripheral.respond(to: request, withResult: .insufficientAuthentication)
                continue
            }
            failedAttempts = 0
            permitted.insert(request.central.identifier)
            peripheral.respond(to: request, withResult: .success)
            fputs("Redmi paired over Bluetooth\n", stderr)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard permitted.contains(request.central.identifier) else {
            peripheral.respond(to: request, withResult: .insufficientAuthentication)
            return
        }
        let value: String
        if request.characteristic.uuid == configID { value = "\(host):\(port):\(token)" }
        else if request.characteristic.uuid == pinID { value = fingerprint }
        else { peripheral.respond(to: request, withResult: .attributeNotFound); return }
        let bytes = Data(value.utf8)
        guard request.offset <= bytes.count else {
            peripheral.respond(to: request, withResult: .invalidOffset); return
        }
        request.value = bytes.subdata(in: request.offset..<bytes.count)
        peripheral.respond(to: request, withResult: .success)
    }
}

let peripheral = PassportPeripheral(host: CommandLine.arguments[1], port: CommandLine.arguments[2],
                                    token: CommandLine.arguments[3], fingerprint: CommandLine.arguments[4],
                                    code: CommandLine.arguments[5])
RunLoop.main.run()
