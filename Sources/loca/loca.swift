import CoreLocation
import Darwin
import Foundation

private let version = "0.1.2"
private let stderrIsTTY = isatty(fileno(stderr)) == 1

private enum Command {
    case help
    case version
    case run(Options)
}

private struct Options {
    enum Output: String {
        case interactive
        case text
        case json
    }

    enum Accuracy: String, CaseIterable {
        case best
        case tenMeters = "10m"
        case hundredMeters = "100m"
        case kilometer = "1km"
        case threeKilometers = "3km"

        var coreLocationValue: CLLocationAccuracy {
            switch self {
            case .best:
                return kCLLocationAccuracyBest
            case .tenMeters:
                return kCLLocationAccuracyNearestTenMeters
            case .hundredMeters:
                return kCLLocationAccuracyHundredMeters
            case .kilometer:
                return kCLLocationAccuracyKilometer
            case .threeKilometers:
                return kCLLocationAccuracyThreeKilometers
            }
        }
    }

    var output: Output = .interactive
    var timeout: TimeInterval = 20
    var accuracy: Accuracy = .hundredMeters
    var statusOnly = false
}

private struct StatusPayload: Encodable {
    let locationServicesEnabled: Bool
    let authorizationStatus: String
}

private struct LocationPayload: Encodable {
    let latitude: Double
    let longitude: Double
    let city: String
    let region: String
    let country: String
    let timestamp: String
    let source: String
}

private struct ProviderLocation {
    let latitude: Double
    let longitude: Double
    let city: String
    let region: String
    let country: String
}

private enum CLIError: LocalizedError {
    case invalidOption(String)
    case missingValue(String)
    case invalidValue(flag: String, value: String)
    case locationServicesDisabled
    case authorizationDenied
    case authorizationRestricted
    case authorizationNotDetermined
    case timeout(TimeInterval)
    case locationUnavailable
    case locationFailure(String)
    case ipFallbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidOption(let option):
            return "Unknown option: \(option). Use --help for usage."
        case .missingValue(let flag):
            return "\(flag) requires a value."
        case .invalidValue(let flag, let value):
            return "Invalid value '\(value)' for \(flag)."
        case .locationServicesDisabled:
            return "Location Services are disabled on this Mac."
        case .authorizationDenied:
            return "Location permission was denied."
        case .authorizationRestricted:
            return "Location access is restricted by system policy."
        case .authorizationNotDetermined:
            return "Location permission is still not determined."
        case .timeout(let seconds):
            return "Timed out after \(formatTimeout(seconds))s waiting for CoreLocation."
        case .locationUnavailable:
            return "No location was returned by CoreLocation."
        case .locationFailure(let message):
            return "CoreLocation failed: \(message)"
        case .ipFallbackFailed(let message):
            return "IP fallback failed: \(message)"
        }
    }
}

private struct IPInfoResponse: Decodable {
    let city: String?
    let region: String?
    let country: String?
    let loc: String?
}

private struct IfconfigResponse: Decodable {
    let city: String?
    let region_name: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
}

private struct GeolocationDBResponse: Decodable {
    let city: String?
    let state: String?
    let country_name: String?
    let latitude: Double?
    let longitude: Double?
}

private struct IPWhoisAppResponse: Decodable {
    let success: Bool?
    let city: String?
    let region: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let message: String?
}

private struct IPWhoIsResponse: Decodable {
    let success: Bool?
    let city: String?
    let region: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let message: String?
}

private struct IPAPICoResponse: Decodable {
    let city: String?
    let region: String?
    let country_name: String?
    let latitude: Double?
    let longitude: Double?
    let error: Bool?
    let reason: String?
    let message: String?
}

private struct IPAPIComResponse: Decodable {
    let status: String?
    let city: String?
    let regionName: String?
    let country: String?
    let lat: Double?
    let lon: Double?
    let message: String?
}

private final class PlacemarkBox: @unchecked Sendable {
    var placemark: CLPlacemark?
}

