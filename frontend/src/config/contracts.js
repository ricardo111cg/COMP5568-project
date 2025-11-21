// 合约配置 - 请根据实际部署地址更新
export const CONTRACT_ADDRESSES = {
  // 本地开发网络或测试网络地址
  NFT: import.meta.env.VITE_NFT_ADDRESS || "0x0000000000000000000000000000000000000000",
  Stablecoin: import.meta.env.VITE_STABLECOIN_ADDRESS || "0x0000000000000000000000000000000000000000",
  Marketplace: import.meta.env.VITE_MARKETPLACE_ADDRESS || "0x0000000000000000000000000000000000000000",
};

// 网络配置
export const NETWORK_CONFIG = {
  chainId: import.meta.env.VITE_CHAIN_ID || "31337", // 默认本地 Hardhat 网络
  chainName: import.meta.env.VITE_CHAIN_NAME || "Localhost",
  rpcUrl: import.meta.env.VITE_RPC_URL || "http://127.0.0.1:8545",
};

