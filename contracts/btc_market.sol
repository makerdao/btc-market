import 'erc20/erc20.sol';
import 'btc-tx/btc_tx.sol';

// BTC-relay integration

// Contracts that use btc-relay need to conform to the BitcoinProcessor API.
contract BitcoinProcessor {
    // called after successful relayTx call on relay contract
    function processTransaction(bytes txBytes, uint256 txHash) returns (int256);
}

contract BTCMarket is BitcoinProcessor {
    struct OfferInfo {
        uint sell_how_much;
        ERC20 sell_which_token;

        uint buy_how_much;

        uint deposit_how_much;
        ERC20 deposit_which_token;

        address owner;
        bool active;

        bytes20 btc_address;
        address buyer;
        uint256 confirmed;
    }
    uint public last_offer_id;
    mapping( uint => OfferInfo ) public offers;
    mapping( uint256 => uint) public offersByTxHash;

    address public trustedRelay;

    function () {
        throw;
    }

    function assert(bool condition) internal {
        if (!condition) throw;
    }

    modifier only_unlocked(uint id) {
        assert(!isLocked(id));
        _
    }

    modifier only_buyer(uint id) {
        assert(msg.sender == getBuyer(id));
        _
    }

    modifier only_owner(uint id) {
        assert(msg.sender == getOwner(id));
        _
    }

    modifier only_relay() {
        assert(msg.sender == trustedRelay);
        _
    }

    modifier only_active(uint id) {
        assert(isActive(id));
        _
    }

    function BTCMarket( address BTCRelay)
    {
        trustedRelay = BTCRelay;
    }

    function next_id() internal returns (uint) {
        last_offer_id++; return last_offer_id;
    }
    function offer( uint sell_how_much, ERC20 sell_which_token,
                    uint buy_how_much_btc, bytes20 btc_address )
        returns (uint id)
    {
        return offer(sell_how_much, sell_which_token,
                     buy_how_much_btc, btc_address,
                     0, sell_which_token);
    }
    function offer( uint sell_how_much, ERC20 sell_which_token,
                    uint buy_how_much_btc, bytes20 btc_address,
                    uint deposit_how_much, ERC20 deposit_which_token)
        returns (uint id)
    {
        assert(sell_how_much > 0);
        assert(address(sell_which_token) != 0x0);
        assert(buy_how_much_btc > 0);

        sell_which_token.transferFrom( msg.sender, this, sell_how_much);

        OfferInfo memory info;
        info.sell_how_much = sell_how_much;
        info.sell_which_token = sell_which_token;

        info.buy_how_much = buy_how_much_btc;
        info.btc_address = btc_address;

        info.deposit_how_much = deposit_how_much;
        info.deposit_which_token = deposit_which_token;

        info.owner = msg.sender;
        info.active = true;
        id = next_id();
        offers[id] = info;
        return id;
    }
    function buy (uint id) only_unlocked(id) only_active(id) {
        var offer = offers[id];
        offer.buyer = msg.sender;
        offer.deposit_which_token.transferFrom( msg.sender, this, offer.deposit_how_much);
    }
    function cancel(uint id) only_unlocked(id) only_owner(id) only_active(id) {
        OfferInfo memory offer = offers[id];
        delete offers[id];
        offer.sell_which_token.transfer(offer.owner, offer.sell_how_much);
    }
    function confirm(uint id, uint256 txHash) only_buyer(id) {
        var offer = offers[id];
        offer.confirmed = txHash;
        offersByTxHash[txHash] = id;
    }
    function processTransaction(bytes txBytes, uint256 txHash) only_relay
        returns (int256)
    {
        var id = offersByTxHash[txHash];
        OfferInfo memory offer = offers[id];

        var sent = BTC.checkValueSent(txBytes,
                                      offer.btc_address,
                                      offer.buy_how_much);

        if (sent) {
            delete offers[id];
            offer.sell_which_token.transfer(offer.buyer, offer.sell_how_much);
            offer.deposit_which_token.transfer(offer.buyer, offer.deposit_how_much);
            return 0;
        } else {
            return 1;
        }
    }
    function getOffer( uint id ) constant
        returns (uint, ERC20, uint, bytes20) {
      var offer = offers[id];
      return (offer.sell_how_much, offer.sell_which_token,
              offer.buy_how_much, offer.btc_address);
    }
    function getBtcAddress( uint id ) constant returns (bytes20) {
        var offer = offers[id];
        return offer.btc_address;
    }
    function getOfferByTxHash( uint256 txHash ) returns (uint id) {
        return offersByTxHash[txHash];
    }
    function getRelay() returns (address) {
        return trustedRelay;
    }
    function isLocked( uint id ) constant returns (bool) {
        var offer = offers[id];
        return (offer.buyer != 0x00);
    }
    function getBuyer(uint id) constant returns (address) {
        var offer = offers[id];
        return offer.buyer;
    }
    function isConfirmed( uint id ) constant returns (bool) {
        var offer = offers[id];
        return (offer.confirmed != 0);
    }
    function getOwner(uint id) constant returns (address) {
        var offer = offers[id];
        return offer.owner;
    }
    function isActive(uint id) constant returns (bool) {
        var offer = offers[id];
        return offer.active;
    }
}
