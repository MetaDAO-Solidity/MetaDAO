
// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;
import "@openzeppelin/contracts@4.9.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.0/utils/Address.sol";
import "@openzeppelin/contracts@4.9.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.0/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/utils/SafeERC20.sol";
import "./IMetaDAORandomNumberGenerator.sol";
import "./IMetaDAOLottery.sol";


interface MetaDAOLotteryDividends {
     function withdraw() external; 
}

contract MetaDAOLottery is ReentrancyGuard, IMetaDAOLottery, Ownable {
    using SafeERC20 for IERC20;

    address public injectorAddress; 
    address public operatorAddress;
    address public treasuryAddress;
   

    uint256 public currentLotteryId;
    uint256 public currentTicketId;

    uint256 public maxNumberTicketsPerBuyOrClaim = 100; 

    uint256[6] public rewardsBreakdown;
    
    uint32 public treasuryFee = 1000;
    uint32  public discountDivisor = 2000;
    uint256 public priceTicket = 2 ether;
    uint256 public endTime = 1 days;
    
    uint256 public maxPriceTicket = 10 ether; 
    uint256 public minPriceTicket = 2 ether;
    uint256 public pendingInjectionNextLottery; 
    
    uint256 public metaDAOLotteryDividendsFree = 5000; //50%
    uint256 public constant MIN_DISCOUNT_DIVISOR = 300; 
    uint256 public constant MIN_LENGTH_LOTTERY = 1 hours - 5 minutes; 
    uint256 public constant MAX_LENGTH_LOTTERY = 4 days + 5 minutes; 
    uint256 public constant MAX_TREASURY_FEE = 3000; 
    uint16 private constant PPTT = 10000; 

    address public LotteryDividendsAddress;
    IERC20 public  USDTToken;
    IMetaDAORandomNumberGenerator public randomGenerator
    ;

    enum Status {
        Pending, 
        Open,
        Close,
        Claimable
    }

    struct Lottery {
        Status status;
        uint32 startTime;
        uint256 endTime;
        uint256 priceTicket;
        uint32 discountDivisor; 
        uint256[6] rewardsBreakdown; 
    //    uint256[6] ticketRewardsBreakdown; // 0: 1 matching number 
        uint32 treasuryFee; 
        uint256[6] perBracket; 
        uint256[6] countWinnersPerBracket; 
        uint256 firstTicketId; 
        uint256 firstTicketIdNextLottery; 
        uint256 amountCollected; 
        uint32 finalNumber; 
    }

    struct Ticket {
        uint32 number;
        address owner;
    }

    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => Ticket) private _tickets;
    mapping(uint32 => uint32) private _bracketCalculator;
    mapping(uint256 => mapping(uint32 => uint256)) private _numberTicketsPerLotteryId;
    mapping(address => mapping(uint256 => uint256[])) private _userTicketIdsPerLotteryId;

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    modifier onlyOwnerOrInjector() {
        require((msg.sender == owner()) || (msg.sender == injectorAddress), "Not owner or injector");
        _;
    }

    event AdminTokenRecovery(address token, uint256 amount);
    event LotteryClose(uint256 indexed lotteryId, uint256 firstTicketIdNextLottery);
    event LotteryInjection(uint256 indexed lotteryId, uint256 injectedAmount);
    event LotteryOpen(
        uint256 indexed lotteryId,
        uint256 startTime,
        uint256 endTime,
        uint256 priceTicket,
        uint256 firstTicketId,
        uint256 injectedAmount
    );
    event LotteryNumberDrawn(uint256 indexed lotteryId, uint256 finalNumber, uint256 countWinningTickets);
    event NewOperatorAndTreasuryAndInjectorAddresses(address operator, address treasury, address injector);
    event NewrandomGenerator(address indexed randomGenerator);
    event TicketsPurchase(address indexed buyer, uint256 indexed lotteryId, uint256 numberTickets);
    event TicketsClaim(address indexed claimer, uint256 amount, uint256 indexed lotteryId, uint256 numberTickets);
    constructor(address _USDTTokenAddress, address _randomGeneratorAddress, address _LotteryDividendsAddress) {
        USDTToken = IERC20(_USDTTokenAddress);
        randomGenerator = IMetaDAORandomNumberGenerator(_randomGeneratorAddress);
        LotteryDividendsAddress = _LotteryDividendsAddress;


        _bracketCalculator[0] = 1;
        _bracketCalculator[1] = 11;
        _bracketCalculator[2] = 111;
        _bracketCalculator[3] = 1111;
        _bracketCalculator[4] = 11111;
        _bracketCalculator[5] = 111111;
 
        rewardsBreakdown[0] = 5;
        rewardsBreakdown[1] = 12;
        rewardsBreakdown[2] = 100;
        rewardsBreakdown[3] = 500;
        rewardsBreakdown[4] = 1250;
        rewardsBreakdown[5] = 8133;
    }

    function buyTickets(uint256 _lotteryId, uint32[] calldata _ticketNumbers)
        external
        notContract
        nonReentrant {
        require(_ticketNumbers.length != 0, "No ticket specified");
        require(_ticketNumbers.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");

        require(_lotteries[_lotteryId].status == Status.Open, "Lottery is not open");
        require(block.timestamp < _lotteries[_lotteryId].endTime, "Lottery is over");
        (uint256 amountToTransfer) = _calculateTotalPriceForBulkTickets(
            _lotteries[_lotteryId].discountDivisor,
            _lotteries[_lotteryId].priceTicket,
            _ticketNumbers.length
        );

 
        uint256 amountLotteryDiv = amountToTransfer * metaDAOLotteryDividendsFree / PPTT;
        if(amountToTransfer > 0) {            
            USDTToken.safeTransferFrom(msg.sender, address(this), amountToTransfer);
            USDTToken.safeTransfer(LotteryDividendsAddress,amountLotteryDiv);
        } 
   
        _lotteries[_lotteryId].amountCollected += amountToTransfer - amountLotteryDiv ;
    
        for (uint256 i = 0; i < _ticketNumbers.length; i++) {
            uint32 thisTicketNumber = _ticketNumbers[i];

            require((thisTicketNumber >= 1000000) && (thisTicketNumber <= 1999999), "Outside range");

            _numberTicketsPerLotteryId[_lotteryId][1 + (thisTicketNumber % 10)]++;
            _numberTicketsPerLotteryId[_lotteryId][11 + (thisTicketNumber % 100)]++;
            _numberTicketsPerLotteryId[_lotteryId][111 + (thisTicketNumber % 1000)]++;
            _numberTicketsPerLotteryId[_lotteryId][1111 + (thisTicketNumber % 10000)]++;
            _numberTicketsPerLotteryId[_lotteryId][11111 + (thisTicketNumber % 100000)]++;
            _numberTicketsPerLotteryId[_lotteryId][111111 + (thisTicketNumber % 1000000)]++;

            _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(currentTicketId);

            _tickets[currentTicketId] = Ticket({number: thisTicketNumber, owner: msg.sender});

            currentTicketId++;

            if (USDTToken.balanceOf(LotteryDividendsAddress) >= 10 * 10 **18) {
                MetaDAOLotteryDividends(LotteryDividendsAddress).withdraw();
            }
        }   

        emit TicketsPurchase(msg.sender, _lotteryId, _ticketNumbers.length);
    }


    function claimTickets(
        uint256 _lotteryId,
        uint256[] calldata _ticketIds,
        uint32[] calldata _brackets) external override notContract nonReentrant {
        require(_ticketIds.length == _brackets.length, "Not same length");
        require(_ticketIds.length != 0, "Length must be >0");
        require(_ticketIds.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");
        require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");


        uint256 rewardUSDTToTransfer;


        for (uint256 i = 0; i < _ticketIds.length; i++) {
            require(_brackets[i] < 6, "Bracket out of range"); 

            uint256 thisTicketId = _ticketIds[i]; 

            require(_lotteries[_lotteryId].firstTicketIdNextLottery > thisTicketId, "TicketId too high");
            require(_lotteries[_lotteryId].firstTicketId <= thisTicketId, "TicketId too low");
            require(msg.sender == _tickets[thisTicketId].owner, "Not the owner");

          
            _tickets[thisTicketId].owner = address(0);
      
            uint256 rewardForTicketId = _calculateRewardsForTicketId(_lotteryId, thisTicketId, _brackets[i]);

            if (_brackets[i] != 5) {
                uint256 rewardForTicketId = _calculateRewardsForTicketId(_lotteryId, thisTicketId, _brackets[i] + 1);
                require((rewardForTicketId == 0),"Bracket must be higher");
            }

        
            rewardUSDTToTransfer += rewardForTicketId;
           
        }
     
        if(rewardUSDTToTransfer > 0) {
 
            USDTToken.safeTransfer(msg.sender, rewardUSDTToTransfer);
        }

        emit TicketsClaim(msg.sender, rewardUSDTToTransfer, _lotteryId, _ticketIds.length);
    }
  
    function closeLottery(uint256 _lotteryId) external override onlyOperator nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");
        require(block.timestamp > _lotteries[_lotteryId].endTime, "Lottery not over");
 
        _lotteries[_lotteryId].firstTicketIdNextLottery = currentTicketId;

     
        randomGenerator.getRandomNumber();

        _lotteries[_lotteryId].status = Status.Close;

        emit LotteryClose(_lotteryId, currentTicketId);
    }
    
    function drawFinalNumberAndMakeLotteryClaimable(uint256 _lotteryId, bool _autoInjection)
        external
        override
        onlyOperator
        nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Close, "Lottery not close");
        require(_lotteryId == randomGenerator.viewLatestLotteryId(), "Numbers not drawn");

       
        uint32 finalNumber = randomGenerator.viewRandomResult();

 
        uint256 numberAddressesInPreviousBracket;

       
        uint256 amountToShareToWinners = (
            ((_lotteries[_lotteryId].amountCollected) * (PPTT - _lotteries[_lotteryId].treasuryFee))
        ) / PPTT;

    
        uint256 amountToWithdrawToTreasury;


        for (uint32 i = 0; i < 6; i++) {
            uint32 j = 5 - i;
          
            uint32 transformedWinningNumber = _bracketCalculator[j] + (finalNumber % (uint32(10)**(j + 1)));
       
            _lotteries[_lotteryId].countWinnersPerBracket[j] =
                _numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber] - numberAddressesInPreviousBracket;

           
            if ((_numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber] - numberAddressesInPreviousBracket) != 0) {
                
                if (_lotteries[_lotteryId].rewardsBreakdown[j] != 0) {
                    _lotteries[_lotteryId].perBracket[j] = ((_lotteries[_lotteryId].rewardsBreakdown[j] * amountToShareToWinners) 
                            (_numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber] - numberAddressesInPreviousBracket)) 

                  
                    numberAddressesInPreviousBracket = _numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber];
                }
            
            } else {
                _lotteries[_lotteryId].perBracket[j] = 0;

                amountToWithdrawToTreasury +=
                    (_lotteries[_lotteryId].rewardsBreakdown[j] * amountToShareToWinners) /
                    PPTT;
            }
        }

       
        _lotteries[_lotteryId].finalNumber = finalNumber;
        _lotteries[_lotteryId].status = Status.Claimable;

        amountToWithdrawToTreasury += (_lotteries[_lotteryId].amountCollected - amountToShareToWinners);
     
        if (_autoInjection) {
            pendingInjectionNextLottery = amountToWithdrawToTreasury;
            amountToWithdrawToTreasury = 0;
        } else {
            
            USDTToken.safeTransfer(treasuryAddress, amountToWithdrawToTreasury);
        }

        emit LotteryNumberDrawn(currentLotteryId, finalNumber, numberAddressesInPreviousBracket);
    }

    function changeRandomGenerator(address _randomGeneratorAddress) external onlyOwner {
        require(_lotteries[currentLotteryId].status == Status.Claimable, "Lottery not in claimable");

      
        IMetaDAORandomNumberGenerator(_randomGeneratorAddress).getRandomNumber();

       
        IMetaDAORandomNumberGenerator(_randomGeneratorAddress).viewRandomResult();

        randomGenerator = IMetaDAORandomNumberGenerator(_randomGeneratorAddress);

     
    }

    function injectFunds(uint256 _lotteryId, uint256 _amount) external override onlyOwnerOrInjector {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");

        USDTToken.safeTransferFrom(msg.sender, address(this), _amount);
        _lotteries[_lotteryId].amountCollected += _amount;

        emit LotteryInjection(_lotteryId, _amount);
    }

    function startLottery(

        ) external  onlyOperator {
        require(
            (currentLotteryId == 0) || (_lotteries[currentLotteryId].status == Status.Claimable),
            "Not time to start lottery"
        );
        uint256 _endTime = block.timestamp + endTime;
        require(
            ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) && ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
            "Lottery length outside of range"
        );

        require(
            (priceTicket >= minPriceTicket) && (priceTicket <= maxPriceTicket),
            "Outside of limits"
        );

        require(discountDivisor >= MIN_DISCOUNT_DIVISOR, "Discount divisor too low");
        require(treasuryFee <= MAX_TREASURY_FEE, "Treasury fee too high");



        currentLotteryId++; 

        _lotteries[currentLotteryId] = Lottery({
            status: Status.Open,
            startTime: uint32(block.timestamp),
            endTime: _endTime,
            priceTicket: priceTicket,
            discountDivisor: discountDivisor,
            rewardsBreakdown: rewardsBreakdown,
          
            treasuryFee: treasuryFee,
            perBracket: [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)],
            countWinnersPerBracket: [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)],
            firstTicketId: currentTicketId,
            firstTicketIdNextLottery: currentTicketId,
            amountCollected: pendingInjectionNextLottery,
            finalNumber: 0
        });

        emit LotteryOpen(
            currentLotteryId,
            block.timestamp,
            _endTime,
            priceTicket,
            currentTicketId,
            pendingInjectionNextLottery
        );

        pendingInjectionNextLottery = 0;
    }

    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(msg.sender, _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }



    function setMinAndMaxTicketPriceInPLT(uint256 _minPriceTicket, uint256 _maxPriceTicket)
        external
        onlyOwner {
        require(_minPriceTicket <= _maxPriceTicket, "minPrice must be < maxPrice");

        minPriceTicket = _minPriceTicket;
        maxPriceTicket = _maxPriceTicket;
    }

    function setMaxNumberTicketsPerBuy(uint256 _maxNumberTicketsPerBuy) external onlyOwner {
        require(_maxNumberTicketsPerBuy != 0, "Must be > 0");
        maxNumberTicketsPerBuyOrClaim = _maxNumberTicketsPerBuy;
    }

    function setOperatorAndTreasuryAndInjectorAddresses(
        address _operatorAddress,
        address _treasuryAddress,
        address _injectorAddress ) external onlyOwner {
        require(_operatorAddress != address(0), "Cannot be zero address");
        require(_treasuryAddress != address(0), "Cannot be zero address");
        require(_injectorAddress != address(0), "Cannot be zero address");

        operatorAddress = _operatorAddress;
        treasuryAddress = _treasuryAddress;
        injectorAddress = _injectorAddress;

        emit NewOperatorAndTreasuryAndInjectorAddresses(_operatorAddress, _treasuryAddress, _injectorAddress);
    }

    function calculateTotalPriceForBulkTickets(
        uint256 _discountDivisor,
        uint256 _priceTicket,
        uint256 _numberTickets) pure external returns (uint256) {
        require(_discountDivisor >= MIN_DISCOUNT_DIVISOR, "Must be >= MIN_DISCOUNT_DIVISOR");
        require(_numberTickets != 0, "Number of tickets must be > 0");

        return _calculateTotalPriceForBulkTickets(_discountDivisor, _priceTicket, _numberTickets);
    }

    function viewCurrentLotteryId() external view override returns (uint256) {
        return currentLotteryId;
    }

    function viewNumbersAndStatusesForTicketIds(uint256[] calldata _ticketIds)
        external
        override
        view
        returns (uint32[] memory, bool[] memory) {
        uint256 length = _ticketIds.length;
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            ticketNumbers[i] = _tickets[_ticketIds[i]].number;
            if (_tickets[_ticketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                ticketStatuses[i] = false;
            }
        }

        return (ticketNumbers, ticketStatuses);
    }
  
    function viewRewardsForTicketId(
        uint256 _lotteryId,
        uint256 _ticketId,
        uint32 _bracket) external view returns (uint256) {
       
        if (_lotteries[_lotteryId].status != Status.Claimable) {
            return (0);
        }

       
        if (
            (_lotteries[_lotteryId].firstTicketIdNextLottery < _ticketId) &&
            (_lotteries[_lotteryId].firstTicketId >= _ticketId)
        ) {
            return (0);
        }

        return _calculateRewardsForTicketId(_lotteryId, _ticketId, _bracket);
    }

    function viewUserInfoForLotteryId(
        address _user,
        uint256 _lotteryId,
        uint256 _cursor,
        uint256 _size)
        external view returns (
            uint256[] memory,
            uint32[] memory,
            bool[] memory,
            uint256
        ) {
        uint256 length = _size;
        uint256 numberTicketsBoughtAtLotteryId = _userTicketIdsPerLotteryId[_user][_lotteryId].length;

        if (length > (numberTicketsBoughtAtLotteryId - _cursor)) {
            length = numberTicketsBoughtAtLotteryId - _cursor;
        }

        uint256[] memory lotteryTicketIds = new uint256[](length);
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][i + _cursor];
            ticketNumbers[i] = _tickets[lotteryTicketIds[i]].number;

    
            if (_tickets[lotteryTicketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
              
                ticketStatuses[i] = false;
            }
        }

        return (lotteryTicketIds, ticketNumbers, ticketStatuses, _cursor + length);
    }

    function viewLottery(uint256 _lotteryId) external view returns (Lottery memory) {
        return _lotteries[_lotteryId];
    }

 
    function _calculateRewardsForTicketId(
        uint256 _lotteryId,
        uint256 _ticketId,
        uint32 _bracket) internal view returns (uint256) {
     
        uint32 winningTicketNumber = _lotteries[_lotteryId].finalNumber;

      
        uint32 userNumber = _tickets[_ticketId].number;

   
        uint32 transformedWinningNumber = _bracketCalculator[_bracket] +
            (winningTicketNumber % (uint32(10)**(_bracket + 1)));

        uint32 transformedUserNumber = _bracketCalculator[_bracket] + (userNumber % (uint32(10)**(_bracket + 1)));

    
        if (transformedWinningNumber == transformedUserNumber) {
                return (_lotteries[_lotteryId].perBracket[_bracket]);
            
        } else {
            return (0);
        }
    }


    function _calculateTotalPriceForBulkTickets(
        uint256 _discountDivisor,
        uint256 _priceTicket,
        uint256 _numberTickets) internal pure returns (uint256) {
  
        return (_priceTicket * _numberTickets * (_discountDivisor + 1 - _numberTickets)) / _discountDivisor;
        
    }


    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }


    function setmetaDAOLotteryDividend(address _LotteryDividendsAddress,uint256 _metaDAOLotteryDividendsFree) public onlyOwner {
        LotteryDividendsAddress = _LotteryDividendsAddress;
        metaDAOLotteryDividendsFree = _metaDAOLotteryDividendsFree;
    }
  
    function setRewardsBreakdown(uint256[6] memory _rewardsBreakdown) public onlyOwner {
        for(uint i = 0;i <6; i++) {
            rewardsBreakdown[i] = _rewardsBreakdown[i];
        }
    }

    function setTreasuryFee(uint32 _treasuryFee) public onlyOwner {
        treasuryFee = _treasuryFee;
    }
    
    function setDiscountDivisor(uint32 _discountDivisor) public onlyOwner {
        discountDivisor = _discountDivisor;
    }

    function setUSDTContract(address _USDTaddr) public onlyOwner {
        USDTToken = IERC20(_USDTaddr);
    }
}




