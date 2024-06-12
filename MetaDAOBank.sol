// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface BestLogic {   
    function getIsUser(address _addr) external view returns (bool);
    function getUpline(address _addr) external view returns(address);
    function getVIP(address _addr) external view  returns(uint8);

}
contract MetaDAOBank is Ownable {
    uint256 public  GOLDS_TO_HIRE_1MINER = 20 days; 
    uint256 public  REFERRAL = 50;     
    uint256 public constant PERCENTS_DIVIDER = 1000;

    uint256 public constant DAMPENING_FACTOR = 80;
    uint256 public INVESTMENTFUND = 70;
    uint256 public EDUUNION_TAX = 10;
    uint256 public OPERTAION_TAX = 30;
    uint256 public devTax = 5;

    uint256 public COMPOUND_BONUS = 30;
    uint256 public COMPOUND_BONUS_MAX_TIMES = 20; 
    uint256 public COMPOUND_STEP = 1 days; 

    uint256 public WITHDRAWAL_TAX = 800;
    uint256 public SELLFUND_TAX = 50; 
    uint256 public COMPOUND_FOR_NO_TAX_WITHDRAWAL = 10;
    uint256 public OUT = 3;

    uint256 public totalStaked; 
    uint256 public totalUsers; 
    uint256 public totalCompound;
    uint256 public totalRefBonus; 
    uint256 public totalWithdrawn;
 
    uint256 private marketGolds = 100_000 * GOLDS_TO_HIRE_1MINER;
    uint256 PSN = 10000;
    uint256 PSNH = 5000;

    bool private _initialized; 
    uint256 public CUTOFF_STEP =  2 days; 
    uint256 public WITHDRAW_COOLDOWN = 1 days;

    /* addresses */
    address payable private dev1;  
    address payable  private investmentFundAssociation;
    address payable private FundAddress;
    address payable private EduAddress;
    address payable private OprationAddress; 
    BestLogic private bestLogic;
    IERC20 public token;

    mapping(address => bool) private hasParticipated; 


    struct User {
        uint256 initialDeposit;
        uint256 userDeposit; 
        uint256 miners; 
        uint256 claimedGolds;
        uint256 lastHireTime; 
        address referrer; 
        uint256 referralsCount;  
        uint256 referralGoldRewards; 
        uint256 totalWithdrawn; 
        uint256 dailyCompoundBonus; 
        uint256 farmerCompoundCount;
        uint256 lastWithdrawTime; 
    }

    mapping(address => User) public users;

    modifier initialized() {
        require(_initialized, "Contract not initialized");
        _;
    }

    constructor(
        address payable _dev1,
        IERC20 _token ,
        BestLogic _bestLogic,
        address payable _investmentFundAssociation,
        address payable _FundAddress,
        address payable _EduAddress,
        address payable  _OprationAddress

        
        ) 
        {
        dev1 = _dev1;
        token=_token;
        bestLogic = _bestLogic;
        investmentFundAssociation = _investmentFundAssociation;
        FundAddress = _FundAddress;
        EduAddress = _EduAddress;
        OprationAddress = _OprationAddress;

    }

    function startFarm(address addr,uint256 amount) public payable onlyOwner {
        require(!_initialized, "Already initialized");
        _initialized = true;
        buyGold(addr,amount);
    }

    function hireMiners(bool isCompound) public initialized {
        User storage user = users[msg.sender];

        uint256 goldsUsed = getMyGolds(msg.sender);
        uint256 goldsForCompound = goldsUsed;

        if (isCompound) {
            goldsForCompound += getDailyCompoundBonus(
                msg.sender,
                goldsForCompound
            );
            uint256 goldsUsedValue = calculateGoldSell(goldsForCompound);
            user.userDeposit += goldsUsedValue;
            totalCompound += goldsUsedValue;
        }

        if (block.timestamp - user.lastHireTime >= COMPOUND_STEP) {
            if (user.dailyCompoundBonus < COMPOUND_BONUS_MAX_TIMES) {
                ++user.dailyCompoundBonus;
            }
         
            ++user.farmerCompoundCount;
        }
        user.claimedGolds = goldsForCompound % GOLDS_TO_HIRE_1MINER;
        user.miners += goldsForCompound / GOLDS_TO_HIRE_1MINER;
        user.lastHireTime = block.timestamp;

        marketGolds += dampenGold(goldsUsed);

        if (!hasParticipated[msg.sender]) {
            hasParticipated[msg.sender] = true;
            totalUsers++;
        }
    }


    
    function dampenGold(uint256 amount) private pure returns (uint256) {
        return (amount * DAMPENING_FACTOR) / 100;
    }


    function sellGolds() public initialized {
        
        User storage user = users[msg.sender];
    
        require(block.timestamp-user.lastHireTime>=WITHDRAW_COOLDOWN, "must wait 24 hours before sell");
     
        uint256 hasGolds = getMyGolds(msg.sender);
        uint256 goldValue = calculateGoldSell(hasGolds);
        if (user.dailyCompoundBonus < COMPOUND_FOR_NO_TAX_WITHDRAWAL) {
           
            goldValue -= ((goldValue * WITHDRAWAL_TAX) / PERCENTS_DIVIDER);

        } else if ( user.totalWithdrawn  >= user.initialDeposit * OUT ){
           
            user.dailyCompoundBonus = 0;
            user.farmerCompoundCount = 0;
        }

    
        user.lastWithdrawTime = block.timestamp;
        user.claimedGolds = 0;
        user.lastHireTime = block.timestamp;
        marketGolds += dampenGold(hasGolds);

        if (token.balanceOf(address(this)) < goldValue) {
            goldValue = token.balanceOf(address(this));
        }

        uint256 goldsPayout = goldValue - payFees(FundAddress,goldValue,SELLFUND_TAX); 
    
        token.transfer(msg.sender,goldsPayout);
        
        user.totalWithdrawn = user.totalWithdrawn + goldsPayout; 
        totalWithdrawn += goldsPayout;
        if (user.miners == 0) { 
            hasParticipated[msg.sender] = false;
            totalUsers--;
        }
    }


   function buyGold(address ref, uint256 amount) public payable initialized {
        User storage user = users[msg.sender];
 
        token.transferFrom(msg.sender,address(this),amount);
        uint256 goldsBought = calculateGoldBuy(amount,token.balanceOf(address(this))-amount);
        user.userDeposit += amount;
        user.initialDeposit += amount;
        user.claimedGolds += goldsBought;

        uint256 refRewards = (amount * REFERRAL) / PERCENTS_DIVIDER;

        if (user.referrer == address(0) ) {
            address upline = bestLogic.getUpline(msg.sender);
            if(upline == address(0)) {
                user.referrer = (ref != address(0) && ref != msg.sender) ? ref : dev1 ;
               
            }else {
                user.referrer = upline;
            }
            ++users[user.referrer].referralsCount;
        }

        if (user.referrer != address(0)) {
            address upline = user.referrer;
            // uint256 refRewards = (amount * REFERRAL) / PERCENTS_DIVIDER;
            token.transfer(upline,refRewards);

            users[upline].referralGoldRewards += refRewards;
            totalRefBonus += refRewards;
        }

        uint256 technologyAmount = payFees(dev1,amount,devTax);
        uint256 investAmount = payFees(investmentFundAssociation,amount,INVESTMENTFUND);        
        uint256 operateAmount = payFees(OprationAddress,amount,OPERTAION_TAX);       
        uint256 educateAmount = payFees(EduAddress,amount,EDUUNION_TAX);
        totalStaked += amount - technologyAmount - investAmount - operateAmount - educateAmount - refRewards;
        hireMiners(false);
    }
    function payFees(address _addr, uint256 goldValue,uint256 Free) internal returns (uint256) {
        uint256 tax = (goldValue * Free) / PERCENTS_DIVIDER;
        token.transfer(_addr,tax);
        return tax;
    } 
    

    function getDailyCompoundBonus(address _adr, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 totalBonus = users[_adr].dailyCompoundBonus * COMPOUND_BONUS;
        uint256 result = (amount * totalBonus) / PERCENTS_DIVIDER;
        return result;
    }
    function getUserInfo(address _adr)
        public
        view
        returns (
            uint256 _initialDeposit,
            uint256 _userDeposit,
            uint256 _miners,
            uint256 _claimedGolds,
            uint256 _lastHireTime,
            address _referrer,
            uint256 _referrals,
            uint256 _totalWithdrawn,
            uint256 _referralGoldRewards,
            uint256 _dailyCompoundBonus,
            uint256 _farmerCompoundCount,
            uint256 _lastWithdrawTime
        )
    {
        _initialDeposit = users[_adr].initialDeposit;
        _userDeposit = users[_adr].userDeposit;
        _miners = users[_adr].miners;
        _claimedGolds = users[_adr].claimedGolds;
        _lastHireTime = users[_adr].lastHireTime;
        _referrer = users[_adr].referrer;
        _referrals = users[_adr].referralsCount;
        _totalWithdrawn = users[_adr].totalWithdrawn;
        _referralGoldRewards = users[_adr].referralGoldRewards;
        _dailyCompoundBonus = users[_adr].dailyCompoundBonus;
        _farmerCompoundCount = users[_adr].farmerCompoundCount;
        _lastWithdrawTime = users[_adr].lastWithdrawTime;
    }
    
    function getAvailableEarnings(address _adr) public view returns (uint256) {
        return calculateGoldSell(getMyGolds(_adr));
    }
   
    function calculateTrade(
        uint256 rt,
        uint256 rs,
        uint256 bs
    ) private view returns (uint256) {
        return (PSN * bs) / (PSNH + (PSN * rs + PSNH * rt) / rt);
    }

    function calculateGoldSell(uint256 golds) public view returns (uint256) {
        return calculateTrade(golds, marketGolds, token.balanceOf(address(this)));
    }

    function calculateGoldBuy(uint256 eth, uint256 contractBalance)
        public
        view
        returns (uint256)
    {
        return calculateTrade(eth, contractBalance, marketGolds);
    }

    function calculateGoldBuySimple(uint256 eth) public view returns (uint256) {
        return calculateGoldBuy(eth, token.balanceOf(address(this)));
    }
    function getGoldsYieldPerDay(uint256 amount)
        public
        view
        returns (uint256, uint256)
    {
        uint256 goldsAmount = calculateGoldBuy(amount, token.balanceOf(address(this)));
        uint256 miners = goldsAmount / GOLDS_TO_HIRE_1MINER;
        uint256 day = 1 days;
        uint256 goldsPerDay = day * miners;
        uint256 earningsPerDay = calculateGoldSellForYield(goldsPerDay, amount);
        return (miners, earningsPerDay);
    }

    function calculateGoldSellForYield(uint256 golds, uint256 amount)
        public
        view
        returns (uint256)
    {
        return
            calculateTrade(golds, marketGolds, token.balanceOf(address(this)) + amount);
    }

    function getSiteInfo()
        public
        view
        returns (
            uint256 _totalStaked,
            uint256 _totalUsers,
            uint256 _totalCompound,
            uint256 _totalRefBonus
        )
    {
        return (totalStaked, totalUsers, totalCompound, totalRefBonus);
    }
 
    function getMyMiners() public view returns (uint256) {
        return users[msg.sender].miners;
    }
   
    function getMyGolds(address addr) public view returns (uint256) {
        return users[addr].claimedGolds + getGoldsSinceLastHireTime(addr);
    }
  
    function getGoldsSinceLastHireTime(address adr)
        public
        view
        returns (uint256)
    {
        uint256 secondsSinceLastHireTime = block.timestamp -
            users[adr].lastHireTime;
        /** get min time. **/
        uint256 cutoffTime = min(secondsSinceLastHireTime, CUTOFF_STEP);
        uint256 secondsPassed = min(GOLDS_TO_HIRE_1MINER, cutoffTime);
        return secondsPassed * users[adr].miners;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

}
