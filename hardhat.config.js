require("@nomicfoundation/hardhat-toolbox");
const accounts = process.env.DEPLOYER_KEY ? [process.env.DEPLOYER_KEY] : [];
module.exports = {
  solidity: { version: "0.8.24", settings: { optimizer: { enabled: true, runs: 200 } } },
  networks: {
    bscTestnet: { url: process.env.BSC_TESTNET_RPC || "https://bsc-testnet-rpc.publicnode.com", chainId: 97, accounts },
    bsc: { url: process.env.BSC_RPC || "https://bsc-dataseed.bnbchain.org", chainId: 56, accounts },
    // X Layer (OKX L2, OP stack, gas token OKB). Production target.
    xlayer: { url: process.env.XLAYER_RPC || "https://rpc.xlayer.tech", chainId: 196, accounts },
    xlayerTestnet: { url: process.env.XLAYER_TESTNET_RPC || "https://testrpc.xlayer.tech/terigon", chainId: 1952, accounts },
  },
  etherscan: {
    apiKey: { xlayer: process.env.OKLINK_API_KEY || "", bsc: process.env.BSCSCAN_API_KEY || "" },
    customChains: [{ network: "xlayer", chainId: 196, urls: { apiURL: "https://www.oklink.com/api/v5/explorer/contract/verify-source-code-plugin/XLAYER", browserURL: "https://www.oklink.com/x-layer" } }],
  },
};
