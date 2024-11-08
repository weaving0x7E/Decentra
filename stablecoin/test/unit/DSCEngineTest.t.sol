// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelpConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MockV3Aggregator} from "../mock/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public LIQ = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    uint256 public COLLATERAL_TO_COVER = 20 ether;
    uint256 public AMOUNT_TO_MINT = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;

        console.log(engine.getLatestPrice(weth));
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testWeatherDepositCollateralSuccessfulOrNot() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        assertEq(IERC20(weth).balanceOf(address(engine)), AMOUNT_COLLATERAL);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier mint(uint256 amount) {
        vm.startPrank(USER);
        engine.mintDsc(amount);
        vm.stopPrank();
        _;
    }

    function testBurnDsc() public depositedCollateral mint(10) {
        vm.startPrank(USER);
        dsc.approve(address(engine), 10);
        uint256 allowance = IERC20(dsc).allowance(USER, address(engine));
        console.log(allowance);

        engine.burnDsc(5);

        vm.stopPrank();
        uint256 collateralDeposited;
        uint256 dscAmount;
        (collateralDeposited, dscAmount) = engine.getAccountInfo(USER, weth);
        assertEq(5, dscAmount);
    }

    function testMintDscTooMuch() public depositedCollateral {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__BreakHealthFactor.selector);
        engine.mintDsc(AMOUNT_COLLATERAL * 1e18);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralWhenEthPriceDown() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL * 1000);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 999e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_COLLATERAL * 1000);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL * 1000);
        vm.stopPrank();

        assertEq(ERC20Mock(weth).balanceOf(USER), AMOUNT_COLLATERAL);
    }

    function testIfNoNeedLiquidate() public depositedCollateral mint(10) {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOK.selector);
        engine.liquidate(weth, USER, 10);
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);

        ERC20Mock(weth).mint(LIQ, COLLATERAL_TO_COVER);

        vm.startPrank(LIQ);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_TO_COVER);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQ);
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
    }
}
