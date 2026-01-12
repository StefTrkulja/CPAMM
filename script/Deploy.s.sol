// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {Factory} from "../src/Factory.sol";
import {Router} from "../src/Router.sol";
import {Pair} from "../src/Pair.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Mock token ERC20 za testiranje
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
			// Initial mint za testiranje, 1 milion tokena
        _mint(msg.sender, 1000000 * 10 ** 18); 
    }
    
    // Mint funkcija za testiranje 
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Deploy is Script {
   
	  Factory public factory;
    Router public router;
    MockToken public tokenA;
    MockToken public tokenB;
    Pair public pair;

    function run()
        external
        returns (
            Factory,
            Router,
            MockToken,
            MockToken,
            Pair
        )
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        factory = new Factory();
        console.log("Factory deployed at:", address(factory));

        router = new Router(address(factory));
        console.log("Router deployed at:", address(router));

        tokenA = new MockToken("Token A", "TKNA");
        console.log("Token A deployed at:", address(tokenA));
        
        tokenB = new MockToken("Token B", "TKNB");
        console.log("Token B deployed at:", address(tokenB));

        address pairAddress = factory.createPair(
            address(tokenA),
            address(tokenB)
        );
        pair = Pair(pairAddress);
        console.log("Pair created at:", pairAddress);

        vm.stopBroadcast();

        return (factory, router, tokenA, tokenB, pair);
    }
}
