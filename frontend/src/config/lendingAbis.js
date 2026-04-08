// ABI definitions for the COMP5568 Lending Protocol contracts

export const LENDING_POOL_ABI = [
  "function deposit(address token, uint256 amount) external",
  "function withdraw(address token, uint256 amount) external",
  "function borrow(address token, uint256 amount) external",
  "function repay(address token, uint256 amount) external",
  "function accrueInterest(address token) external",

  "function getHealthFactor(address user) view returns (uint256)",
  "function getSupplyBalance(address user, address token) view returns (uint256)",
  "function getBorrowBalance(address user, address token) view returns (uint256)",
  "function getMaxBorrow(address user, address borrowToken) view returns (uint256)",
  "function getTotalCollateralUSD(address user) view returns (uint256)",
  "function getTotalDebtUSD(address user) view returns (uint256)",
  "function getSupplyAPY(address token) view returns (uint256)",
  "function getBorrowAPY(address token) view returns (uint256)",
  "function getUtilizationRate(address token) view returns (uint256)",
  "function getSupportedTokens() view returns (address[])",
  "function getMarketData(address token) view returns (uint256 totalSupplied, uint256 totalBorrowed, uint256 utilizationRate, uint256 supplyAPY, uint256 borrowAPY, uint256 price)",
  "function getUserData(address user, address token) view returns (uint256 supplyBalance, uint256 borrowBalance, uint256 healthFactor, uint256 maxBorrow)",

  "function tokenConfigs(address) view returns (bool supported, uint256 ltv, uint256 liquidationThreshold, uint256 baseRatePerYear, uint256 slopePerYear)",
  "function tokenPricesUSD(address) view returns (uint256)",

  "event Deposit(address indexed user, address indexed token, uint256 amount)",
  "event Withdraw(address indexed user, address indexed token, uint256 amount)",
  "event Borrow(address indexed user, address indexed token, uint256 amount)",
  "event Repay(address indexed user, address indexed token, uint256 amount)",
];

export const ERC20_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function faucet() external",
];
