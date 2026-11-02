# contracts — XRaffle

tapeXO 的开奖合约（Solidity 0.8.24 + Hardhat），生产部署在 **X Layer 主网（chainId 196）**：`XRaffle` @ [`0x8aD12e97A4B6BEfa375aF004c86655ffe97D83ed`](https://www.oklink.com/x-layer/address/0x8aD12e97A4B6BEfa375aF004c86655ffe97D83ed)，`revealDelay = 3` 块。链上只存哈希，名单和结果文件都在链下（对象存储 / TapeOut 容器）；任何人都能用公开文件 + 公共 RPC 复算全部结果。

产品流程与验证页说明见 tapeXO 主项目文档。

## 目录

```
contracts/
├── contracts/XRaffle.sol     # 主合约
├── scripts/deploy.js         # 部署 XRaffle
├── hardhat.config.js         # 网络与源码验证配置
├── package.json
├── README.md
└── LICENSE
```

## 机制

commit-reveal 抽奖，三步操作都由运营地址发起：

1. **commit**：写入 `entriesHash`、`entryCount`、`winnerCount`、`seedHash`，记录 `commitBlock`。`ref` 只进事件，不占存储。
2. **reveal**：等到 `revealBlock = commitBlock + revealDelay` 之后公开 `seed`，合约校验 `keccak256(seed) == seedHash` 后计算：

   ```
   randomness = keccak256(seed ‖ entriesHash ‖ blockhash(commitBlock + revealDelay))
   ```

   若 reveal 时距目标区块已超过 256 个区块（`blockhash` 返回 0），置 `blockhashMissing = true`，随机数退化为 `keccak256(seed ‖ entriesHash ‖ 0)`。
3. **finalize**：记录 `sha256(results.json 字节)` 到 `Finalized` 事件（每场只能一次，且必须在 reveal 之后）。

中奖序号由纯函数计算，链上链下同一算法：

```
idx_j = keccak256(randomness ‖ uint256 nonce) mod entryCount, nonce = 0,1,2…
        跳过已出现过的索引，取前 winnerCount 个
```

`winnersOf(id)` 即时计算前 `k` 名（不落存储），完整排名由链下 `worker/src/derive.js` 的 `ranking()` 续算到 `entryCount`，两者前 `k` 项必须一致（测试强制校验）。

## 哈希约定

| 值 | 算法 | 来源 |
| --- | --- | --- |
| `entriesHash` | `keccak256(entries.json 原始字节)` | 名单文件 UTF-8 JSON，handles 已小写、去重、升序 |
| `seedHash` | `keccak256(abi.encodePacked(seed))` | 运营方生成，reveal 前后都可校验 |
| `randomness` | 见上文 | 合约计算并存一处 |
| `resultsHash` | `sha256(results.json 原始字节)` | finalize 事件，浏览器可直接对下载文件复算 |

`entries.json` 结构（v1）：

```json
{ "v": 1, "raffle": 1, "entries": ["handle1", "handle2"] }
```

v2 在同一文件里追加 `conditions` 等字段，`entries` 仍是全量未筛选名单（参与条件在开奖后按排名逐位检查）。

## 接口

| 函数 | 权限 | 说明 |
| --- | --- | --- |
| `commit(ref, entriesHash, entryCount, winnerCount, seedHash)` | operator | 新建一场，返回自增 `id`。`entryCount > 0`、`0 < winnerCount <= entryCount`、`winnerCount <= 500`、`seedHash != 0` |
| `reveal(id, seed)` | operator | 校验时间与 seed 后写入 `randomness` |
| `finalize(id, resultsHash)` | operator | 仅 reveal 后、仅一次 |
| `winnersOf(id)` | 任何人 | 未 reveal 时返回空数组 |
| `deriveWinners(randomness, n, k)` | 任何人 | 纯函数，可离线复算 |
| `revealBlock(id)` | 任何人 | 可 reveal 的目标区块 |
| `setOperator(op, enabled)` / `transferOwnership(n)` | owner | 运营地址管理 |

只读公开状态：`owner`、`operators`、`revealDelay`、`raffleCount`、`raffles(id)`。

事件：`OperatorSet`、`Committed`、`Revealed`、`Finalized`。

## 部署

前置：部署地址需有少量 OKB 付 Gas；运营地址即服务端 `OPERATOR_KEY` 对应的地址。

```bash
cd contracts
npm install
DEPLOYER_KEY=<部署私钥> OPERATOR_ADDRESS=<运营地址> REVEAL_DELAY=3 \
  npx hardhat run scripts/deploy.js --network xlayer
```

- 环境变量只写变量名，取值不写进仓库：`DEPLOYER_KEY`、`OPERATOR_ADDRESS`、`REVEAL_DELAY`（区块数，默认 3，X Layer 约 1 秒一块）、`XLAYER_RPC`（可选 RPC）。
- 部署后把地址填入服务端的合约地址配置（例如 Cloudflare Worker 的 `RAFFLE_CONTRACT`，`CHAIN_ID=196`）。
- 源码验证（可选）：`npx hardhat verify --network xlayer <address> <operator> <revealDelay>`，需要 `OKLINK_API_KEY`。

`package.json` 里的快捷命令：`npm run deploy:xlayer`、`npm run deploy:testnet`。

## 网络（hardhat.config.js）

| 网络 | chainId | 用途 |
| --- | --- | --- |
| `xlayer` | 196 | 生产 |
| `xlayerTestnet` | 1952 | 预演 |
| `bsc` / `bscTestnet` | 56 / 97 | 备用 |

## 信任边界

- 链上保证：commit 之后 `entriesHash` / `seedHash` 不可更改；`randomness` 由 seed、名单哈希和目标区块哈希唯一确定；`resultsHash` 只能 finalize 一次。
- 不保证：名单是否等于全部真实参与者（由运营方抓取并公开 `entries.json`）、运营方是否按时 reveal 或不中途放弃、开奖后参与条件检查的准确性。
- 复核方式：下载 `entries.json` / `results.json`，计算哈希，用公共 RPC 读合约数据，按上文公式复算。官方部署地址以外的同名合约与 tapeXO 无关。

## 注意

- 重新部署会换掉合约地址：历史场次的数据仍留在旧合约上，`results.json` 里记录的是生成时使用的合约地址，验证时从该文件读取，因此旧场次仍可复算。

