// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {ReputationLedger} from "../src/ReputationLedger.sol";
import {MosaicHub} from "../src/MosaicHub.sol";
import {GuardianModule} from "../src/GuardianModule.sol";
import {ISomniaAgents} from "../src/interfaces/ISomniaAgents.sol";

/// @notice One-shot deployment script for Mosaic on Somnia.
/// @dev    Run with:
///         forge script script/Deploy.s.sol \
///             --rpc-url $SOMNIA_RPC_URL \
///             --private-key $DEPLOYER_PK \
///             --broadcast -vvvv
contract Deploy is Script {
    // Somnia testnet platform contract (per docs.somnia.network).
    address constant SOMNIA_TESTNET = 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776;
    address constant SOMNIA_MAINNET = 0x5E5205CF39E766118C01636bED000A54D93163E6;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address deployer = vm.addr(pk);
        address treasury = vm.envOr("TREASURY", deployer);
        address somnia = vm.envOr("SOMNIA_AGENTS", SOMNIA_TESTNET);

        console2.log("deployer:", deployer);
        console2.log("treasury:", treasury);
        console2.log("somnia agents platform:", somnia);

        vm.startBroadcast(pk);

        AgentRegistry registry = new AgentRegistry(deployer);
        ReputationLedger reputation = new ReputationLedger(deployer);
        MosaicHub hub = new MosaicHub(
            deployer, registry, reputation, ISomniaAgents(somnia), treasury
        );
        reputation.setHub(address(hub));

        GuardianModule guardian = new GuardianModule(hub, registry);
        // Default Guardian fee: 0.05 STT per scan.
        guardian.selfRegister(
            0.05 ether,
            "data:application/json,%7B%22name%22%3A%22ProtocolGuardian%22%2C%22kind%22%3A%22security%22%2C%22version%22%3A%221.0.0%22%7D"
        );

        vm.stopBroadcast();

        console2.log("AgentRegistry:    ", address(registry));
        console2.log("ReputationLedger: ", address(reputation));
        console2.log("MosaicHub:        ", address(hub));
        console2.log("GuardianModule:   ", address(guardian));
        console2.log("Guardian agent id:", guardian.guardianAgentId());
    }
}
