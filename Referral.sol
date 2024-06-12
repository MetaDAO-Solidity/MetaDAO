
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts@4.9.0/utils/Address.sol";
import "@openzeppelin/contracts@4.9.0/access/AccessControl.sol";
import "@openzeppelin/contracts@4.9.0/security/Pausable.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/utils/SafeERC20.sol";

contract MetaDAOReferral is AccessControl, Pausable {
    using SafeERC20 for IERC20;


    struct Account {
        address referrer;
        uint24 referredCount;
        uint32 lastActiveTimestamp;
    }


    struct RefereeBonusRate {
        uint16 lowerBound;
        uint16 rate;
    }

    uint16[3] public levelRate;

   
    uint24 public secondsUntilInactive;

   
    bool public onlyRewardActiveReferrers;


    RefereeBonusRate[3] public refereeBonusRateMap;

 
    mapping(address => mapping(address => uint256)) private _credits;

   
    mapping(address => Account) private _accounts;

  
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    bytes32 public constant BANK_ROLE = keccak256("BANK_ROLE");


    event SetReferral(
        uint24 secondsUntilInactive,
        bool onlyRewardActiveReferrers,
        uint16[3] levelRate
    );


    event SetReferreeBonusRate(uint16 lowerBound, uint16 rate);


    event RegisteredReferer(address indexed referee, address indexed referrer);


    event SetLastActiveTimestamp(
        address indexed referrer,
        uint32 lastActiveTimestamp
    );

        address indexed user,
        address indexed token,
        uint256 amount,
        uint16 indexed level
    );

    event WithdrawnReferralCredit(
        address indexed payee,
        address indexed token,
        uint256 amount
    );


    error WrongLevelRate();

    error WrongRefereeBonusRate(uint16 rate);


    constructor(
        uint24 _secondsUntilInactive,
        bool _onlyRewardActiveReferrers,
        uint16[3] memory _levelRate,
        uint16[6] memory _refereeBonusRateMap
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        setReferral(
            _secondsUntilInactive,
            _onlyRewardActiveReferrers,
            _levelRate,
            _refereeBonusRateMap
        );
    }

    receive() external payable {}

    function _getRefereeBonusRate(uint24 referredCount)
        private
        view
        returns (uint16)
    {
        uint16 rate = refereeBonusRateMap[0].rate;
        uint256 refereeBonusRateMapLength = refereeBonusRateMap.length;
        for (uint8 i = 1; i < refereeBonusRateMapLength; i++) {
            RefereeBonusRate memory refereeBonusRate = refereeBonusRateMap[i];
            if (referredCount < refereeBonusRate.lowerBound) {
                break;
            }
            rate = refereeBonusRate.rate;
        }
        return rate;
    }



    function _isCircularReference(address referrer, address referee)
        private
        view
        returns (bool)
    {
        address parent = referrer;
        uint256 levelRateLength = levelRate.length;
        for (uint8 i; i < levelRateLength; i++) {
            if (parent == address(0)) {
                break;
            }

            if (parent == referee) {
                return true;
            }

            parent = _accounts[parent].referrer;
        }

        return false;
    }


    function setReferral(
        uint24 _secondsUntilInactive,
        bool _onlyRewardActiveReferrers,
        uint16[3] memory _levelRate,
        uint16[6] memory _refereeBonusRateMap
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 levelRateTotal;
        uint256 levelRateLength = _levelRate.length;
        for (uint8 i; i < levelRateLength; i++) {
            levelRateTotal += _levelRate[i];
        }
        if (levelRateTotal > 10000) {
            revert WrongLevelRate();
        }

        secondsUntilInactive = _secondsUntilInactive;
        onlyRewardActiveReferrers = _onlyRewardActiveReferrers;
        levelRate = _levelRate;

        emit SetReferral(
            secondsUntilInactive,
            onlyRewardActiveReferrers,
            levelRate
        );

        uint8 j;
        uint256 refereeBonusRateMapLength = _refereeBonusRateMap.length;
        for (uint8 i; i < refereeBonusRateMapLength; i += 2) {
            uint16 refereeBonusLowerBound = _refereeBonusRateMap[i];
            uint16 refereeBonusRate = _refereeBonusRateMap[i + 1];
            if (refereeBonusRate > 10000) {
                revert WrongRefereeBonusRate(refereeBonusRate);
            }
            refereeBonusRateMap[j] = RefereeBonusRate(
                refereeBonusLowerBound,
                refereeBonusRate
            );
            emit SetReferreeBonusRate(refereeBonusLowerBound, refereeBonusRate);
            j++;
        }
    }

    function addReferrer(address user, address referrer)
        external
        onlyRole(GAME_ROLE)
    {
        if (referrer == address(0)) {
            // Referrer cannot be 0x0 address
            return;
        } else if (_isCircularReference(referrer, user)) {
            // Referee cannot be one of referrer uplines
            return;
        } else if (_accounts[user].referrer != address(0)) {
            // Address have been registered upline
            return;
        }

        Account storage userAccount = _accounts[user];
        Account storage parentAccount = _accounts[referrer];

        userAccount.referrer = referrer;
        userAccount.lastActiveTimestamp = uint32(block.timestamp);
        parentAccount.referredCount += 1;

        emit RegisteredReferer(user, referrer);
    }

    function payReferral(
        address user,
        address token,
        uint256 amount
    ) external onlyRole(BANK_ROLE) returns (uint256) {
        uint256 totalReferral;
        Account memory userAccount = _accounts[user];

        if (userAccount.referrer != address(0)) {
            uint256 levelRateLength = levelRate.length;
            for (uint8 i; i < levelRateLength; i++) {
                address parent = userAccount.referrer;
                Account memory parentAccount = _accounts[parent];

                if (parent == address(0)) {
                    break;
                }

                if (
                    !onlyRewardActiveReferrers ||
                    (parentAccount.lastActiveTimestamp + secondsUntilInactive >=
                        block.timestamp)
                ) {
                    uint256 credit = (((amount * levelRate[i]) / 10000) *
                        _getRefereeBonusRate(parentAccount.referredCount)) /
                        10000;
                    totalReferral += credit;

                    _credits[parent][token] += credit;

                    emit AddReferralCredit(parent, token, credit, i + 1);
                }

                userAccount = parentAccount;
            }
        }
        return totalReferral;
    }


    function updateReferrerActivity(address user) external onlyRole(GAME_ROLE) {
        Account storage userAccount = _accounts[user];
        if (userAccount.referredCount > 0) {
            uint32 lastActiveTimestamp = uint32(block.timestamp);
            userAccount.lastActiveTimestamp = lastActiveTimestamp;
            emit SetLastActiveTimestamp(user, lastActiveTimestamp);
        }
    }


    function withdrawCredits(address[] calldata tokens) external {
        address payable payee = payable(msg.sender);
        for (uint8 i; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 credit = _credits[payee][token];
            if (credit > 0) {
                _credits[payee][token] = 0;

                if (token == address(0)) {
                    Address.sendValue(payee, credit);
                } else {
                    IERC20(token).safeTransfer(payee, credit);
                }

                emit WithdrawnReferralCredit(payee, token, credit);
            }
        }
    }


    function hasReferrer(address user) external view returns (bool) {
        return _accounts[user].referrer != address(0);
    }


    function referralCreditOf(address payee, address token)
        external
        view
        returns (uint256)
    {
        return _credits[payee][token];
    }

    function getReferralAccount(address user)
        external
        view
        returns (Account memory)
    {
        return _accounts[user];
    }
}
