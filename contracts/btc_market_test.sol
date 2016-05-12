import 'maker-user/user_test.sol';
import 'btc_market.sol';

contract MockBTCRelay {
    function relayTx(bytes rawTransaction, int256 transactionIndex,
                     int256[] merkleSibling, int256 blockHash,
                     int256 contractAddress)
        returns (int256)
    {
        uint256 txHash = 1234;
        var processor = MockProcessor(contractAddress);
        return processor.processTransaction(rawTransaction, txHash);
    }
}

contract MockProcessor {
    function processTransaction(bytes txBytes, uint256 txHash)
        returns (int256) {}
}

contract BTCMarketTest is Test
                           , MakerUserGeneric(new MakerUserMockRegistry())
                           , EventfulMarket
{
    MakerUserTester user1;
    MakerUserTester user2;
    BTCMarket otc;
    MockBTCRelay relay;

    function setUp() {
        relay = new MockBTCRelay();
        otc = new BTCMarket(_M, relay);
        user1 = new MakerUserTester(_M);
        user1._target(otc);
        user2 = new MakerUserTester(_M);
        user2._target(otc);
        transfer(user1, 100, "DAI");
        user1.doApprove(otc, 100, "DAI");
        approve(otc, 30, "MKR");
    }
    function testOfferBuyBitcoin() {
        bytes20 seller_btc_address = 0x123;
        var id = otc.offer(30, "MKR", 10, "BTC", seller_btc_address);
        assertEq(id, 1);
        assertEq(otc.last_offer_id(), id);

        var (sell_how_much, sell_which_token,
             buy_how_much, buy_which_token) = otc.getOffer(id);

        assertEq(sell_how_much, 30);
        assertEq32(sell_which_token, "MKR");

        assertEq(buy_how_much, 10);
        assertEq32(buy_which_token, "BTC");

        assertEq20(otc.getBtcAddress(id), seller_btc_address);
    }
    function testFailOfferSellBitcoin() {
        otc.offer(30, "BTC", 10, "MKR", 0x11);
    }
    function testFailOfferBuyNotBitcoin() {
        otc.offer(30, "MKR", 10, "DAI", 0x11);
    }
    function testOfferTransferFrom() {
        var my_mkr_balance_before = balanceOf(this, "MKR");
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        var my_mkr_balance_after = balanceOf(this, "MKR");

        var transferred = my_mkr_balance_before - my_mkr_balance_after;

        assertEq(transferred, 30);
    }
    function testBuyLocking() {
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        assertEq(otc.isLocked(id), false);
        BTCMarket(user1).buy(id);
        assertEq(otc.isLocked(id), true);
    }
    function testCancelUnlocked() {
        var my_mkr_balance_before = balanceOf(this, "MKR");
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        var my_mkr_balance_after = balanceOf(this, "MKR");
        otc.cancel(id);
        var my_mkr_balance_after_cancel = balanceOf(this, "MKR");

        var diff = my_mkr_balance_before - my_mkr_balance_after_cancel;
        assertEq(diff, 0);
    }
    function testFailCancelInactive() {
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        otc.cancel(id);
        otc.cancel(id);
    }
    function testFailCancelNonOwner() {
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        BTCMarket(user1).cancel(id);
    }
    function testFailCancelLocked() {
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        BTCMarket(user1).buy(id);
        otc.cancel(id);
    }
    function testFailBuyLocked() {
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        BTCMarket(user1).buy(id);
        BTCMarket(user2).buy(id);
    }
    function testConfirm() {
        // after calling `buy` and sending bitcoin, buyer should call
        // `confirm` to associate the offer with a bitcoin transaction hash
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        BTCMarket(user1).buy(id);

        assertEq(otc.isConfirmed(id), false);
        var txHash = 1234;
        BTCMarket(user1).confirm(id, txHash);
        assertEq(otc.isConfirmed(id), true);
    }
    function testFailConfirmNonBuyer() {
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        BTCMarket(user1).buy(id);
        BTCMarket(user2).confirm(id, 123);
    }
    function testGetOfferByTxHash() {
        var id = otc.offer(30, "MKR", 10, "BTC", 0x11);
        BTCMarket(user1).buy(id);

        var txHash = 1234;
        BTCMarket(user1).confirm(id, txHash);
        assertEq(otc.getOfferByTxHash(txHash), id);
    }
    function testLinkedRelay() {
        assertEq(otc.getRelay(), relay);
    }
    function testRelayTx() {
        bytes memory mockBytes = "\x11\x22";
        int256 txIndex = 100;
        int256[] memory siblings;
        int256 blockHash = 100;
        int256 contractAddress = int256(otc);
        var ret = relay.relayTx(mockBytes, txIndex, siblings, blockHash, contractAddress);
        assertEq(ret, 1);
    }
}
