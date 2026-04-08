# COMP5568 项目开发进度记录

> 最后更新：2026-04-05
> 用途：下次与 Claude 对话时，把这个文件内容告诉 Claude，可以直接继续开发

---

## 项目概述

- **课程**：PolyU COMP5568
- **题目**：Decentralized Lending & Borrowing Protocol（去中心化借贷协议）
- **项目路径**：`/Users/hk00579ml/Documents/bybit-paywork/COMP5521Project`
- **区块链**：Hardhat 本地链（chainId: **1337**，port: 8545）
- **前端**：React 18 + Vite + ethers.js v6 + Tailwind CSS
- **前端地址**：http://localhost:3000

---

## 当前完成状态

### ✅ 已完成并测试通过

#### 智能合约（Solidity）
- `contracts/Stablecoin.sol` — ERC-20 稳定币 C5D（1 C5D = $1），含 faucet 函数
- `contracts/MockWETH.sol` — ERC-20 模拟 WETH（1 WETH = $2000），含 faucet 函数
- `contracts/LendingPool.sol` — 核心借贷合约，完整实现：
  - `deposit()` 存款 ✅ 测试通过
  - `withdraw()` 取款 ✅ 界面完成
  - `borrow()` 借款（带 LTV 检查）✅ 测试通过
  - `repay()` 还款 ✅ 界面完成
  - 健康因子 `getHealthFactor()` 计算 ✅ 显示正确
  - 动态利率模型（线性模型，基于 Utilization Rate）✅ 实测 50% 利用率时 Supply APY 3.15% / Borrow APY 7%
  - 按区块累计利息（Compound 风格的 index-based 利息）✅
  - 各类 view 函数供前端调用 ✅

#### 部署工具
- `hardhat.config.cjs` — Hardhat 2 配置，chainId = **1337**
- `scripts/deploy.cjs` — 部署脚本，自动写入前端地址配置，给前5个账户各铸造 100,000 C5D + 50 WETH
- `package.json` — 根目录脚本（compile/node/deploy/frontend）

#### 前端页面（React）
- `frontend/src/components/lending/Dashboard.jsx` — 总览页（总抵押、总债务、健康因子、市场数据）✅ 测试通过
- `frontend/src/components/lending/LendingPage.jsx` — 存款/取款页面 ✅ 测试通过
- `frontend/src/components/lending/BorrowPage.jsx` — 借款/还款页面 ✅ 测试通过
- `frontend/src/config/lendingContracts.js` — 合约地址配置（已更新真实地址）
- `frontend/src/config/lendingAbis.js` — 合约 ABI
- `frontend/src/App.jsx` — 路由已更新

#### 文档
- `README.md` — 完整项目说明（中文）
- `REQUIREMENTS.md` — 作业要求（中文）
- `PROGRESS.md` — 本文件
- `GUIDE.md` — 操作手册（给组员看的）

---

### 🔲 待完成（Bonus 功能，选做但加分）

| 功能 | 优先级 | 说明 |
|------|--------|------|
| 清算机制（Liquidation） | ⭐⭐⭐ 高 | 当 HF < 1 时，允许第三方清算，获得 5-10% 奖励 |
| Flash Loan（闪电贷） | ⭐⭐ 中 | 在单笔交易内借出并偿还，无需抵押 |
| Chainlink 预言机 | ⭐⭐ 中 | 替换 hardcode 价格，接入 Sepolia 测试网 |
| NFT 作为抵押品 | ⭐⭐⭐ 高 | 创新加分项，已有 NFT 合约可复用 |

---

## 当前部署地址（本地链 chainId 1337）

```
C5D Stablecoin: 0x0B306BF915C4d645ff596e518fAf3F9669b97016
MockWETH:       0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1
LendingPool:    0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE
```

> ⚠️ 每次重启 Hardhat 节点后需要重新部署（地址会变），重新部署后前端配置自动更新。

---

## 启动命令

```bash
# 终端 1：启动本地区块链
npm run node

# 终端 2：部署合约（等终端1启动后）
npm run deploy

# 终端 3：启动前端
npm run frontend
# → 访问 http://localhost:3000
```

---

## 重要技术说明

### chainId 必须用 1337
- 31337 会被 MetaMask Blockaid 拦截，无法确认交易
- 已修改 `hardhat.config.cjs` 和 `scripts/deploy.cjs`

### MetaMask 常见问题及解决
| 问题 | 解决方案 |
|------|----------|
| "查看提醒"按钮无法点击 | Settings → Advanced → Reset Account |
| 显示 ETH 余额为 0 | Settings → Advanced → Reset Account |
| 网络费报红/余额不足 | Reset Account 后重试 |
| 安全警告拦截 | Settings → Security & Privacy → 关闭 Blockaid |

### 前端读写分离
所有 view 函数（读数据）使用 `readProvider`（直连 Hardhat，不经 MetaMask），避免 MetaMask 的已知 bug。写操作（存款、借款等）仍通过 MetaMask signer 发送交易。

### 利率模型
```
U   = totalBorrowed / totalSupplied          （利用率）
借款 APR = baseRate + slope × U
存款 APR = 借款APR × U × 0.9               （10% 留给协议储备）
```
C5D: baseRate=2%, slope=10% → 实测 50% 利用率时 Supply 3.15% / Borrow 7%
WETH: baseRate=2%, slope=20%

### 编译命令（特殊）
企业网络 TLS 证书问题，编译需要加环境变量（已内置到 npm scripts）：
```bash
NODE_TLS_REJECT_UNAUTHORIZED=0 npx hardhat compile --config hardhat.config.cjs
```

---

## 下次对话时告诉 Claude 的话

> "我在做 COMP5568 作业，项目路径是 /Users/hk00579ml/Documents/bybit-paywork/COMP5521Project，请先读 PROGRESS.md 了解进度，然后帮我继续开发。目前基础功能已完成并测试通过，我想接下来做 [xxx] 功能。"
