const Realm = artifacts.require("Realm");
const Util = artifacts.require("Util");
const Base64 = artifacts.require("Base64");

module.exports = async function (deployer) {
	await deployer.deploy(Base64);
	await deployer.link(Base64, [Util, Realm]);
	await deployer.deploy(Util);
	await deployer.link(Util, Realm);
	await deployer.deploy(Realm);
};
