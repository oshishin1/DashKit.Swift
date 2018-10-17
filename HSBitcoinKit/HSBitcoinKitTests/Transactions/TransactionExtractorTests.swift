import XCTest
import Cuckoo
import RealmSwift
@testable import HSBitcoinKit

class TransactionExtractorTests: XCTestCase {

    private var pfromsh: MockPFromSHExtractor!
    private var p2pkh: MockP2PKHExtractor!
    private var p2pk: MockP2PKExtractor!
    private var p2sh: MockP2SHExtractor!
    private var addressConverter: MockAddressConverter!
    private var scriptConverter: MockScriptConverter!
    private var realm: Realm!
    private var inputExtractors: [ScriptExtractor]!
    private var outputExtractors: [ScriptExtractor]!
    private var extractor: TransactionExtractor!

    private var p2pkhTransaction: Transaction!
    private var p2pkTransaction: Transaction!
    private var p2shTransaction: Transaction!

    override func setUp() {
        super.setUp()

        let mockBitcoinKit = MockBitcoinKit()

        pfromsh = MockPFromSHExtractor()
        p2pkh = MockP2PKHExtractor()
        p2pk = MockP2PKExtractor()
        p2sh = MockP2SHExtractor()
        addressConverter = MockAddressConverter(network: BitcoinTestNet(validatorFactory: mockBitcoinKit.mockValidatorFactory), bech32AddressConverter: SegWitBech32AddressConverter())
        scriptConverter = MockScriptConverter()
        realm = mockBitcoinKit.realm

        inputExtractors = [pfromsh]
        outputExtractors = [p2pkh, p2pk, p2sh]

        extractor = TransactionExtractor(scriptInputExtractors: inputExtractors, scriptOutputExtractors: outputExtractors, scriptConverter: scriptConverter, addressConverter: addressConverter)

        stub(pfromsh) { mock in
            when(mock.type.get).thenReturn(.p2sh)
            when(mock.extract(from: any(), converter: any())).thenThrow(ScriptError.wrongScriptLength)
        }
        stub(p2pkh) { mock in
            when(mock.type.get).thenReturn(.p2pkh)
            when(mock.extract(from: any(), converter: any())).thenThrow(ScriptError.wrongScriptLength)
        }
        stub(p2pk) { mock in
            when(mock.type.get).thenReturn(.p2pk)
            when(mock.extract(from: any(), converter: any())).thenThrow(ScriptError.wrongScriptLength)
        }
        stub(p2sh) { mock in
            when(mock.type.get).thenReturn(.p2sh)
            when(mock.extract(from: any(), converter: any())).thenThrow(ScriptError.wrongScriptLength)
        }
        stub(scriptConverter) { mock in
            when(mock.decode(data: any())).thenReturn(Script(with: Data(), chunks: []))
        }
        stub(addressConverter) { mock in
            when(mock.convert(keyHash: any(), type: any())).thenReturn(LegacyAddress(type: .pubKeyHash, keyHash: Data(), base58: ""))
        }

        p2pkhTransaction = TestData.p2pkhTransaction
        p2pkTransaction = TestData.p2pkTransaction
        p2shTransaction = TestData.p2shTransaction
    }

    override func tearDown() {
        extractor = nil
        inputExtractors = nil
        outputExtractors = nil
        addressConverter = nil
        scriptConverter = nil
        realm = nil

        pfromsh = nil
        p2pkh = nil
        p2pk = nil
        p2sh = nil
        p2pkhTransaction = nil
        p2pkTransaction = nil
        p2shTransaction = nil

        super.tearDown()
    }

    func testExtractP2pkhTransaction() {
        let keyHash = Data(hex: "1ec865abcb88cec71c484d4dadec3d7dc0271a7b")!

        stub(p2pkh) { mock in
            when(mock.extract(from: any(), converter: any())).thenReturn(keyHash)
        }
        extractor.extract(transaction: p2pkhTransaction, realm: realm)

        if let testHash = p2pkhTransaction.outputs[0].keyHash {
            XCTAssertEqual(testHash, keyHash)
            XCTAssertEqual(p2pkhTransaction.outputs[0].scriptType, .p2pkh)
        } else {
            XCTFail("KeyHash not found!")
        }
    }

    func testExtractP2pkTransaction() {
        let keyHash = Data(hex: "e4de5d630c5cacd7af96418a8f35c411c8ff3c06")!

        stub(p2pk) { mock in
            when(mock.extract(from: any(), converter: any())).thenReturn(keyHash)
        }

        extractor.extract(transaction: p2pkTransaction, realm: realm)

        if let testHash = p2pkTransaction.outputs[0].keyHash {
            XCTAssertEqual(testHash, keyHash)
            XCTAssertEqual(p2pkTransaction.outputs[0].scriptType, .p2pk)
        } else {
            XCTFail("KeyHash not found!")
        }
    }

    func testExtractP2shTransaction() {
        let keyHash = Data(hex: "bd82ef4973ebfcbc8f7cb1d540ef0503a791970b")!

        stub(p2sh) { mock in
            when(mock.extract(from: any(), converter: any())).thenReturn(keyHash)
        }

        extractor.extract(transaction: p2shTransaction, realm: realm)

        if let testHash = p2shTransaction.outputs[0].keyHash {
            XCTAssertEqual(testHash, keyHash)
            XCTAssertEqual(p2shTransaction.outputs[0].scriptType, .p2sh)
        } else {
            XCTFail("KeyHash not found!")
        }
    }

    func testAssignAddress() {
        let keyHash = Data(hex: "1ec865abcb88cec71c484d4dadec3d7dc0271a7b")!
        let address = "msGCb97sW9s9Mt7gN5m7TGmwLqhqGaFqYz"

        stub(p2pkh) { mock in
            when(mock.extract(from: any(), converter: any())).thenReturn(keyHash)
        }
        stub(addressConverter) { mock in
            when(mock.convert(keyHash: any(), type: any())).thenReturn(LegacyAddress(type: .pubKeyHash, keyHash: Data(), base58: address))
        }

        extractor.extract(transaction: p2pkhTransaction, realm: realm)

        if let assignedAddress = p2pkhTransaction.outputs[0].address {
            XCTAssertEqual(assignedAddress, address)
        } else {
            XCTFail("Address not found!")
        }
    }

}