private final class CoreLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var result: Result<LocationPayload, CLIError>?
    private var deadline = Date()
    private var timeoutSeconds: TimeInterval = 20
    private let geocoder = CLGeocoder()

    func fetch(timeout: TimeInterval, accuracy: CLLocationAccuracy) -> Result<LocationPayload, CLIError> {
        guard CLLocationManager.locationServicesEnabled() else {
            return .failure(.locationServicesDisabled)
        }

        timeoutSeconds = timeout
        deadline = Date().addingTimeInterval(timeout)
        manager.delegate = self
        manager.desiredAccuracy = accuracy
        manager.distanceFilter = 2

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()

        while result == nil {
            if Date() >= deadline {
                manager.stopUpdatingLocation()
                if manager.authorizationStatus == .notDetermined {
                    finish(.failure(.authorizationNotDetermined))
                } else {
                    finish(.failure(.timeout(timeoutSeconds)))
                }
                break
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        return result ?? .failure(.timeout(timeoutSeconds))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied:
            finish(.failure(.authorizationDenied))
        case .restricted:
            finish(.failure(.authorizationRestricted))
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.max(by: { $0.timestamp < $1.timestamp }) else {
            finish(.failure(.locationUnavailable))
            return
        }

        manager.stopUpdatingLocation()
        let (city, region, country) = reverseGeocode(location: location, timeout: 4)
        finish(
            .success(
                LocationPayload(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    city: city,
                    region: region,
                    country: country,
                    timestamp: isoTimestamp(from: location.timestamp),
                    source: "core_location"
                )
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        finish(.failure(.locationFailure(error.localizedDescription)))
    }

    private func reverseGeocode(location: CLLocation, timeout: TimeInterval) -> (String, String, String) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = PlacemarkBox()
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            box.placemark = placemarks?.first
            semaphore.signal()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if semaphore.wait(timeout: .now()) == .success {
                break
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return (
            cityFromPlacemark(box.placemark),
            regionFromPlacemark(box.placemark),
            countryFromPlacemark(box.placemark)
        )
    }

    private func finish(_ newResult: Result<LocationPayload, CLIError>) {
        guard result == nil else { return }
        result = newResult
    }
}

private func parseCommandLine() throws -> Command {
    var options = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var index = 0

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "-h", "--help":
            return .help
        case "-v", "--version":
            return .version
        case "--status":
            options.statusOnly = true
        case "--text":
            options.output = .text
        case "-j", "--json":
            options.output = .json
        case "-t", "--timeout":
            index += 1
            guard index < args.count else { throw CLIError.missingValue(arg) }
            guard let timeout = TimeInterval(args[index]), timeout > 0 else {
                throw CLIError.invalidValue(flag: arg, value: args[index])
            }
            options.timeout = timeout
        case "-a", "--accuracy":
            index += 1
            guard index < args.count else { throw CLIError.missingValue(arg) }
            guard let accuracy = Options.Accuracy(rawValue: args[index]) else {
                throw CLIError.invalidValue(flag: arg, value: args[index])
            }
            options.accuracy = accuracy
        default:
            throw CLIError.invalidOption(arg)
        }
        index += 1
    }

    return .run(options)
}

private func authorizationString(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways:
        return "authorized_always"
    case .authorizedWhenInUse:
        return "authorized_when_in_use"
    case .denied:
        return "denied"
    case .restricted:
        return "restricted"
    case .notDetermined:
        return "not_determined"
    @unknown default:
        return "unknown"
    }
}

private func printHelp() {
    let accuracyValues = Options.Accuracy.allCases.map(\.rawValue).joined(separator: ", ")
    print(
        """
        loca \(version)
        Get your Mac's current location.
        CoreLocation is always attempted first; IP fallback is only used if it fails.

        Usage:
          loca [options]

        Options:
          -h, --help              Show help
          -v, --version           Show version
          --status                Print location permission/service status only
          --text                  Plain text output (no progress logs)
          -j, --json              Output JSON
          -t, --timeout <sec>     Timeout in seconds (default: 20)
          -a, --accuracy <value>  Accuracy: \(accuracyValues) (default: 100m)
        """
    )
}

