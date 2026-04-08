// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LendingPool
 * @notice Decentralized Lending & Borrowing Protocol for COMP5521
 *
 * Core features:
 *  - Deposit (Supply) / Withdraw
 *  - Borrow / Repay
 *  - Over-collateralization with Health Factor
 *  - Loan-to-Value (LTV) limits
 *  - Dynamic interest rate model based on Utilization Rate
 *  - Per-block interest accrual (index-based, same as Compound/Aave)
 *
 * Interest Rate Model (Linear / "Kinked" simplified):
 *   Utilization Rate U = totalBorrowed / totalSupplied
 *   Borrow APR        = baseRate + slope * U
 *   Supply APR        = Borrow APR * U * (1 - reserveFactor)
 *
 * Health Factor:
 *   HF = (totalCollateralUSD * liquidationThreshold) / totalDebtUSD
 *   HF < 1.0 → position can be liquidated
 */
contract LendingPool is Ownable, ReentrancyGuard {

    // ─────────────────────────────────────────────
    //  Constants
    // ─────────────────────────────────────────────

    uint256 public constant PRECISION         = 1e18;
    uint256 public constant BLOCKS_PER_YEAR   = 2102400; // ~15s/block on Ethereum
    uint256 public constant RESERVE_FACTOR    = 10;      // 10% of interest → protocol reserve

    // ─────────────────────────────────────────────
    //  Data Structures
    // ─────────────────────────────────────────────

    /**
     * @dev Configuration for each supported token.
     * @param ltv                Max borrow as % of collateral value (e.g. 75 = 75%)
     * @param liquidationThreshold  Threshold for liquidation (e.g. 80 = 80%), always > ltv
     * @param baseRatePerYear    Minimum borrow rate per year in % (e.g. 2 = 2%)
     * @param slopePerYear       Additional rate per year at 100% utilization (e.g. 20 = 20%)
     */
    struct TokenConfig {
        bool     supported;
        uint256  ltv;
        uint256  liquidationThreshold;
        uint256  baseRatePerYear;
        uint256  slopePerYear;
    }

    /**
     * @dev Per-token market state.
     *
     * Index-based accounting (same pattern as Compound):
     *   scaledAmount = principalAmount * PRECISION / indexAtTime
     *   currentAmount = scaledAmount * currentIndex / PRECISION
     *
     * This way, just updating the index automatically applies interest
     * to every user position without looping.
     */
    struct MarketState {
        uint256 totalScaledSupply;   // Sum of (supplyAmount * PRECISION / supplyIndex at deposit)
        uint256 totalScaledBorrow;   // Sum of (borrowAmount * PRECISION / borrowIndex at borrow)
        uint256 borrowIndex;         // Cumulative borrow interest multiplier (starts at PRECISION)
        uint256 supplyIndex;         // Cumulative supply interest multiplier (starts at PRECISION)
        uint256 lastUpdateBlock;     // Block number of last interest accrual
    }

    struct UserSupply {
        uint256 scaledAmount;   // user's scaled supply balance
    }

    struct UserBorrow {
        uint256 scaledAmount;   // user's scaled borrow balance
    }

    // ─────────────────────────────────────────────
    //  State
    // ─────────────────────────────────────────────

    address[] public supportedTokens;

    mapping(address => TokenConfig)  public tokenConfigs;
    mapping(address => MarketState)  public markets;
    mapping(address => uint256)      public tokenPricesUSD; // price in USD, scaled by 1e18

    // user → token → position
    mapping(address => mapping(address => UserSupply)) public userSupplies;
    mapping(address => mapping(address => UserBorrow)) public userBorrows;

    // ─────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────

    event Deposit  (address indexed user, address indexed token, uint256 amount);
    event Withdraw (address indexed user, address indexed token, uint256 amount);
    event Borrow   (address indexed user, address indexed token, uint256 amount);
    event Repay    (address indexed user, address indexed token, uint256 amount);
    event PriceUpdated(address indexed token, uint256 newPrice);

    // ─────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────

    constructor() Ownable(msg.sender) {}

    // ─────────────────────────────────────────────
    //  Admin Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Add a new token to the lending pool.
     * @param token                  ERC20 token address
     * @param ltv                    Max LTV in % (e.g. 75)
     * @param liquidationThreshold   Liquidation threshold in % (e.g. 80)
     * @param baseRatePerYear        Base borrow rate in % per year (e.g. 2)
     * @param slopePerYear           Slope in % per year at 100% utilization (e.g. 20)
     * @param initialPriceUSD        Initial USD price scaled by 1e18
     */
    function addSupportedToken(
        address token,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 baseRatePerYear,
        uint256 slopePerYear,
        uint256 initialPriceUSD
    ) external onlyOwner {
        require(token != address(0),               "Invalid token");
        require(!tokenConfigs[token].supported,    "Already supported");
        require(ltv < liquidationThreshold,        "LTV must be < liq threshold");
        require(liquidationThreshold <= 95,        "Liq threshold too high");

        tokenConfigs[token] = TokenConfig({
            supported:            true,
            ltv:                  ltv,
            liquidationThreshold: liquidationThreshold,
            baseRatePerYear:      baseRatePerYear,
            slopePerYear:         slopePerYear
        });

        markets[token] = MarketState({
            totalScaledSupply: 0,
            totalScaledBorrow: 0,
            borrowIndex:       PRECISION,
            supplyIndex:       PRECISION,
            lastUpdateBlock:   block.number
        });

        tokenPricesUSD[token] = initialPriceUSD;
        supportedTokens.push(token);
    }

    /**
     * @notice Update token price (simulates oracle in production).
     */
    function setTokenPrice(address token, uint256 priceUSD) external onlyOwner {
        require(tokenConfigs[token].supported, "Not supported");
        tokenPricesUSD[token] = priceUSD;
        emit PriceUpdated(token, priceUSD);
    }

    // ─────────────────────────────────────────────
    //  Core User Actions
    // ─────────────────────────────────────────────

    /**
     * @notice Supply tokens to the lending pool and earn interest.
     *         Supplied tokens also count as collateral for borrowing.
     * @param token   ERC20 token address
     * @param amount  Amount to supply (in token's native decimals)
     */
    function deposit(address token, uint256 amount) external nonReentrant {
        require(tokenConfigs[token].supported, "Token not supported");
        require(amount > 0,                    "Amount must be > 0");

        _accrueInterest(token);

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Convert amount to scaled units and add to user's position
        uint256 scaled = amount * PRECISION / markets[token].supplyIndex;
        userSupplies[msg.sender][token].scaledAmount += scaled;
        markets[token].totalScaledSupply += scaled;

        emit Deposit(msg.sender, token, amount);
    }

    /**
     * @notice Withdraw previously supplied tokens (+ accrued interest).
     * @param token   ERC20 token address
     * @param amount  Amount to withdraw. Pass type(uint256).max to withdraw all.
     */
    function withdraw(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(token);

        uint256 currentBalance = _supplyBalanceOf(msg.sender, token);

        // Allow "withdraw all"
        if (amount == type(uint256).max) {
            amount = currentBalance;
        }

        require(currentBalance >= amount, "Insufficient supply balance");
        require(
            _isHealthyAfterWithdraw(msg.sender, token, amount),
            "Withdrawal would undercollateralize position"
        );

        uint256 scaled = amount * PRECISION / markets[token].supplyIndex;
        userSupplies[msg.sender][token].scaledAmount -= scaled;
        markets[token].totalScaledSupply -= scaled;

        IERC20(token).transfer(msg.sender, amount);

        emit Withdraw(msg.sender, token, amount);
    }

    /**
     * @notice Borrow tokens against your deposited collateral.
     *         Requires Health Factor to remain >= 1.0 after borrowing.
     * @param token   ERC20 token to borrow
     * @param amount  Amount to borrow
     */
    function borrow(address token, uint256 amount) external nonReentrant {
        require(tokenConfigs[token].supported, "Token not supported");
        require(amount > 0,                    "Amount must be > 0");

        _accrueInterest(token);

        // Check enough liquidity in the pool
        uint256 availableLiquidity = IERC20(token).balanceOf(address(this));
        require(availableLiquidity >= amount, "Insufficient pool liquidity");

        // Check that HF would stay >= 1 after this borrow
        require(
            _isHealthyAfterBorrow(msg.sender, token, amount),
            "Insufficient collateral (Health Factor would drop below 1)"
        );

        uint256 scaled = amount * PRECISION / markets[token].borrowIndex;
        userBorrows[msg.sender][token].scaledAmount += scaled;
        markets[token].totalScaledBorrow += scaled;

        IERC20(token).transfer(msg.sender, amount);

        emit Borrow(msg.sender, token, amount);
    }

    /**
     * @notice Repay borrowed tokens (+ accrued interest).
     * @param token   ERC20 token to repay
     * @param amount  Amount to repay. Pass type(uint256).max to repay all debt.
     */
    function repay(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(token);

        uint256 currentDebt = _borrowBalanceOf(msg.sender, token);
        require(currentDebt > 0, "No debt to repay");

        // Allow "repay all"
        if (amount == type(uint256).max) {
            amount = currentDebt;
        }

        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;

        IERC20(token).transferFrom(msg.sender, address(this), repayAmount);

        uint256 scaled = repayAmount * PRECISION / markets[token].borrowIndex;
        // Guard against underflow due to rounding
        UserBorrow storage ub = userBorrows[msg.sender][token];
        ub.scaledAmount = ub.scaledAmount > scaled ? ub.scaledAmount - scaled : 0;
        markets[token].totalScaledBorrow = markets[token].totalScaledBorrow > scaled
            ? markets[token].totalScaledBorrow - scaled
            : 0;

        emit Repay(msg.sender, token, repayAmount);
    }

    // ─────────────────────────────────────────────
    //  Interest Accrual  (the "engine")
    // ─────────────────────────────────────────────

    /**
     * @dev Update borrow/supply indexes for a token based on blocks elapsed.
     *
     * Linear Interest Rate Model:
     *   U   = totalBorrowed / totalSupplied        (utilization rate)
     *   APR = baseRate + slope * U                 (annual borrow rate)
     *   Rate per block = APR / BLOCKS_PER_YEAR
     *
     * Index update:
     *   newBorrowIndex = borrowIndex * (1 + ratePerBlock * blockDelta)
     *   newSupplyIndex = supplyIndex * (1 + supplyRatePerBlock * blockDelta)
     */
    function _accrueInterest(address token) internal {
        MarketState storage market = markets[token];
        uint256 blockDelta = block.number - market.lastUpdateBlock;
        if (blockDelta == 0) return;

        uint256 totalBorrowed = market.totalScaledBorrow * market.borrowIndex / PRECISION;
        uint256 totalSupplied = market.totalScaledSupply * market.supplyIndex / PRECISION;

        uint256 utilizationRate = (totalSupplied == 0)
            ? 0
            : totalBorrowed * PRECISION / totalSupplied;

        TokenConfig memory cfg = tokenConfigs[token];

        // Borrow APR as a fraction of PRECISION (e.g. 5% → 0.05 * 1e18)
        uint256 borrowAPR = (cfg.baseRatePerYear * PRECISION / 100)
            + (cfg.slopePerYear * utilizationRate / 100);         // slope * U / 100

        uint256 borrowRatePerBlock = borrowAPR / BLOCKS_PER_YEAR;
        uint256 borrowInterest     = borrowRatePerBlock * blockDelta; // fraction of PRECISION

        // Update borrow index
        market.borrowIndex = market.borrowIndex + market.borrowIndex * borrowInterest / PRECISION;

        // Update supply index: lenders receive (1 - reserveFactor) fraction of interest
        if (totalBorrowed > 0 && totalSupplied > 0) {
            uint256 supplyAPR        = borrowAPR * utilizationRate / PRECISION
                                       * (100 - RESERVE_FACTOR) / 100;
            uint256 supplyRatePerBlock = supplyAPR / BLOCKS_PER_YEAR;
            uint256 supplyInterest     = supplyRatePerBlock * blockDelta;
            market.supplyIndex = market.supplyIndex + market.supplyIndex * supplyInterest / PRECISION;
        }

        market.lastUpdateBlock = block.number;
    }

    // Public wrapper so the frontend can trigger it explicitly
    function accrueInterest(address token) external {
        require(tokenConfigs[token].supported, "Not supported");
        _accrueInterest(token);
    }

    // ─────────────────────────────────────────────
    //  Health Factor Logic
    // ─────────────────────────────────────────────

    /**
     * @notice Calculate Health Factor for a user.
     * @return HF scaled by PRECISION (1e18 = 1.0). Returns max uint if no debt.
     *
     * HF = Σ(supplyBalance_i * price_i * liqThreshold_i / 100)
     *    / Σ(borrowBalance_i * price_i)
     */
    function getHealthFactor(address user) public view returns (uint256) {
        (uint256 collateralValue, uint256 debtValue) = _positionValues(user);
        if (debtValue == 0) return type(uint256).max;
        return collateralValue * PRECISION / debtValue;
    }

    function _positionValues(address user)
        internal view
        returns (uint256 totalCollateralUSD, uint256 totalDebtUSD)
    {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 price = tokenPricesUSD[token];

            uint256 supplyBal = _supplyBalanceOf(user, token);
            if (supplyBal > 0) {
                // Weighted by liquidation threshold
                totalCollateralUSD +=
                    supplyBal * price / PRECISION
                    * tokenConfigs[token].liquidationThreshold / 100;
            }

            uint256 borrowBal = _borrowBalanceOf(user, token);
            if (borrowBal > 0) {
                totalDebtUSD += borrowBal * price / PRECISION;
            }
        }
    }

    function _isHealthyAfterBorrow(
        address user,
        address borrowToken,
        uint256 borrowAmount
    ) internal view returns (bool) {
        (uint256 collateral, uint256 debt) = _positionValues(user);
        uint256 newDebt = debt + borrowAmount * tokenPricesUSD[borrowToken] / PRECISION;
        if (newDebt == 0) return true;
        return collateral * PRECISION / newDebt >= PRECISION;
    }

    function _isHealthyAfterWithdraw(
        address user,
        address supplyToken,
        uint256 withdrawAmount
    ) internal view returns (bool) {
        (uint256 collateral, uint256 debt) = _positionValues(user);
        if (debt == 0) return true;

        uint256 removedCollateral =
            withdrawAmount * tokenPricesUSD[supplyToken] / PRECISION
            * tokenConfigs[supplyToken].liquidationThreshold / 100;

        if (removedCollateral >= collateral) return false;
        uint256 newCollateral = collateral - removedCollateral;
        return newCollateral * PRECISION / debt >= PRECISION;
    }

    // ─────────────────────────────────────────────
    //  Internal Balance Helpers
    // ─────────────────────────────────────────────

    function _supplyBalanceOf(address user, address token)
        internal view returns (uint256)
    {
        uint256 scaled = userSupplies[user][token].scaledAmount;
        if (scaled == 0) return 0;
        return scaled * markets[token].supplyIndex / PRECISION;
    }

    function _borrowBalanceOf(address user, address token)
        internal view returns (uint256)
    {
        uint256 scaled = userBorrows[user][token].scaledAmount;
        if (scaled == 0) return 0;
        return scaled * markets[token].borrowIndex / PRECISION;
    }

    // ─────────────────────────────────────────────
    //  Public View Functions (for frontend)
    // ─────────────────────────────────────────────

    function getSupplyBalance(address user, address token)
        external view returns (uint256)
    {
        return _supplyBalanceOf(user, token);
    }

    function getBorrowBalance(address user, address token)
        external view returns (uint256)
    {
        return _borrowBalanceOf(user, token);
    }

    /// @notice Current Utilization Rate for a token (0 – 1e18 = 0% – 100%)
    function getUtilizationRate(address token) public view returns (uint256) {
        MarketState memory m = markets[token];
        uint256 totalBorrowed = m.totalScaledBorrow * m.borrowIndex / PRECISION;
        uint256 totalSupplied = m.totalScaledSupply * m.supplyIndex / PRECISION;
        if (totalSupplied == 0) return 0;
        return totalBorrowed * PRECISION / totalSupplied;
    }

    /// @notice Annual Percentage Yield for borrowers (as fraction of PRECISION)
    function getBorrowAPY(address token) public view returns (uint256) {
        uint256 U   = getUtilizationRate(token);
        TokenConfig memory cfg = tokenConfigs[token];
        return (cfg.baseRatePerYear * PRECISION / 100) + (cfg.slopePerYear * U / 100);
    }

    /// @notice Annual Percentage Yield for suppliers (as fraction of PRECISION)
    function getSupplyAPY(address token) public view returns (uint256) {
        uint256 U       = getUtilizationRate(token);
        uint256 bAPY    = getBorrowAPY(token);
        return bAPY * U / PRECISION * (100 - RESERVE_FACTOR) / 100;
    }

    /// @notice Total collateral value in USD (raw, without threshold weighting)
    function getTotalCollateralUSD(address user) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 bal = _supplyBalanceOf(user, token);
            total += bal * tokenPricesUSD[token] / PRECISION;
        }
        return total;
    }

    /// @notice Total debt value in USD
    function getTotalDebtUSD(address user) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 bal = _borrowBalanceOf(user, token);
            total += bal * tokenPricesUSD[token] / PRECISION;
        }
        return total;
    }

    /**
     * @notice Maximum amount the user can borrow of a given token
     *         given their current collateral and LTV limits.
     */
    function getMaxBorrow(address user, address borrowToken)
        external view returns (uint256)
    {
        uint256 totalLTVWeightedCollateralUSD = 0;
        uint256 totalDebtUSD = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 price = tokenPricesUSD[token];

            uint256 supplyBal = _supplyBalanceOf(user, token);
            if (supplyBal > 0) {
                totalLTVWeightedCollateralUSD +=
                    supplyBal * price / PRECISION * tokenConfigs[token].ltv / 100;
            }

            uint256 borrowBal = _borrowBalanceOf(user, token);
            if (borrowBal > 0) {
                totalDebtUSD += borrowBal * price / PRECISION;
            }
        }

        if (totalLTVWeightedCollateralUSD <= totalDebtUSD) return 0;
        uint256 availableUSD = totalLTVWeightedCollateralUSD - totalDebtUSD;
        return availableUSD * PRECISION / tokenPricesUSD[borrowToken];
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /**
     * @notice Get all relevant market data for a token in one call.
     */
    function getMarketData(address token) external view returns (
        uint256 totalSupplied,
        uint256 totalBorrowed,
        uint256 utilizationRate,
        uint256 supplyAPY,
        uint256 borrowAPY,
        uint256 price
    ) {
        MarketState memory m = markets[token];
        totalSupplied   = m.totalScaledSupply * m.supplyIndex / PRECISION;
        totalBorrowed   = m.totalScaledBorrow * m.borrowIndex / PRECISION;
        utilizationRate = getUtilizationRate(token);
        supplyAPY       = getSupplyAPY(token);
        borrowAPY       = getBorrowAPY(token);
        price           = tokenPricesUSD[token];
    }

    /**
     * @notice Get all relevant user data for a token in one call.
     */
    function getUserData(address user, address token) external view returns (
        uint256 supplyBalance,
        uint256 borrowBalance,
        uint256 healthFactor,
        uint256 maxBorrow
    ) {
        supplyBalance = _supplyBalanceOf(user, token);
        borrowBalance = _borrowBalanceOf(user, token);
        healthFactor  = getHealthFactor(user);
        // maxBorrow per token computed inline to avoid re-entry to external
        uint256 totalLTVWeightedCollateralUSD = 0;
        uint256 totalDebtUSD = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address t = supportedTokens[i];
            uint256 sb = _supplyBalanceOf(user, t);
            if (sb > 0) totalLTVWeightedCollateralUSD += sb * tokenPricesUSD[t] / PRECISION * tokenConfigs[t].ltv / 100;
            uint256 bb = _borrowBalanceOf(user, t);
            if (bb > 0) totalDebtUSD += bb * tokenPricesUSD[t] / PRECISION;
        }
        maxBorrow = totalLTVWeightedCollateralUSD <= totalDebtUSD
            ? 0
            : (totalLTVWeightedCollateralUSD - totalDebtUSD) * PRECISION / tokenPricesUSD[token];
    }
}
