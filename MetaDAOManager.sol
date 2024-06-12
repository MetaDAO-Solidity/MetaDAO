
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "../../node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "solmate/src/utils/ReentrancyGuard.sol";
import "../interfaces/core/IManager.sol";
import "../interfaces/tokens/IMTD.sol";
import "./AccessControlBase.sol";
import "../interfaces/strategies/IMiningStrategy.sol";
import "../interfaces/strategies/IFeeStrategy.sol";
import "../interfaces/stakings/IStaking.sol";
import "../interfaces/referrals/IReferralStorage.sol";
import "../tokens/MTD/interfaces/IBasicMTD.sol";

contract MetaDAOManager is AccessControlBase, ReentrancyGuard {
	using SafeERC20 for IMTD;
	using SafeERC20 for IERC20;
	event Converted(address indexed account, uint256 amount);
	event StrategiesSet(
		IMiningStrategy indexed miningStrategyAddress,
		IFeeStrategy indexed feeStrategyAddress
	);
	event TokensSet(IMTD indexed MTD, IMTD indexed vMTDAddress);
	event MTDStakingSet(IMTDStaking indexed MTDStakingAddress);
	event ReferralStorageSet(IReferralStorage indexed referralStorageAddress);
	
	IMTD public immutable MTD;
	IMTD public immutable vMTD;
	IBasicFDT public immutable MLP;
	IMTDStaking public MTDStaking;
	IReferralStorage public referralStorage;
	IMiningStrategy public miningStrategy;
	IFeeStrategy public feeStrategy;
	uint256 public mintedByGames;
	uint256 public immutable MAX_MINT;
	uint256 public totalConverted;
	uint256 public sendableAmount;
	uint256 public accumFee;
	uint256 public mintDivider;
	uint256 private constant BASIS_POINTS = 10000;
	constructor(
		IMTD _MTD,
		IMTD _vMTD,
		IBasicFDT _MLP,
		uint256 _maxMint,
		address _vaultRegistry,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) {
		MTD = _MTD;
		vMTD = _vMTD;
		MLP = _MLP;
		MAX_MINT = _maxMint;
		mintDivider = 4;
	}

	function setStrategies(
		IMiningStrategy _miningStrategy,
		IFeeStrategy _feeStrategy
	) external onlyGovernance {
		miningStrategy = _miningStrategy;
		feeStrategy = _feeStrategy;

		emit StrategiesSet(miningStrategy, feeStrategy);
	}

	function setMTDStaking(IMTDStaking _MTDStaking) external onlyGovernance {
		require(address(_MTDStaking) != address(0), "address can not be zero");
		MTDStaking = _MTDStaking;
		emit MTDStakingSet(MTDStaking);
	}

	function setReferralStorage(IReferralStorage _referralStorage) external onlyGovernance {
		referralStorage = _referralStorage;

		emit ReferralStorageSet(referralStorage);
	}

	function setMintDivider(uint256 _mintDivider) external onlyGovernance {
		mintDivider = _mintDivider;
	}

	function takeVestedMTD(address _from, uint256 _amount) external nonReentrant onlyProtocol {
		vMTD.safeTransferFrom(_from, address(this), _amount);
	}

	function takeMTD(address _from, uint256 _amount) external nonReentrant onlyProtocol {
		MTD.safeTransferFrom(_from, address(this), _amount);
	}

	function sendVestedMTD(address _to, uint256 _amount) external nonReentrant onlyProtocol {
		vMTD.safeTransfer(_to, _amount);
	}

	function sendMTD(address _to, uint256 _amount) external nonReentrant onlyProtocol {
		_sendMTD(_to, _amount);
	}


	function mintMTD(address _to, uint256 _amount) external nonReentrant onlyProtocol {
		_mintMTD(_to, _amount);
	}


	function burnVestedMTD(uint256 _amount) external nonReentrant onlyProtocol {
		vMTD.burn(_amount);
	}

	function burnMTD(uint256 _amount) external nonReentrant onlyProtocol {
		MTD.burn(_amount);
	}

	function mintOrTransferByPool(
		address _to,
		uint256 _amount
	) external nonReentrant onlyProtocol {
		if (sendableAmount >= _amount) {
			sendableAmount -= _amount;
			_sendMTD(_to, _amount);
		} else {
			_mintMTD(_to, _amount);
		}
	}

	function sendMLP(address _to, uint256 _amount) external nonReentrant onlyProtocol {
		IERC20(MLP).safeTransfer(_to, _amount);
	}

	function _mintMTD(address _to, uint256 _amount) internal {
		MTD.mint(_to, _amount);
	}

	function _sendMTD(address _to, uint256 _amount) internal {
		MTD.safeTransfer(_to, _amount);
	}

	function share(uint256 amount) external nonReentrant onlyProtocol {
		MTDStaking.share(amount);
	}

	function convertToken(uint256 _amount) external nonReentrant {
	
		MTD.safeTransferFrom(msg.sender, address(this), _amount);
		
		vMTD.mint(msg.sender, _amount);
	
		totalConverted += _amount;

		sendableAmount += _amount;

		emit Converted(msg.sender, _amount);
	}

	function mintVestedMTD(
		address _input,
		uint256 _amount,
		address _recipient
	) external nonReentrant onlyProtocol returns(uint256 _mintAmount){
		
		uint256 _feeAmount = feeStrategy.calculate(_input, _amount);
		_mintAmount = miningStrategy.calculate(_recipient, _feeAmount, mintedByGames);
	
		uint256 _vMTDRate = referralStorage.getPlayerVestedMTDRate(_recipient);
		
		if (_vMTDRate > 0) {
			_mintAmount += (_mintAmount * _vMTDRate) / BASIS_POINTS;
		}
    	
    	if (mintedByGames + _mintAmount > MAX_MINT) {
        	_mintAmount = MAX_MINT - mintedByGames;
    	}

    	vMTD.mint(_recipient, _mintAmount);
    	accumFee += _mintAmount / mintDivider;
    	mintedByGames += _mintAmount;
	}

	function mintFee() external nonReentrant onlySupport {
		vMTD.mint(address(MLP), accumFee);
		MLP.updateFundsReceived_VMTD();
		accumFee = 0;
	}

	function increaseVolume(address _input, uint256 _amount) external nonReentrant onlyProtocol {
		miningStrategy.increaseVolume(_input, _amount);
	}

	function decreaseVolume(address _input, uint256 _amount) external nonReentrant onlyProtocol {
		miningStrategy.decreaseVolume(_input, _amount);
	}
}
