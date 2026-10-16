// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {NightFrogs} from "../../src/NightFrogs.sol";
import {IVRFCoordinatorV2Plus} from "../../src/interfaces/IVRFCoordinatorV2Plus.sol";

/// @dev Local payment adversary only. Never a deployment application.
contract MockIMD is ERC20 {
    uint8 private tokenDecimals;
    bool public returnFalse;
    bool public omitReturn;
    bool public taxPull;
    bool public taxPush;
    bool public extraPullCharge;
    address public taxedRecipient;
    address public blockedRecipient;
    NightFrogs public reentryTarget;
    bool public reentrySucceeded;

    constructor() ERC20("Mock IMD", "IMD") {}

    function setDecimals(uint8 value) external {
        tokenDecimals = value;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function fund(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFalse(bool value) external {
        returnFalse = value;
    }

    function setNoReturn(bool value) external {
        omitReturn = value;
    }

    function setTaxes(bool pull, bool push) external {
        taxPull = pull;
        taxPush = push;
    }

    function setExtraPullCharge(bool value) external {
        extraPullCharge = value;
    }

    function setRecipientTax(address recipient) external {
        taxedRecipient = recipient;
    }

    function blockRecipient(address recipient) external {
        blockedRecipient = recipient;
    }

    function setReentry(NightFrogs target) external {
        reentryTarget = target;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _pay(from, to, amount, taxPull);
        if (extraPullCharge) _burn(from, 1);
        if (address(reentryTarget) != address(0)) {
            (reentrySucceeded,) = address(reentryTarget).call(abi.encodeWithSignature("mint(uint256)", 1));
        }
        if (omitReturn) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return !returnFalse;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _pay(msg.sender, to, amount, taxPush);
        if (omitReturn) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return !returnFalse;
    }

    function _pay(address from, address to, uint256 amount, bool taxed) private {
        require(to != blockedRecipient, "recipient blocked");
        uint256 fee = (taxed || to == taxedRecipient) ? amount / 10 : 0;
        _transfer(from, to, amount - fee);
        if (fee > 0) _burn(from, fee);
    }
}

contract MockCoordinator is IVRFCoordinatorV2Plus {
    bool public failRequest;
    uint256 public requests;
    uint256 public lastSub;
    bytes32 public lastKey;
    uint16 public lastConfirmations;
    uint32 public lastGas;
    uint32 public lastWords;
    bytes public lastExtra;
    address public consumer;

    function setFail(bool value) external {
        failRequest = value;
    }

    function requestRandomWords(RandomWordsRequest calldata req) external returns (uint256) {
        require(!failRequest, "subscription unfunded or consumer unregistered");
        consumer = msg.sender;
        lastSub = req.subId;
        lastKey = req.keyHash;
        lastConfirmations = req.requestConfirmations;
        lastGas = req.callbackGasLimit;
        lastWords = req.numWords;
        lastExtra = req.extraArgs;
        return ++requests;
    }

    function fulfill(NightFrogs nft, uint256 id, uint256[] memory words) external {
        nft.rawFulfillRandomWords(id, words);
    }

    function fulfillWithBudget(NightFrogs nft, uint256 id, uint256 word, uint256 budget)
        external
        returns (bool success, uint256 used)
    {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        uint256 beforeGas = gasleft();
        (success,) =
            address(nft).call{gas: budget}(abi.encodeCall(NightFrogs.rawFulfillRandomWords, (id, words)));
        used = beforeGas - gasleft();
    }
}

contract MintReceiver is IERC721Receiver {
    NightFrogs public immutable nft;
    MockIMD public immutable token;
    bool public reject;
    bool public reenter;
    bool public reentrySucceeded;
    uint256 public received;
    address public forwardTo;

    constructor(NightFrogs nft_, MockIMD token_) {
        nft = nft_;
        token = token_;
    }

    function configure(bool reject_, bool reenter_, address forwardTo_) external {
        reject = reject_;
        reenter = reenter_;
        forwardTo = forwardTo_;
    }

    function buy(uint256 n) external {
        token.approve(address(nft), n * nft.price());
        nft.mint(n);
    }

    function onERC721Received(address, address, uint256 id, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(nft));
        if (reject) return bytes4(0);
        ++received;
        if (reenter) (reentrySucceeded,) = address(nft).call(abi.encodeWithSignature("mint(uint256)", 1));
        if (forwardTo != address(0)) nft.transferFrom(address(this), forwardTo, id);
        return IERC721Receiver.onERC721Received.selector;
    }
}
