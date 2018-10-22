import HSCryptoKit
import RealmSwift

class BlockSyncer {

    private let realmFactory: IRealmFactory
    private let network: INetwork
    private let progressSyncer: IProgressSyncer
    private let transactionProcessor: ITransactionProcessor
    private let blockchain: IBlockchain
    private let addressManager: IAddressManager
    private let bloomFilterManager: IBloomFilterManager

    private let hashCheckpointThreshold: Int
    private var needToReDownload = false

    init(realmFactory: IRealmFactory, network: INetwork, progressSyncer: IProgressSyncer,
         transactionProcessor: ITransactionProcessor, blockchain: IBlockchain, addressManager: IAddressManager, bloomFilterManager: IBloomFilterManager,
         hashCheckpointThreshold: Int = 100) {
        self.realmFactory = realmFactory
        self.network = network
        self.progressSyncer = progressSyncer
        self.transactionProcessor = transactionProcessor
        self.blockchain = blockchain
        self.addressManager = addressManager
        self.bloomFilterManager = bloomFilterManager
        self.hashCheckpointThreshold = hashCheckpointThreshold

        let realm = realmFactory.realm
        if realm.objects(Block.self).count == 0, let checkpointBlockHeader = network.checkpointBlock.header {
            let checkpointBlock = Block(withHeader: checkpointBlockHeader, height: network.checkpointBlock.height)
            try? realm.write {
                realm.add(checkpointBlock)
            }
        }
    }

    // We need to clear block hashes when sync peer is disconnected
    private func clearBlockHashes() throws {
        let realm = realmFactory.realm

        try realm.write {
            realm.delete(realm.objects(BlockHash.self).filter("height = 0"))
        }
    }

    private func clearNotFullBlocks() throws {
        let realm = realmFactory.realm
        guard let blockHash = realm.objects(BlockHash.self).filter("height = 0").sorted(byKeyPath: "order").first else {
            return
        }

        var block = realm.objects(Block.self).filter("headerHash = %@", blockHash.headerHash).first

        try realm.write {
            while let resolvedBlock = block {
                block = nil
                let blockHash = resolvedBlock.headerHash

                for transaction in resolvedBlock.transactions {
                    for output in transaction.outputs {
                        realm.delete(output)
                    }
                    for input in transaction.inputs {
                        realm.delete(input)
                    }
                    realm.delete(transaction)
                }
                realm.delete(resolvedBlock)

                if let blockHeader = realm.objects(BlockHeader.self).filter("previousBlockHeaderHash = %@", blockHash).first {
                    block = realm.objects(Block.self).filter("header = %@", blockHeader).first
                }
            }
        }
    }

    private func handleFork() {
        // todo
    }

    private func hasUnspentOutputs(transaction: Transaction) -> Bool {
        for output in transaction.outputs {
            if output.scriptType == .p2wpkh || output.scriptType == .p2pk  {
                return true
            }
        }

        return false
    }
}

extension BlockSyncer: IBlockSyncer {

    func prepareForDownload() {
        do {
            try addressManager.fillGap()
            bloomFilterManager.regenerateBloomFilter()
            needToReDownload = false

            try clearNotFullBlocks()
            try clearBlockHashes()

            handleFork()
        } catch {
            print(error)
        }
    }

    func downloadStarted() {
    }

    func downloadIterationCompleted() {
        try? addressManager.fillGap()
        bloomFilterManager.regenerateBloomFilter()
        needToReDownload = false
    }

    func downloadCompleted() {
        handleFork()
    }

    func downloadFailed() {
        prepareForDownload()
    }

    func getBlockHashes() -> [Data] {
        let realm = realmFactory.realm
        let blockHashes = realm.objects(BlockHash.self).sorted(byKeyPath: "order")

        return blockHashes.prefix(500).map { blockHash in blockHash.headerHash }
    }

    func getBlockLocatorHashes() -> [Data] {
        let realm = realmFactory.realm
        var blockLocatorHashes = [Data]()

        if let lastBlockHash = realm.objects(BlockHash.self).filter("height = 0").sorted(byKeyPath: "order").last {
            blockLocatorHashes.append(lastBlockHash.headerHash)
        }

        if blockLocatorHashes.isEmpty {
            realm.objects(Block.self).sorted(byKeyPath: "height", ascending: false).prefix(10).forEach { block in
                blockLocatorHashes.append(block.headerHash)
            }
        }

        blockLocatorHashes.append(network.checkpointBlock.headerHash)

        return blockLocatorHashes
    }

    func add(blockHashes: [Data]) {
        let realm = realmFactory.realm
        var lastOrder = 0

        if let lastHash = realm.objects(BlockHash.self).sorted(byKeyPath: "order").last {
            lastOrder = lastHash.order
        }

        var hashes = [BlockHash]()
        for hash in blockHashes {
            lastOrder = lastOrder + 1
            hashes.append(BlockHash(withHeaderHash: hash, height: 0, order: lastOrder))
        }

        try? realm.write {
            realm.add(hashes)
        }
    }

    func handle(merkleBlock: MerkleBlock) throws {
        let realm = realmFactory.realm

        try? realm.write {
            guard let block = try blockchain.connect(merkleBlock: merkleBlock, realm: realm) else {
                return
            }

            for transaction in merkleBlock.transactions {
                if let existingTransaction = realm.objects(Transaction.self).filter("reversedHashHex = %@", transaction.reversedHashHex).first {
                    existingTransaction.block = block
                    existingTransaction.status = .relayed
                    continue
                }

                transactionProcessor.process(transaction: transaction, realm: realm)

                if transaction.isMine {
                    transaction.block = block
                    realm.add(transaction)

                    self.needToReDownload = self.needToReDownload || self.addressManager.gapShifts() || self.hasUnspentOutputs(transaction: transaction)
                }
            }
            
            if !self.needToReDownload, let blockHash = realm.objects(BlockHash.self).filter("headerHash = %@", block.headerHash).first {
                realm.delete(blockHash)
            }
        }
    }

    func shouldRequestBlock(withHash hash: Data) -> Bool {
        let realm = realmFactory.realm
        return realm.objects(Block.self).filter("headerHash == %@", hash).count == 0
    }

}
