# COMP5568 — 去中心化借贷协议

> 香港理工大学 COMP5568 期末小组项目

基于以太坊的去中心化借贷协议，参考 Aave / Compound 设计，支持两种 ERC-20 资产、超额抵押借贷、动态利率模型和实时风险仪表盘。

---

## 功能完成情况

### 基础功能（必做）

| 功能 | 状态 |
|------|------|
| MetaMask 钱包集成 | ✅ 完成 |
| 两种 ERC-20 代币（C5D 稳定币 + WETH） | ✅ 完成 |
| 存款（Supply） | ✅ 完成 |
| 取款（Withdraw） | ✅ 完成 |
| 借款（Borrow） | ✅ 完成 |
| 还款（Repay） | ✅ 完成 |
| 超额抵押逻辑 | ✅ 完成 |
| 健康因子实时计算与显示 | ✅ 完成 |
| LTV（贷款价值比）限制 | ✅ 完成 |
| 动态利率模型（基于利用率的线性模型） | ✅ 完成 |
| 按区块累计利息（Index 机制） | ✅ 完成 |
| 仪表盘（总抵押、总债务、APY、健康因子） | ✅ 完成 |

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 智能合约 | Solidity ^0.8.20、OpenZeppelin |
| 本地区块链 | Hardhat 2（chainId: 31337） |
| 前端框架 | React 18、Vite、Tailwind CSS |
| Web3 交互 | ethers.js v6 |
| 路由 | React Router v6 |

---

## 智能合约说明

| 合约 | 说明 |
|------|------|
| `Stablecoin.sol` | C5D 稳定币，模拟 1 C5D = $1，含测试水龙头（每次领 1000 C5D） |
| `MockWETH.sol` | 模拟 WETH，1 WETH = $2000，含测试水龙头（每次领 10 WETH） |
| `LendingPool.sol` | 核心借贷协议，包含所有借贷逻辑 |

### 风险参数

| 资产 | LTV | 清算阈值 | 基础利率 | 斜率 |
|------|-----|---------|---------|------|
| C5D | 80% | 85% | 2%/年 | 10%/年 |
| WETH | 75% | 80% | 2%/年 | 20%/年 |

### 利率模型（线性）

```
利用率 U      = 总借款 / 总存款
借款年利率    = 基础利率 + 斜率 × U
存款年利率    = 借款年利率 × U × 90%（10% 留给协议储备）
```

### 健康因子

```
HF = Σ(存款余额 × 代币价格 × 清算阈值) / Σ(借款余额 × 代币价格)

HF ≥ 1.0 → 仓位安全
HF < 1.0 → 可被清算
```

---

## 项目结构

```
COMP5521Project/
├── contracts/
│   ├── Stablecoin.sol          # C5D 稳定币
│   ├── MockWETH.sol            # 模拟 WETH
│   └── LendingPool.sol         # 核心借贷协议
├── scripts/
│   └── deploy.cjs              # 部署脚本
├── frontend/
│   └── src/
│       ├── components/
│       │   ├── lending/
│       │   │   ├── Dashboard.jsx     # 仪表盘（总览）
│       │   │   ├── LendingPage.jsx   # 存款 / 取款
│       │   │   └── BorrowPage.jsx    # 借款 / 还款
│       │   ├── Marketplace.jsx       # NFT 市场（原有保留）
│       │   ├── MyNFTs.jsx
│       │   ├── MintNFT.jsx
│       │   └── MintStablecoin.jsx
│       ├── config/
│       │   ├── lendingContracts.js   # 合约地址（部署后自动更新）
│       │   └── lendingAbis.js        # 合约 ABI
│       ├── context/
│       │   └── Web3Context.jsx       # 全局钱包状态
│       └── App.jsx                   # 路由配置
├── hardhat.config.cjs
├── package.json
├── REQUIREMENTS.md             # 作业原始要求（中文）
├── PROGRESS.md                 # 开发进度记录
└── README.md                   # 本文件
```

---

## 启动方法

需要开 **3 个终端窗口**。

### 第一步 — 启动本地区块链（终端 1）
```bash
npm run node
```
Hardhat 启动后会打印 20 个测试账户及其私钥，**复制第一个私钥备用**。

### 第二步 — 部署合约（终端 2，等第一步启动后）
```bash
npm run deploy
```
自动部署 3 个合约，并将地址写入 `frontend/src/config/lendingContracts.js`。

### 第三步 — 启动前端（终端 3）
```bash
npm run frontend
# 访问 http://localhost:5173
```

### 第四步 — 配置 MetaMask
在 MetaMask 中添加自定义网络：

| 字段 | 值 |
|------|-----|
| 网络名称 | Localhost 8545 |
| RPC URL | http://127.0.0.1:8545 |
| Chain ID | 31337 |
| 货币符号 | ETH |

然后将第一步的私钥导入 MetaMask。

### 第五步 — 领取测试代币
进入 **Dashboard → 测试水龙头**，领取免费的 C5D 和 WETH。

---

## 常用命令

| 命令 | 说明 |
|------|------|
| `npm run node` | 启动 Hardhat 本地区块链 |
| `npm run compile` | 编译 Solidity 合约 |
| `npm run deploy` | 部署合约到本地链 |
| `npm run frontend` | 启动 React 前端 |
