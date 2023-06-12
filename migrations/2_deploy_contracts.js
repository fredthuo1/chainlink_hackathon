const Chama = artifacts.require("Chama");
const UserRegistry = artifacts.require("UserRegistry");

module.exports = async function (deployer) {
    await deployer.deploy(UserRegistry);
    const userRegistry = await UserRegistry.deployed();

    const treasurerAddress = "0x6eB0dA3D32b30BfA2E28284Fea04CEc13C74cD99"; // Replace with actual treasurer address
    const priceFeedAddress = "0x5fb1616F78dA7aFC9FF79e0371741a747D2a7F22"; // Replace with actual price feed address

    await deployer.deploy(
        Chama,
        treasurerAddress,
        priceFeedAddress,
        userRegistry.address,
        { gas: 5000000 }
    );
    const chama = await Chama.deployed();
};
