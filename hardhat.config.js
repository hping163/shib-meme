require("@nomicfoundation/hardhat-toolbox");
require("chai")

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  namedAccounts: {
    owner: 0,
    addr1: 1,
    addr2: 2,
  },
};
