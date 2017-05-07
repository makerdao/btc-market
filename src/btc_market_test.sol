/*
Copyright 2016 rain <https://keybase.io/rain>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

pragma solidity ^0.4.11;

import 'ds-test/test.sol';
import 'ds-token/base.sol';

import 'btc-tx/btc_tx.sol';

import './btc_market.sol';

contract MockBTCRelay {
    function relayTx(bytes rawTransaction, int256 transactionIndex,
                     int256[] merkleSibling, int256 blockHash,
                     int256 contractAddress)
        returns (int256)
    {
        // see testRelayTx for full tx details
        bytes memory _txHash = "\x29\xc0\x2a\x5d\x57\x29\x30\xe6\xd3\xde\x6f\xad\x45\xbb\xfd\x8d\x1a\x73\x22\x0f\x86\xf1\xad\xf4\xcd\x1d\xe6\x33\x2c\x33\xac\x3c";
        var txHash = BTC.getBytesLE(_txHash, 0, 32);
        var processor = BitcoinProcessor(contractAddress);
        return processor.processTransaction(rawTransaction, txHash);
    }
}

contract MarketTester {
    address _t;
    function _target(address target) {
        _t = target;
    }
    function () {
        if(!_t.call(msg.data)) throw;
    }
    function doApprove(address who, uint how_much, ERC20 token) {
        token.approve(who, how_much);
    }
}

contract TestableBTCMarket is BTCMarket {
    uint _time;
    function TestableBTCMarket(MockBTCRelay relay, uint time_limit)
        BTCMarket(relay, time_limit) {}
    function getTime() constant returns (uint) {
        return _time;
    }
    function addTime(uint delta) {
        _time += delta;
    }
}

contract BTCMarketTest is DSTest {
    MarketTester user1;
    MarketTester user2;

    TestableBTCMarket otc;
    MockBTCRelay relay;

    ERC20 dai;
    ERC20 mkr;

    function setUp() {
        dai = new DSTokenBase(10 ** 6);
        mkr = new DSTokenBase(10 ** 6);

        relay = new MockBTCRelay();
        otc = new TestableBTCMarket(relay, 1 days);

        user1 = new MarketTester();
        user1._target(otc);
        user2 = new MarketTester();
        user2._target(otc);

        dai.transfer(user1, 100);
        user1.doApprove(otc, 100, dai);
        mkr.approve(otc, 30);
    }
    function testOfferBuyBitcoin() {
        bytes20 seller_btc_address = 0x123;
        var id = otc.offer(30, mkr, 10, seller_btc_address);
        assertEq(id, 1);
        assertEq(otc.last_offer_id(), id);

        var (sell_how_much, sell_which_token,
             buy_how_much, buy_which_token,,) = otc.getOffer(id);

        assertEq(sell_how_much, 30);
        assertEq(sell_which_token, mkr);

        assertEq(buy_how_much, 10);

        assertEq(otc.getBtcAddress(id), seller_btc_address);
    }
    function testOfferTransferFrom() {
        var my_mkr_balance_before = mkr.balanceOf(this);
        var id = otc.offer(30, mkr, 10, 0x11);
        var my_mkr_balance_after = mkr.balanceOf(this);

        var transferred = my_mkr_balance_before - my_mkr_balance_after;

        assertEq(transferred, 30);
    }
    function testBuyLocking() {
        var id = otc.offer(30, mkr, 10, 0x11);
        assert(!otc.isLocked(id));
        BTCMarket(user1).buy(id);
        assert(otc.isLocked(id));
    }
    function testCancelUnlocked() {
        var my_mkr_balance_before = mkr.balanceOf(this);
        var id = otc.offer(30, mkr, 10, 0x11);
        var my_mkr_balance_after = mkr.balanceOf(this);
        otc.cancel(id);
        var my_mkr_balance_after_cancel = mkr.balanceOf(this);

        var diff = my_mkr_balance_before - my_mkr_balance_after_cancel;
        assertEq(diff, 0);
    }
    function testFailCancelInactive() {
        var id = otc.offer(30, mkr, 10, 0x11);
        otc.cancel(id);
        otc.cancel(id);
    }
    function testFailCancelNonOwner() {
        var id = otc.offer(30, mkr, 10, 0x11);
        BTCMarket(user1).cancel(id);
    }
    function testFailCancelLocked() {
        var id = otc.offer(30, mkr, 10, 0x11);
        BTCMarket(user1).buy(id);
        otc.cancel(id);
    }
    function testFailBuyLocked() {
        var id = otc.offer(30, mkr, 10, 0x11);
        BTCMarket(user1).buy(id);
        BTCMarket(user2).buy(id);
    }
    function testConfirm() {
        // after calling `buy` and sending bitcoin, buyer should call
        // `confirm` to associate the offer with a bitcoin transaction hash
        var id = otc.offer(30, mkr, 10, 0x11);
        BTCMarket(user1).buy(id);

        assert(!otc.isConfirmed(id));
        var txHash = 1234;
        BTCMarket(user1).confirm(id, txHash);
        assert(otc.isConfirmed(id));
    }
    function testFailConfirmNonBuyer() {
        var id = otc.offer(30, mkr, 10, 0x11);
        BTCMarket(user1).buy(id);
        BTCMarket(user2).confirm(id, 123);
    }
    function testGetOfferByTxHash() {
        var id = otc.offer(30, mkr, 10, 0x11);
        BTCMarket(user1).buy(id);

        var txHash = 1234;
        BTCMarket(user1).confirm(id, txHash);
        assertEq(otc.getOfferByTxHash(txHash), id);
    }
    function testLinkedRelay() {
        assertEq(otc.getRelay(), relay);
    }
    function testRelayTxNoMatchingOrder() {
        var fail = _relayTx(relay);
        // return 1 => unsuccessful check.
        assertEq(fail, 1);
    }
    function testRelayTx() {
        // see _relayTx for associated transaction
        bytes memory _txHash = "\x29\xc0\x2a\x5d\x57\x29\x30\xe6\xd3\xde\x6f\xad\x45\xbb\xfd\x8d\x1a\x73\x22\x0f\x86\xf1\xad\xf4\xcd\x1d\xe6\x33\x2c\x33\xac\x3c";
        // convert hex txHash to uint
        var txHash = BTC.getBytesLE(_txHash, 0, 32);

        var id = otc.offer(30, mkr, 10, hex"8078624453510cd314398e177dcd40dff66d6f9e");
        BTCMarket(user1).buy(id);
        BTCMarket(user1).confirm(id, txHash);

        var success = _relayTx(relay);
        // return 0 => successful check.
        assertEq(success, 0);
    }
    function testRelayInsufficientTx() {
        // see _relayTx for associated transaction
        bytes memory _txHash = "\x29\xc0\x2a\x5d\x57\x29\x30\xe6\xd3\xde\x6f\xad\x45\xbb\xfd\x8d\x1a\x73\x22\x0f\x86\xf1\xad\xf4\xcd\x1d\xe6\x33\x2c\x33\xac\x3c";
        // convert hex txHash to uint
        var txHash = BTC.getBytesLE(_txHash, 0, 32);

        var id_not_enough = otc.offer(30, mkr, 10, hex"1e6022990700109cb82692bb12085381087d5cea");
        BTCMarket(user1).buy(id_not_enough);
        BTCMarket(user1).confirm(id_not_enough, txHash);

        var not_enough = _relayTx(relay);
        assertEq(not_enough, 1);
    }
    function testRelayTxTransfers() {
        // see _relayTx for associated transaction
        bytes memory _txHash = "\x29\xc0\x2a\x5d\x57\x29\x30\xe6\xd3\xde\x6f\xad\x45\xbb\xfd\x8d\x1a\x73\x22\x0f\x86\xf1\xad\xf4\xcd\x1d\xe6\x33\x2c\x33\xac\x3c";
        // convert hex txHash to uint
        var txHash = BTC.getBytesLE(_txHash, 0, 32);

        var my_mkr_balance_before = mkr.balanceOf(this);
        var id = otc.offer(30, mkr, 10, hex"8078624453510cd314398e177dcd40dff66d6f9e");
        BTCMarket(user1).buy(id);
        BTCMarket(user1).confirm(id, txHash);

        var user1_mkr_balance_before = mkr.balanceOf(user1);
        var success = _relayTx(relay);
        var user1_mkr_balance_after = mkr.balanceOf(user1);
        var my_mkr_balance_after = mkr.balanceOf(this);

        // return 0 => successful check.
        assertEq(success, 0);

        var my_balance_diff = my_mkr_balance_before - my_mkr_balance_after;
        assertEq(my_balance_diff, 30);

        var balance_diff = user1_mkr_balance_after - user1_mkr_balance_before;
        assertEq(balance_diff, 30);

        // offer should be deleted
        var (w, x, y, z,,) = otc.getOffer(id);
        assertEq(w, 0);
        assertEq(y, 0);
    }
    function testFailRelayTxNonTrusted() {
        // see _relayTx for associated transaction
        bytes memory _txHash = "\x29\xc0\x2a\x5d\x57\x29\x30\xe6\xd3\xde\x6f\xad\x45\xbb\xfd\x8d\x1a\x73\x22\x0f\x86\xf1\xad\xf4\xcd\x1d\xe6\x33\x2c\x33\xac\x3c";
        // convert hex txHash to uint
        var txHash = BTC.getBytesLE(_txHash, 0, 32);

        var id = otc.offer(30, mkr, 10, hex"8078624453510cd314398e177dcd40dff66d6f9e");
        BTCMarket(user1).buy(id);
        BTCMarket(user1).confirm(id, txHash);

        var untrusted_relay = new MockBTCRelay();
        // this should fail
        var success = _relayTx(untrusted_relay);
    }
    function _relayTx(MockBTCRelay relay) returns (int256) {
        // txid: 29c02a5d572930e6d3de6fad45bbfd8d1a73220f86f1adf4cd1de6332c33ac3c
        // txid literal: \x29\xc0\x2a\x5d\x57\x29\x30\xe6\xd3\xde\x6f\xad\x45\xbb\xfd\x8d\x1a\x73\x22\x0f\x86\xf1\xad\xf4\xcd\x1d\xe6\x33\x2c\x33\xac\x3c
        // value: 12345678
        // value: 11223344
        // address: 1CiHhyL4BuD21EJYJBFfUgRKyjPGgB3pVd
        // address: 1LG1HY5P53rkUwcwaXAxx1432UDCyfVq9M
        // script: OP_DUP OP_HASH160 8078624453510cd314398e177dcd40dff66d6f9e OP_EQUALVERIFY OP_CHECKSIG
        // script: OP_DUP OP_HASH160 d340de07e3d72fe70c2d18493e6e3d4c4a3f4ce3 OP_EQUALVERIFY OP_CHECKSIG
        // hex: 0100000001a58cbbcbad45625f5ed1f20458f393fe1d1507e254265f09d9746232da4800240000000000ffffffff024e61bc00000000001976a9148078624453510cd314398e177dcd40dff66d6f9e88ac3041ab00000000001976a914d340de07e3d72fe70c2d18493e6e3d4c4a3f4ce388ac00000000
        // hex literal: \x01\x00\x00\x00\x01\xa5\x8c\xbb\xcb\xad\x45\x62\x5f\x5e\xd1\xf2\x04\x58\xf3\x93\xfe\x1d\x15\x07\xe2\x54\x26\x5f\x09\xd9\x74\x62\x32\xda\x48\x00\x24\x00\x00\x00\x00\x00\xff\xff\xff\xff\x02\x4e\x61\xbc\x00\x00\x00\x00\x00\x19\x76\xa9\x14\x80\x78\x62\x44\x53\x51\x0c\xd3\x14\x39\x8e\x17\x7d\xcd\x40\xdf\xf6\x6d\x6f\x9e\x88\xac\x30\x41\xab\x00\x00\x00\x00\x00\x19\x76\xa9\x14\xd3\x40\xde\x07\xe3\xd7\x2f\xe7\x0c\x2d\x18\x49\x3e\x6e\x3d\x4c\x4a\x3f\x4c\xe3\x88\xac\x00\x00\x00\x00

        bytes memory mockBytes = "\x01\x00\x00\x00\x01\xa5\x8c\xbb\xcb\xad\x45\x62\x5f\x5e\xd1\xf2\x04\x58\xf3\x93\xfe\x1d\x15\x07\xe2\x54\x26\x5f\x09\xd9\x74\x62\x32\xda\x48\x00\x24\x00\x00\x00\x00\x00\xff\xff\xff\xff\x02\x4e\x61\xbc\x00\x00\x00\x00\x00\x19\x76\xa9\x14\x80\x78\x62\x44\x53\x51\x0c\xd3\x14\x39\x8e\x17\x7d\xcd\x40\xdf\xf6\x6d\x6f\x9e\x88\xac\x30\x41\xab\x00\x00\x00\x00\x00\x19\x76\xa9\x14\xd3\x40\xde\x07\xe3\xd7\x2f\xe7\x0c\x2d\x18\x49\x3e\x6e\x3d\x4c\x4a\x3f\x4c\xe3\x88\xac\x00\x00\x00\x00";
        int256 txIndex = 100;
        int256[] memory siblings;
        int256 blockHash = 100;
        int256 contractAddress = int256(otc);

        return relay.relayTx(mockBytes, txIndex, siblings, blockHash, contractAddress);
    }
    function _relayInsufficientTx() returns (int256) {
        // txid: 75da54d7977ddbc27ac35df9a37e2b93173e854c488e5cdf833e3d848e5860fa
        // txid literal: \x75\xda\x54\xd7\x97\x7d\xdb\xc2\x7a\xc3\x5d\xf9\xa3\x7e\x2b\x93\x17\x3e\x85\x4c\x48\x8e\x5c\xdf\x83\x3e\x3d\x84\x8e\x58\x60\xfa
        // value: 1
        // value: 11223344
        // address: 13mcSLqhYjyxK4aeQw7t2fZnngujwrmg3a
        // address: 1Hs8vQQ5FBRSFoFD6bvwWAaLUHthc4ZQkz
        // script: OP_DUP OP_HASH160 1e6022990700109cb82692bb12085381087d5cea OP_EQUALVERIFY OP_CHECKSIG
        // script: OP_DUP OP_HASH160 b8fd6c2b6f03e13de00a0e791a0b23fc1ba0f685 OP_EQUALVERIFY OP_CHECKSIG
        // hex: 0100000001a58cbbcbad45625f5ed1f20458f393fe1d1507e254265f09d9746232da4800240000000000ffffffff0201000000000000001976a9141e6022990700109cb82692bb12085381087d5cea88ac3041ab00000000001976a914b8fd6c2b6f03e13de00a0e791a0b23fc1ba0f68588ac00000000
        // hex literal: \x01\x00\x00\x00\x01\xa5\x8c\xbb\xcb\xad\x45\x62\x5f\x5e\xd1\xf2\x04\x58\xf3\x93\xfe\x1d\x15\x07\xe2\x54\x26\x5f\x09\xd9\x74\x62\x32\xda\x48\x00\x24\x00\x00\x00\x00\x00\xff\xff\xff\xff\x02\x01\x00\x00\x00\x00\x00\x00\x00\x19\x76\xa9\x14\x1e\x60\x22\x99\x07\x00\x10\x9c\xb8\x26\x92\xbb\x12\x08\x53\x81\x08\x7d\x5c\xea\x88\xac\x30\x41\xab\x00\x00\x00\x00\x00\x19\x76\xa9\x14\xb8\xfd\x6c\x2b\x6f\x03\xe1\x3d\xe0\x0a\x0e\x79\x1a\x0b\x23\xfc\x1b\xa0\xf6\x85\x88\xac\x00\x00\x00\x00

        bytes memory mockBytes = "\x01\x00\x00\x00\x01\xa5\x8c\xbb\xcb\xad\x45\x62\x5f\x5e\xd1\xf2\x04\x58\xf3\x93\xfe\x1d\x15\x07\xe2\x54\x26\x5f\x09\xd9\x74\x62\x32\xda\x48\x00\x24\x00\x00\x00\x00\x00\xff\xff\xff\xff\x02\x01\x00\x00\x00\x00\x00\x00\x00\x19\x76\xa9\x14\x1e\x60\x22\x99\x07\x00\x10\x9c\xb8\x26\x92\xbb\x12\x08\x53\x81\x08\x7d\x5c\xea\x88\xac\x30\x41\xab\x00\x00\x00\x00\x00\x19\x76\xa9\x14\xb8\xfd\x6c\x2b\x6f\x03\xe1\x3d\xe0\x0a\x0e\x79\x1a\x0b\x23\xfc\x1b\xa0\xf6\x85\x88\xac\x00\x00\x00\x00";
        int256 txIndex = 100;
        int256[] memory siblings;
        int256 blockHash = 100;
        int256 contractAddress = int256(otc);

        return relay.relayTx(mockBytes, txIndex, siblings, blockHash, contractAddress);
    }
    function testDeposit() {
        // create an offer requiring a 5 DAI deposit
        var id = otc.offer(30, mkr, 10, hex"8078624453510cd314398e177dcd40dff66d6f9e", 5, dai);

        // check deposit is taken when user places order
        dai.transfer(user1, 100);
        user1.doApprove(otc, 100, dai);
        var user_dai_balance_before_buy = dai.balanceOf(user1);
        BTCMarket(user1).buy(id);
        var user_dai_balance_after_buy = dai.balanceOf(user1);

        var user_buy_diff = user_dai_balance_before_buy - user_dai_balance_after_buy;
        assertEq(user_buy_diff, 5);

        bytes memory _txHash = "\x29\xc0\x2a\x5d\x57\x29\x30\xe6\xd3\xde\x6f\xad\x45\xbb\xfd\x8d\x1a\x73\x22\x0f\x86\xf1\xad\xf4\xcd\x1d\xe6\x33\x2c\x33\xac\x3c";
        var txHash = BTC.getBytesLE(_txHash, 0, 32);

        BTCMarket(user1).confirm(id, txHash);

        // check deposit refunded when user relays good tx */
        var success = _relayTx(relay);
        assertEq(success, 0);
        var user_dai_balance_after_relay = dai.balanceOf(user1);
        assertEq(user_dai_balance_after_relay, user_dai_balance_before_buy);
    }
    function testClaim() {
        // create an offer requiring a 5 DAI deposit
        var id = otc.offer(30, mkr, 10, hex"8078624453510cd314398e177dcd40dff66d6f9e", 5, dai);

        dai.transfer(user1, 5);
        user1.doApprove(otc, 5, dai);
        BTCMarket(user1).buy(id);

        otc.addTime(2 days);

        var dai_before = dai.balanceOf(this);
        otc.claim(id);
        assertEq(dai.balanceOf(this) - dai_before, 5);
    }
    function testCancelAfterClaim() {
        // create an offer requiring a 5 DAI deposit
        var id = otc.offer(30, mkr, 10, hex"8078624453510cd314398e177dcd40dff66d6f9e", 5, dai);

        dai.transfer(user1, 5);
        user1.doApprove(otc, 5, dai);
        BTCMarket(user1).buy(id);

        otc.addTime(2 days);

        otc.claim(id);

        var mkr_before = mkr.balanceOf(this);
        otc.cancel(id);
        assertEq(mkr.balanceOf(this) - mkr_before, 30);
    }
    function testFailClaimBeforeElapsed() {
        // create an offer requiring a 5 DAI deposit
        var id = otc.offer(30, mkr, 10, hex"8078624453510cd314398e177dcd40dff66d6f9e", 5, dai);

        dai.transfer(user1, 5);
        user1.doApprove(otc, 5, dai);
        BTCMarket(user1).buy(id);

        otc.claim(id);
    }
}