private func printStatus(output: Options.Output) {
    let manager = CLLocationManager()
    let payload = StatusPayload(
        locationServicesEnabled: CLLocationManager.locationServicesEnabled(),
        authorizationStatus: authorizationString(manager.authorizationStatus)
    )

    switch output {
    case .interactive, .text:
        print("location_services_enabled: \(payload.locationServicesEnabled)")
        print("authorization_status: \(payload.authorizationStatus)")
    case .json:
        printJSON(payload)
    }
}

private func fetchIPFallback(showProgress: Bool) -> Result<LocationPayload, CLIError> {
    printProgress("Falling back to IP geolocation providers...", enabled: showProgress)

    let providers: [(String, String)] = [
        ("ipinfo", "https://ipinfo.io/json"),
        ("ifconfig", "https://ifconfig.co/json"),
        ("geolocation-db", "https://geolocation-db.com/json/"),
        ("ipwhois.app", "https://ipwhois.app/json/"),
        ("ipwho.is", "https://ipwho.is/"),
        ("ipapi.co", "https://ipapi.co/json/"),
        ("ip-api.com", "http://ip-api.com/json/"),
    ]

    var errors: [String] = []

    for (providerName, url) in providers {
        printProgress("Trying \(providerName)", enabled: showProgress)
        switch runCurl(url: url) {
        case .failure(let error):
            errors.append("\(providerName): \(error.localizedDescription)")
        case .success(let data):
            switch decodeProviderData(providerName: providerName, data: data) {
            case .failure(let error):
                errors.append("\(providerName): \(error.localizedDescription)")
            case .success(let providerLocation):
                let enriched = enrichWithReverseGeocode(providerLocation)
                return .success(
                    LocationPayload(
                        latitude: enriched.latitude,
                        longitude: enriched.longitude,
                        city: enriched.city,
                        region: enriched.region,
                        country: enriched.country,
                        timestamp: isoTimestamp(from: Date()),
                        source: "ip_fallback"
                    )
                )
            }
        }
    }

    return .failure(.ipFallbackFailed(errors.joined(separator: " | ")))
}

