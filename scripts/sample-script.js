const { ethers } = require("hardhat");

async function main() {
  let [owner] = await ethers.getSigners();
  //v2上 atToken 1:2 wzyToken, v3上 atToken 1:1.5, 所以在v2上借wzyToken,然后到v3上可以换更多的atToken,还款后有盈利
  let wzyToken = "0xCf9306BEC295AbDc242904C3aA276C3C5Eff4d2B";
  let atToken = "0x75B9b00BBE2822A3d46E4b5e493D80c69050A001";
  let factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"; //v2 uniswap factory
  let swapRouter = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; //v3 uniswap router
  let devAddress = "0x6aCB38f47C14594F58614B89Aac493e1Ab3B4C34";

  let FlashLoanV2 = await ethers.getContractFactory("FlashLoanV2");

  let flashLoanV2 = await FlashLoanV2.deploy(
    wzyToken,
    atToken,
    factory,
    swapRouter,
    devAddress
  );

  await flashLoanV2.deployed();
  console.log("flashLoanV2:" + flashLoanV2.address);

  let loanAmount = ethers.utils.parseUnits("1000", 18); //借1000个wzyToken
  await flashLoanV2.flashSwap(wzyToken, loanAmount, { gasLimit: 8000000 })
  console.log("已发起闪电贷");

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
