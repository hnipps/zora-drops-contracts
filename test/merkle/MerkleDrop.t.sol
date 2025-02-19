// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Vm} from "forge-std/Vm.sol";
import {DSTest} from "ds-test/test.sol";
import {IERC721Drop} from "../../src/interfaces/IERC721Drop.sol";
import {ERC721Drop} from "../../src/ERC721Drop.sol";
import {ZoraFeeManager} from "../../src/ZoraFeeManager.sol";
import {DummyMetadataRenderer} from "../utils/DummyMetadataRenderer.sol";
import {FactoryUpgradeGate} from "../../src/FactoryUpgradeGate.sol";
import {ERC721DropProxy} from "../../src/ERC721DropProxy.sol";

import {MerkleData} from "./MerkleData.sol";

contract ZoraNFTBaseTest is DSTest {
    ERC721Drop zoraNFTBase;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    DummyMetadataRenderer public dummyRenderer = new DummyMetadataRenderer();
    ZoraFeeManager public feeManager;
    MerkleData public merkleData;
    address public constant DEFAULT_OWNER_ADDRESS = address(0x23499);
    address payable public constant DEFAULT_FUNDS_RECIPIENT_ADDRESS =
        payable(address(0x21303));
    address payable public constant DEFAULT_ZORA_DAO_ADDRESS =
        payable(address(0x999));
    address public constant mediaContract = address(0x123456);

    modifier setupZoraNFTBase() {
        zoraNFTBase.initialize({
            _contractName: "Test NFT",
            _contractSymbol: "TNFT",
            _initialOwner: DEFAULT_OWNER_ADDRESS,
            _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            _editionSize: 10,
            _royaltyBPS: 800,
            _salesConfig: IERC721Drop.SalesConfiguration({
                publicSaleStart: 0,
                publicSaleEnd: 0,
                presaleStart: 0,
                presaleEnd: 0,
                publicSalePrice: 0,
                maxSalePurchasePerAddress: 0,
                presaleMerkleRoot: bytes32(0)
            }),
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: ""
        });

        _;
    }

    function setUp() public {
        vm.prank(DEFAULT_ZORA_DAO_ADDRESS);
        feeManager = new ZoraFeeManager(250, DEFAULT_ZORA_DAO_ADDRESS);
        vm.prank(DEFAULT_ZORA_DAO_ADDRESS);

        address impl = address(
            new ERC721Drop(address(1234), FactoryUpgradeGate(address(0)))
        );
        address payable newDrop = payable(
            address(new ERC721DropProxy(impl, ""))
        );
        zoraNFTBase = ERC721Drop(newDrop);
        merkleData = new MerkleData();
    }

    function test_MerklePurchaseActiveSuccess() public setupZoraNFTBase {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: 0,
            presaleStart: 0,
            presaleEnd: type(uint64).max,
            publicSalePrice: 0 ether,
            maxSalePurchasePerAddress: 0,
            presaleMerkleRoot: merkleData
                .getTestSetByName("test-3-addresses")
                .root
        });
        vm.stopPrank();

        MerkleData.MerkleEntry memory item;

        item = merkleData.getTestSetByName("test-3-addresses").entries[0];
        vm.deal(address(item.user), 1 ether);
        vm.startPrank(address(item.user));

        zoraNFTBase.purchasePresale{value: item.mintPrice}(
            1,
            item.maxMint,
            item.mintPrice,
            item.proof
        );
        assertEq(zoraNFTBase.saleDetails().maxSupply, 10);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 1);
        require(
            zoraNFTBase.ownerOf(1) == address(item.user),
            "owner is wrong for new minted token"
        );
        vm.stopPrank();

        item = merkleData.getTestSetByName("test-3-addresses").entries[1];
        vm.deal(address(item.user), 1 ether);
        vm.startPrank(address(item.user));
        zoraNFTBase.purchasePresale{value: item.mintPrice * 2}(
            2,
            item.maxMint,
            item.mintPrice,
            item.proof
        );
        assertEq(zoraNFTBase.saleDetails().maxSupply, 10);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 3);
        require(
            zoraNFTBase.ownerOf(2) == address(item.user),
            "owner is wrong for new minted token"
        );
        vm.stopPrank();
    }

    function test_MerklePurchaseAndPublicSalePurchaseLimits()
        public
        setupZoraNFTBase
    {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: type(uint64).max,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: 1,
            presaleMerkleRoot: merkleData.getTestSetByName("test-2-prices").root
        });
        vm.stopPrank();

        MerkleData.MerkleEntry memory item;

        item = merkleData.getTestSetByName("test-2-prices").entries[0];
        vm.deal(address(item.user), 1 ether);
        vm.startPrank(address(item.user));

        vm.expectRevert(IERC721Drop.Presale_TooManyForAddress.selector);
        zoraNFTBase.purchasePresale{value: item.mintPrice * 3}(
            3,
            item.maxMint,
            item.mintPrice,
            item.proof
        );

        zoraNFTBase.purchasePresale{value: item.mintPrice * 1}(
            1,
            item.maxMint,
            item.mintPrice,
            item.proof
        );
        zoraNFTBase.purchasePresale{value: item.mintPrice * 1}(
            1,
            item.maxMint,
            item.mintPrice,
            item.proof
        );
        assertEq(zoraNFTBase.saleDetails().totalMinted, 2);
        require(
            zoraNFTBase.ownerOf(1) == address(item.user),
            "owner is wrong for new minted token"
        );

        vm.expectRevert(IERC721Drop.Presale_TooManyForAddress.selector);
        zoraNFTBase.purchasePresale{value: item.mintPrice * 1}(
            1,
            item.maxMint,
            item.mintPrice,
            item.proof
        );

        zoraNFTBase.purchase{value: 0.1 ether}(1);
        require(
            zoraNFTBase.ownerOf(3) == address(item.user),
            "owner is wrong for new minted token"
        );
        vm.expectRevert(IERC721Drop.Purchase_TooManyForAddress.selector);
        zoraNFTBase.purchase{value: 0.1 ether}(1);
        vm.stopPrank();
    }

    function test_MerklePurchaseAndPublicSaleEditionSizeZero() public {
        zoraNFTBase.initialize({
            _contractName: "Test NFT",
            _contractSymbol: "TNFT",
            _initialOwner: DEFAULT_OWNER_ADDRESS,
            _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            _editionSize: 0,
            _royaltyBPS: 800,
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: "",
            _salesConfig: IERC721Drop.SalesConfiguration({
                publicSaleStart: 0,
                publicSaleEnd: 0,
                presaleStart: 0,
                presaleEnd: 0,
                publicSalePrice: 0,
                maxSalePurchasePerAddress: 0,
                presaleMerkleRoot: bytes32(0)
            })
        });

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: type(uint64).max,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: 1,
            presaleMerkleRoot: merkleData.getTestSetByName("test-2-prices").root
        });
        vm.stopPrank();

        MerkleData.MerkleEntry memory item;

        item = merkleData.getTestSetByName("test-2-prices").entries[0];
        vm.deal(address(item.user), 1 ether);
        vm.startPrank(address(item.user));

        vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
        zoraNFTBase.purchasePresale{value: item.mintPrice}(
            1,
            item.maxMint,
            item.mintPrice,
            item.proof
        );
        vm.stopPrank();
    }

    function test_MerklePurchaseInactiveFails() public setupZoraNFTBase {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        // block.timestamp returning zero allows sales to go through.
        vm.warp(100);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: 0,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0 ether,
            maxSalePurchasePerAddress: 0,
            presaleMerkleRoot: merkleData
                .getTestSetByName("test-3-addresses")
                .root
        });
        vm.stopPrank();
        vm.deal(address(0x10), 1 ether);

        vm.startPrank(address(0x10));
        MerkleData.MerkleEntry memory item = merkleData
            .getTestSetByName("test-3-addresses")
            .entries[0];
        vm.expectRevert(IERC721Drop.Presale_Inactive.selector);
        zoraNFTBase.purchasePresale{value: item.mintPrice}(
            1,
            item.maxMint,
            item.mintPrice,
            item.proof
        );
    }
}