private func decodeProviderData(providerName: String, data: Data) -> Result<ProviderLocation, CLIError> {
    let decoder = JSONDecoder()

    do {
        switch providerName {
        case "ipinfo":
            let response = try decoder.decode(IPInfoResponse.self, from: data)
            guard let loc = response.loc else {
                return .failure(.ipFallbackFailed("ipinfo missing loc"))
            }
            let parts = loc.split(separator: ",")
            guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else {
                return .failure(.ipFallbackFailed("ipinfo invalid loc"))
            }
            return .success(
                ProviderLocation(
                    latitude: lat,
                    longitude: lon,
                    city: response.city ?? "",
                    region: response.region ?? "",
                    country: countryName(fromRegionCode: response.country ?? "")
                )
            )

        case "ifconfig":
            let response = try decoder.decode(IfconfigResponse.self, from: data)
            guard let lat = response.latitude, let lon = response.longitude else {
                return .failure(.ipFallbackFailed("ifconfig missing coordinates"))
            }
            return .success(
                ProviderLocation(
                    latitude: lat,
                    longitude: lon,
                    city: response.city ?? "",
                    region: response.region_name ?? "",
                    country: response.country ?? ""
                )
            )

        case "geolocation-db":
            let response = try decoder.decode(GeolocationDBResponse.self, from: data)
            guard let lat = response.latitude, let lon = response.longitude else {
                return .failure(.ipFallbackFailed("geolocation-db missing coordinates"))
            }
            return .success(
                ProviderLocation(
                    latitude: lat,
                    longitude: lon,
                    city: response.city ?? "",
                    region: response.state ?? "",
                    country: response.country_name ?? ""
                )
            )

        case "ipwhois.app":
            let response = try decoder.decode(IPWhoisAppResponse.self, from: data)
            if response.success == false {
                return .failure(.ipFallbackFailed(response.message ?? "ipwhois.app failed"))
            }
            guard let lat = response.latitude, let lon = response.longitude else {
                return .failure(.ipFallbackFailed("ipwhois.app missing coordinates"))
            }
            return .success(
                ProviderLocation(
                    latitude: lat,
                    longitude: lon,
                    city: response.city ?? "",
                    region: response.region ?? "",
                    country: response.country ?? ""
                )
            )

        case "ipwho.is":
            let response = try decoder.decode(IPWhoIsResponse.self, from: data)
            if response.success == false {
                return .failure(.ipFallbackFailed(response.message ?? "ipwho.is failed"))
            }
            guard let lat = response.latitude, let lon = response.longitude else {
                return .failure(.ipFallbackFailed("ipwho.is missing coordinates"))
            }
            return .success(
                ProviderLocation(
                    latitude: lat,
                    longitude: lon,
                    city: response.city ?? "",
                    region: response.region ?? "",
                    country: response.country ?? ""
                )
            )

        case "ipapi.co":
            let response = try decoder.decode(IPAPICoResponse.self, from: data)
            if response.error == true {
                let message = response.reason ?? response.message ?? "ipapi.co error"
                return .failure(.ipFallbackFailed(message))
            }
            guard let lat = response.latitude, let lon = response.longitude else {
                return .failure(.ipFallbackFailed("ipapi.co missing coordinates"))
            }
            return .success(
                ProviderLocation(
                    latitude: lat,
                    longitude: lon,
                    city: response.city ?? "",
                    region: response.region ?? "",
                    country: response.country_name ?? ""
                )
            )

        case "ip-api.com":
            let response = try decoder.decode(IPAPIComResponse.self, from: data)
            if response.status == "fail" {
                return .failure(.ipFallbackFailed(response.message ?? "ip-api.com failed"))
            }
            guard let lat = response.lat, let lon = response.lon else {
                return .failure(.ipFallbackFailed("ip-api.com missing coordinates"))
            }
            return .success(
                ProviderLocation(
                    latitude: lat,
                    longitude: lon,
                    city: response.city ?? "",
                    region: response.regionName ?? "",
                    country: response.country ?? ""
                )
            )

        default:
            return .failure(.ipFallbackFailed("Unsupported provider"))
        }
    } catch {
        return .failure(.ipFallbackFailed("Invalid JSON for \(providerName)"))
    }
}

private func enrichWithReverseGeocode(_ providerLocation: ProviderLocation) -> ProviderLocation {
    let location = CLLocation(latitude: providerLocation.latitude, longitude: providerLocation.longitude)
    let geocoder = CLGeocoder()
    let box = PlacemarkBox()
    let semaphore = DispatchSemaphore(value: 0)

    geocoder.reverseGeocodeLocation(location) { placemarks, _ in
        box.placemark = placemarks?.first
        semaphore.signal()
    }

    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        if semaphore.wait(timeout: .now()) == .success {
            break
        }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    let city = emptyToFallback(cityFromPlacemark(box.placemark), fallback: providerLocation.city)
    let region = emptyToFallback(regionFromPlacemark(box.placemark), fallback: providerLocation.region)
    let country = emptyToFallback(countryFromPlacemark(box.placemark), fallback: providerLocation.country)

    return ProviderLocation(
        latitude: providerLocation.latitude,
        longitude: providerLocation.longitude,
        city: city,
        region: region,
        country: country
    )
}

private func emptyToFallback(_ value: String?, fallback: String) -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return fallback
    }
    return value
}

private func firstNonEmpty(_ values: [String?]) -> String {
    for value in values {
        if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
    }
    return ""
}

private func cityFromPlacemark(_ placemark: CLPlacemark?) -> String {
    firstNonEmpty([
        placemark?.locality,
        placemark?.subAdministrativeArea,
        placemark?.subLocality,
        placemark?.name,
    ])
}

private func regionFromPlacemark(_ placemark: CLPlacemark?) -> String {
    firstNonEmpty([
        placemark?.administrativeArea,
        placemark?.subAdministrativeArea,
    ])
}

