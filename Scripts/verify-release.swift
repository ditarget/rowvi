import CryptoKit
import Foundation

enum VerificationError: Error {
    case invalidPublicKey
    case invalidAppcastSignature
    case invalidArchiveSignature
}

let arguments = CommandLine.arguments
guard arguments.count == 5, let publicKey = Data(base64Encoded: arguments[1]) else {
    throw VerificationError.invalidPublicKey
}

let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
let appcast = try Data(contentsOf: URL(filePath: arguments[2]))
let marker = Data("<!-- sparkle-signatures:\n".utf8)
guard let signatureRange = appcast.range(of: marker, options: .backwards),
      let trailer = String(data: appcast[signatureRange.upperBound...], encoding: .utf8) else {
    throw VerificationError.invalidAppcastSignature
}

let fields = trailer.split(separator: "\n")
let signaturePrefix = "edSignature: "
let lengthPrefix = "length: "
let signedAppcast = appcast[..<signatureRange.lowerBound]
guard fields.count == 3, fields[2] == "-->",
      fields[0].hasPrefix(signaturePrefix), fields[1].hasPrefix(lengthPrefix),
      Int(fields[1].dropFirst(lengthPrefix.count)) == signedAppcast.count,
      let feedSignature = Data(base64Encoded: String(fields[0].dropFirst(signaturePrefix.count))),
      key.isValidSignature(feedSignature, for: signedAppcast) else {
    throw VerificationError.invalidAppcastSignature
}

let archive = try Data(contentsOf: URL(filePath: arguments[3]), options: .mappedIfSafe)
guard let archiveSignature = Data(base64Encoded: arguments[4]),
      key.isValidSignature(archiveSignature, for: archive) else {
    throw VerificationError.invalidArchiveSignature
}
