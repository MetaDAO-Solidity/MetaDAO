// SPDX-License-Identifier: MIT

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";


interface BestLogic {
    function getVIP(address _sender) external view returns (uint256);
    function getUpline(address _sender) external view returns(address);
}

contract MetaDAOAGE {
    struct Tower {
        uint256 crystals; 
        uint256 money;
        uint256 money2; 
        uint256 yield; 
        uint256 timestamp; 
        uint256 hrs; 
        address ref; 
        uint256 refs; 
        uint256 refDeps;
        uint8   treasury; 
        uint8   market; 
        uint8[5] chefs; 
        bool[5] bounties; 
        bool king; 
    }

    struct Stable {
        uint256 stableBounty; 
        uint256 stableTimestamp; 
        uint256 stableHrs; 
        uint8   stable; 
    }

    mapping(address => Tower) public towers; 
    mapping(address => Stable) public stables; 
    uint256 public totalChefs; 
    uint256 public totalTowers; 
    uint256 public totalKings; 
    uint256 public totalInvested; 
    address private manager;
    bool public START = false;
    IERC20 public BUSD_TOKEN;
    address private investmentFundAssociation; 
    address private FundUnion;
    BestLogic private bestLogic;   
    uint256 immutable public denominator = 10;
    bool public init;
    uint256 public initTimestamp;

    modifier initialized {
      require(init, 'Not initialized');
      _;
    }

    constructor(address manager_,
      BestLogic _bestLogic,
      address _investmentFundAssociation,
      address _T
      ) {
       manager = manager_;
       bestLogic = _bestLogic;
       investmentFundAssociation = _investmentFundAssociation;
       FundUnion = _T;
          
    }


    function initialize() external {
      require(manager == msg.sender);
      require(!init);
      init = true;
      initTimestamp = block.timestamp;
    }


    function canUpgradeTower(address _addr) public view returns(bool) {
        uint256 passedDays = (block.timestamp - initTimestamp) / 1 days;
        uint256 currentChefs = towers[_addr].chefs[0] + towers[_addr].chefs[1] + towers[_addr].chefs[2] + towers[_addr].chefs[3] + towers[_addr].chefs[4];
        if (currentChefs > passedDays) return false;
        return true;
    }


    function addCrystals(address ref, uint256 value) initialized external {
        uint256 crystals = value / 2e17;
        require(crystals > 0, "Zero stone");
        address user = msg.sender;       
          
        if (towers[user].ref == address(0) ) {
            address upline = bestLogic.getUpline(user);
            if(upline == address(0)) {
                towers[user].ref = (ref != address(0) && ref != msg.sender) ? ref : manager ;
               
            }else {
                towers[user].ref = upline;
            }
        }

        BUSD_TOKEN.transferFrom(msg.sender, address(this), value);
        BUSD_TOKEN.transfer(address(investmentFundAssociation), value * 10 / 100); 
        BUSD_TOKEN.transfer(address(FundUnion), value * 5 / 100);

        totalInvested += value;
        if (towers[user].timestamp == 0) {
            totalTowers++;
            towers[ref].refs++;
            // towers[user].ref = ref;
            towers[user].timestamp = block.timestamp;
            towers[user].treasury = 0;
            towers[user].market = 0;
        }
       // ref = towers[user].ref;
        uint8 marketId = towers[ref].market;
        (,uint256 refCrystal, uint256 refGold) = getMarket(marketId);

        towers[ref].crystals += (crystals * refCrystal) / 100;    //  500  * 500
        towers[ref].money += (crystals  * refGold) / 100; // 500 * 5
        towers[ref].refDeps += crystals;
        towers[user].crystals += crystals;       
    }

    function withdrawMoney(uint256 gold) initialized external {
        require(!START,"no Start");
        address user = msg.sender;
        require(gold <= towers[user].money && gold > 0);
        towers[user].money -= gold;
        uint256 amount = gold * 2e15;
        BUSD_TOKEN.transfer(user, BUSD_TOKEN.balanceOf(address(this)) < amount ? BUSD_TOKEN.balanceOf(address(this)) : amount);
    }
 
    function kingBounty() initialized external {
        address user = msg.sender;
        require(towers[user].king == false, "Alread Claimed");
        require(towers[user].chefs[4] == 6 && towers[user].treasury == 4 && towers[user].market == 2 && stables[user].stable == 3, "All building must be max level");
        syncTower(user);
        towers[user].money += 250000;
        towers[user].king = true;
        totalKings += 1;
    }

    function collectMoney() public {
        address user = msg.sender;
        syncTower(user);
        towers[user].hrs = 0;
        towers[user].money += towers[user].money2;
        towers[user].money2 = 0;
    }
 
    function collectStableBounty() public {
        address user = msg.sender;
        syncStable(user);
        stables[user].stableHrs = 0;
        towers[user].money += stables[user].stableBounty;
        stables[user].stableBounty = 0;
    }

    function claimAirdrop(uint256 towerId) initialized external {
        address user = msg.sender;
        syncTower(user);
        require(towers[user].chefs[towerId] == 6, "Not Max Level");
        require(towers[user].bounties[towerId] == false, "Already Claimed");
        uint256 bounty = getBounty(towerId);
        towers[user].money += bounty;
        towers[user].bounties[towerId] = true;
    }


    function upgradeTower(uint256 towerId) initialized external {
        require(towerId < 5, "Max 5 towers");
        address user = msg.sender;
        require(canUpgradeTower(user), "Should wait 1 day again");
        if (towerId > 0) {
            require(towers[user].chefs[towerId-1] == 6, "Prev Tower not upgraded");
        }

        syncTower(user);
        towers[user].chefs[towerId]++;
        totalChefs++;
        uint256 chefs = towers[user].chefs[towerId];
        towers[user].crystals -= getUpgradePrice(towerId, chefs) / denominator;
        towers[user].yield += getYield(towerId, chefs);
    }

    function upgradeTowncenter() initialized external {
      address user = msg.sender;
      require(towers[user].chefs[0] == 6, "Tower-1 should be Max Level");
      uint8 treasuryId = towers[user].treasury + 1;
      syncTower(user);
      require(treasuryId < 5, "Max 5 treasury");
      (uint256 price,) = getTreasure(treasuryId);
      towers[user].crystals -= price / denominator; 
      towers[user].treasury = treasuryId;
    }


    function upgradeMarket() initialized external {
      address user = msg.sender;
      require(towers[user].chefs[1] == 6, "Tower-2 should be Max Level");
      uint8 marketId = towers[user].market + 1;
      require(marketId < 3, "Max 2 market");
      (uint256 price,,) = getMarket(marketId);
      towers[user].crystals -= price / denominator; 
      towers[user].market = marketId;
    }

    function upgradeStable() initialized external {
      address user = msg.sender;
      uint8 stableId = stables[user].stable + 1;
      require(stableId < 4, "Max 3 stable");
      (uint256 price,, uint256 towerId) = getStable(stableId);
      require(towers[user].chefs[towerId] == 6, "Tower should be Max Level");
      
      towers[user].crystals -= price / denominator; 
      stables[user].stable = stableId;
      stables[user].stableTimestamp = block.timestamp;
    }

    function compound() initialized external {
        address user = msg.sender;
        syncTower(user);
        towers[user].crystals += 2 * towers[user].money / 100;
        towers[user].money = 0;
    }

    function getChefs(address addr) external view returns (uint8[5] memory) {
        return towers[addr].chefs;
    }
    
    function getBounties(address addr) external view returns (bool[5] memory) {
        return towers[addr].bounties;
    }

    function syncTower(address user) internal {
        require(towers[user].timestamp > 0, "User is not registered");
        if (towers[user].yield > 0) {
            (, uint256 treasury) = getTreasure(towers[user].treasury);
            uint256 hrs = block.timestamp / 3600 - towers[user].timestamp / 3600;
            if (hrs + towers[user].hrs > treasury) {
                hrs = treasury - towers[user].hrs;
            }
            towers[user].money2 += hrs * towers[user].yield;
            towers[user].hrs += hrs;
        }
        towers[user].timestamp = block.timestamp;
    }

    function syncStable(address user) internal {
        require(stables[user].stableTimestamp > 0, "User Stable is not registered");
        uint8 stableId = stables[user].stable;
        (,uint256 bounty,) = getStable(stableId);

        if (bounty > 0) {
            uint256 hrs = block.timestamp / 3600 - stables[user].stableTimestamp / 3600;
            if (hrs + stables[user].stableHrs > 24) {
                hrs = 24 - stables[user].stableHrs;
            }
            stables[user].stableBounty = (hrs + stables[user].stableHrs) / 24 * bounty;
            stables[user].stableHrs += hrs;
        }
        stables[user].stableTimestamp = block.timestamp;
    }

    function getUpgradePrice(uint256 towerId, uint256 chefId) internal pure returns (uint256) {
        if (chefId == 1) return [600, 9975, 25000, 40000, 55000][towerId];
        if (chefId == 2) return [1145, 12425, 27500, 42500, 62500][towerId];
        if (chefId == 3) return [2510, 15000, 30000, 45000, 67500][towerId];
        if (chefId == 4) return [3960, 17525, 32500, 47500, 70000][towerId];
        if (chefId == 5) return [5000, 20000, 35000, 50000, 77500][towerId];
        if (chefId == 6) return [7500, 22500, 37500, 52500, 85000][towerId];
        revert("Incorrect chefId");
    }

    function getYield(uint256 towerId, uint256 chefId) internal pure returns (uint256) {
        if (chefId == 1) return [5, 108, 333, 634, 1008][towerId];
        if (chefId == 2) return [10, 140, 378, 691, 1173][towerId];
        if (chefId == 3) return [23, 175, 425, 750, 1295][towerId];
        if (chefId == 4) return [38, 212, 474, 812, 1372][towerId];
        if (chefId == 5) return [50, 250, 525, 875, 1550][towerId];
        if (chefId == 6) return [78, 291, 578, 940, 1735][towerId];
        revert("Incorrect chefId");
    }

    function getTreasure(uint256 treasureId) internal pure returns (uint256, uint256) {
      if(treasureId == 0) return (0, 24); // price | hours
      if(treasureId == 1) return (2000, 36);
      if(treasureId == 2) return (2500, 48);
      if(treasureId == 3) return (3000, 60);
      if(treasureId == 4) return (4000, 72);
      revert("Incorrect treasureId");
    }

    function getMarket(uint256 marketId) internal pure returns (uint256, uint256, uint256) {
      if(marketId == 0) return (0, 5, 500); // price | crystal Ref |  gold Ref (0, 8, 4) 
      if(marketId == 1) return (2500, 5, 800); // (2000, 10, 6)  
      if(marketId == 2) return (5000, 5, 1000);//  (4000, 12, 8)
      revert("Incorrect marketId");
    }

    function getBounty(uint256 towerId) internal pure returns (uint256) {
        return [10000, 50000, 80000, 140000, 210000][towerId];
    }

    function getStable(uint256 stableId) internal pure returns (uint256, uint256, uint256 ) {
        if(stableId == 0) return (0, 0, 0); // price | gold bounty per 24hrs | tower id to max
        if(stableId == 1) return (50000, 25000, 2);
        if(stableId == 2) return (75000, 68750, 3);
        if(stableId == 3) return (100000, 135000, 4);
        revert("Incorrect stableId");
    }
    function setSTART(bool _START) public  {
        require(msg.sender == manager);
        START = _START;
    }
    // BUSD_TOKEN
    function setBUSD_TOKEN(address _BUSD_TOKEN) public  {
        require(manager == msg.sender);
        BUSD_TOKEN = IERC20(_BUSD_TOKEN);
    }  
    function setInvestmentFundAssociation(address _investmentFundAssociation) public  {
        require(manager == msg.sender);
        investmentFundAssociation = _investmentFundAssociation;
    }
    function setBestLogic(BestLogic _bestLogic) public  {
        require(manager == msg.sender);        
        bestLogic = _bestLogic;
    }
    function setInitTimestamp(uint256 _initTimestamp) public  {
        require(manager == msg.sender);
        initTimestamp = _initTimestamp;
    }

}