private func countryFromPlacemark(_ placemark: CLPlacemark?) -> String {
    firstNonEmpty([
        placemark?.country,
        countryName(fromRegionCode: placemark?.isoCountryCode ?? ""),
    ])
}

private func runCurl(url: String) -> Result<Data, CLIError> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = ["--silent", "--show-error", "--location", "--max-time", "6", url]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
        process.waitUntilExit()

        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            return .failure(.ipFallbackFailed(errorText?.isEmpty == false ? errorText! : "curl failed"))
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            return .failure(.ipFallbackFailed("Empty response body"))
        }

        return .success(data)
    } catch {
        return .failure(.ipFallbackFailed(error.localizedDescription))
    }
}

private func printLocation(_ payload: LocationPayload, output: Options.Output) {
    switch output {
    case .interactive, .text:
        print(String(format: "latitude: %.6f", payload.latitude))
        print(String(format: "longitude: %.6f", payload.longitude))
        print("city: \(payload.city)")
        print("region: \(payload.region)")
        print("country: \(payload.country)")
        print("timestamp: \(payload.timestamp)")
        print("source: \(payload.source)")
    case .json:
        printJSON(payload)
    }
}

private func printProgress(_ message: String, enabled: Bool) {
    guard enabled, stderrIsTTY else { return }
    fputs("loca: \(message)\n", stderr)
}

private func hostPermissionHint(for error: CLIError) -> String? {
    let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"]?.lowercased() ?? ""
    let isGhostty = termProgram.contains("ghostty")

    if isGhostty {
        switch error {
        case .authorizationDenied, .authorizationNotDetermined:
            return "Ghostty may not present a Location prompt for child CLIs. Run once in Terminal.app or use a bundled helper app identity."
        case .locationFailure(let message) where message.contains("kCLErrorDomain error 1"):
            return "Ghostty returned location denied immediately. Run once in Terminal.app or use a bundled helper app identity."
        default:
            return nil
        }
    }
    return nil
}

private func printJSON<T: Encodable>(_ payload: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

private func formatTimeout(_ value: TimeInterval) -> String {
    let rounded = Int(value.rounded())
    return value == TimeInterval(rounded) ? String(rounded) : String(format: "%.1f", value)
}

private func isoTimestamp(from date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func countryName(fromRegionCode code: String) -> String {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 2 else { return trimmed }
    let locale = Locale(identifier: "en_US_POSIX")
    return locale.localizedString(forRegionCode: trimmed.uppercased()) ?? trimmed
}

@main
private struct LocaCLI {
    static func main() {
        do {
            switch try parseCommandLine() {
            case .help:
                printHelp()
            case .version:
                print("loca \(version)")
            case .run(let options):
                if options.statusOnly {
                    printStatus(output: options.output)
                    return
                }

                let showProgress = options.output == .interactive
                printProgress("Requesting CoreLocation location (timeout \(formatTimeout(options.timeout))s)...", enabled: showProgress)
                let fetcher = CoreLocationFetcher()
                switch fetcher.fetch(timeout: options.timeout, accuracy: options.accuracy.coreLocationValue) {
                case .success(let payload):
                    printProgress("Using CoreLocation result.", enabled: showProgress)
                    printLocation(payload, output: options.output)
                case .failure(let coreLocationError):
                    printProgress("CoreLocation unavailable (\(coreLocationError.localizedDescription)).", enabled: showProgress)
                    if let hint = hostPermissionHint(for: coreLocationError) {
                        printProgress(hint, enabled: showProgress)
                    }
                    switch fetchIPFallback(showProgress: showProgress) {
                    case .success(let fallbackPayload):
                        printProgress("Using IP fallback result.", enabled: showProgress)
                        printLocation(fallbackPayload, output: options.output)
                    case .failure(let fallbackError):
                        fputs("loca: \(coreLocationError.localizedDescription)\n", stderr)
                        fputs("loca: \(fallbackError.localizedDescription)\n", stderr)
                        exit(1)
                    }
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            fputs("loca: \(message)\n", stderr)
            exit(1)
        }
    }
}
