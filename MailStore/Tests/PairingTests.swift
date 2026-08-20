import Foundation
import MailStore
import Testing

struct PairingTests {
    @Test func missingCredentialFailsClosed() throws {
        let pairing = Pairing()
        _ = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: "secret-token"
        )

        #expect(throws: PairingError.unauthorized) {
            try pairing.authenticate(credential: nil)
        }
    }

    @Test func wrongCredentialFailsClosed() throws {
        let pairing = Pairing()
        _ = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: "secret-token"
        )

        #expect(throws: PairingError.unauthorized) {
            try pairing.authenticate(credential: "other-token")
        }
    }

    @Test func matchingCredentialReturnsPairedAgent() throws {
        let pairing = Pairing()
        let registered = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: "secret-token"
        )

        let agent = try pairing.authenticate(credential: "secret-token")
        #expect(agent.id == registered.id)
        #expect(agent.name == "Cursor")
        #expect(agent.trustClass == .machineLocal)
    }

    @Test func revokeStopsAccessImmediately() throws {
        let pairing = Pairing()
        let registered = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: "secret-token"
        )

        pairing.revoke(agentID: registered.id)

        #expect(throws: PairingError.unauthorized) {
            try pairing.authenticate(credential: "secret-token")
        }
    }
}
