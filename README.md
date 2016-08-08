# Bitcoin <-> Token market

Trade Bitcoin for Standard Tokens on Ethereum.

## Usage

Alice wants to sell some ETH for bitcoins. She will accept delivery
at her bitcoin address `1SendBitcoinsHerePlease`.

Alice makes an offer to trade ether for bitcoins:

```
var id = market.offer(30, eth, 10, 1SendBitcoinsHerePlease)
```

This transfers 30 ETH from Alice to escrow in the market.

Alice can cancel her offer:

```
market.cancel(id)
```

This will return Alice's 30 ETH and delete her offer.

Bob has some bitcoins and wants to buy some ETH. He commits to buy
Alice's offer:

```
market.buy(id)
```

Alice can no longer cancel her offer. Bob now has 1 day to send
the required bitcoin to Alice's address.


Bob now has a two step verification process to assert that he has
sent his bitcoins. First he needs to tell the market the bitcoin transaction
hash that he used to send the bitcoins:

```
market.confirm(id, bobs_tx_hash)
```

Then he needs to verify this transaction by calling btc-relay:

```
relay.relayTx(rawTx, txIndex, merkleSibling, blockHash, address(market))
```

Note that the relay needs to know quite a few details of the
transaction. If the transaction is valid (which currently means
having > 6 confirmations), then the market will be notified and Bob
will receive his ETH.

If Bob does not relay his transaction within 1 day then Alice's
offer to pay Bob will be voided and the offer will be unlocked.
