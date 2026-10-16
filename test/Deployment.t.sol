// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "./helpers/Fixture.sol";
import {NightFrogs} from "../src/NightFrogs.sol";
import {FrogRenderer} from "../src/FrogRenderer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Test-only analogue of the launch's static-bytecode factory. Never a launch application.
contract FactoryProbe {
    function deploy(bytes memory initCode, bytes32 salt) external returns (address created) {
        assembly ("memory-safe") { created := create2(0, add(initCode, 32), mload(initCode), salt) }
        require(created != address(0), "factory deployment failed");
    }
}

contract DeploymentTest is Fixture {
    function testApplicationsAndSSTORE2PayloadsFitEthereumLimits() public view {
        address[4] memory apps = [address(art1), address(art2), address(renderer), address(nft)];
        for (uint256 i; i < apps.length; ++i) {
            bytes memory code = apps[i].code;
            assertGt(code.length, 0);
            assertLe(code.length, 24_576);
            for (uint256 j; j < code.length; ++j) {
                uint8 op = uint8(code[j]);
                if (op >= 0x60 && op <= 0x7f) {
                    j += op - 0x5f;
                    continue;
                }
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden application opcode");
            }
        }
        bytes memory first = art1.dataPointer().code;
        bytes memory second = art2.dataPointer().code;
        assertEq(first[0], bytes1(0));
        assertEq(second[0], bytes1(0));
        assertLe(first.length, 24_576);
        assertLe(second.length, 24_576);
        assertEq(art1.recordCount(), 19);
        assertEq(art2.recordCount(), 81);
    }

    function testConstructorsUseNoExternalDependenciesAndFactoryNeverOwns() public {
        vm.chainId(1);
        address launchOwner = 0x6C4c78f2C3bDf4C4318Fe305FB1C8BC1694d19b5;
        address productionCoordinator = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;
        vm.etch(nft.IMD(), hex"");
        assertEq(productionCoordinator.code.length, 0);
        FactoryProbe factory = new FactoryProbe();
        string[4] memory names = [
            "FrogArt1.sol:FrogArt1",
            "FrogArt2.sol:FrogArt2",
            "FrogRenderer.sol:FrogRenderer",
            "NightFrogs.sol:NightFrogs"
        ];
        address[4] memory deployed;
        uint256 beforeGas = gasleft();
        for (uint256 i; i < names.length; ++i) {
            bytes memory initCode = vm.getCode(names[i]);
            if (i == 2) initCode = bytes.concat(initCode, abi.encode(deployed[0], deployed[1]));
            if (i == 3) {
                initCode = bytes.concat(initCode, abi.encode(launchOwner, productionCoordinator, deployed[2]));
            }
            assertLe(initCode.length, 49_152);
            deployed[i] = factory.deploy(initCode, bytes32(i));
        }
        emit log_named_uint(
            "Complete application deployment gas (including test overhead)", beforeGas - gasleft()
        );
        NightFrogs launched = NightFrogs(deployed[3]);
        assertEq(launched.owner(), launchOwner);
        assertEq(launched.treasury(), launchOwner);
        assertTrue(launched.owner() != address(factory));
        assertEq(launched.coordinator(), productionCoordinator);
        assertEq(address(launched.renderer()), deployed[2]);
        assertEq(launched.totalSupply(), 0);
        assertEq(launched.subscriptionId(), 0);
    }

    function testRendererConstructorDoesNotProbeStores() public {
        address emptyA = makeAddr("empty art A");
        address emptyB = makeAddr("empty art B");
        FrogRenderer emptyRenderer = new FrogRenderer(emptyA, emptyB);
        assertEq(address(emptyRenderer.art1()), emptyA);
        assertEq(address(emptyRenderer.art2()), emptyB);
    }

    function testConstructorsRejectInvalidStaticParameters() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new NightFrogs(address(0), address(coordinator), address(renderer));
        vm.expectRevert(NightFrogs.InvalidAddress.selector);
        new NightFrogs(owner, address(0), address(renderer));
        vm.expectRevert(NightFrogs.InvalidAddress.selector);
        new NightFrogs(owner, address(coordinator), address(0));
        vm.expectRevert(FrogRenderer.InvalidArtStore.selector);
        new FrogRenderer(address(0), address(art2));
    }
}
