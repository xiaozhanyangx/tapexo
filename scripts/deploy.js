// X Layer mainnet:  set -a; source /workspace/.gas.env; set +a; DEPLOYER_KEY=$OPERATOR_KEY OPERATOR_ADDRESS=$OPERATOR_ADDRESS \
//                     npx hardhat run scripts/deploy.js --network xlayer
// env: DEPLOYER_KEY, OPERATOR_ADDRESS, REVEAL_DELAY (blocks, default 3; X Layer blocks are ~1 s)
// Then: set RAFFLE_CONTRACT (and keep CHAIN_ID=196) in worker/wrangler.toml and redeploy the worker.
const hre = require("hardhat");
async function main() {
  const op = process.env.OPERATOR_ADDRESS; if (!op) throw new Error("OPERATOR_ADDRESS required");
  const { chainId } = await hre.ethers.provider.getNetwork();
  console.log("network", hre.network.name, "chainId", chainId.toString(), "operator", op);
  const f = await hre.ethers.getContractFactory("XRaffle");
  const c = await f.deploy(op, BigInt(process.env.REVEAL_DELAY || 3));
  console.log("deploy tx:", c.deploymentTransaction().hash);
  await c.waitForDeployment();
  console.log("XRaffle deployed:", await c.getAddress(), "→ set RAFFLE_CONTRACT in worker");
}
main().catch((e) => { console.error(e); process.exit(1); });
