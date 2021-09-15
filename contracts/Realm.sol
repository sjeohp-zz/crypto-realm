// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Base64.sol";
import "./Util.sol";

contract Realm is ERC721, ReentrancyGuard {
	using SafeMath for uint256;

	address private _owner;

	uint256 public constant MAX_ELEMENTS = 808;
	uint256 public constant PRICE = 1 * 10**16;
	uint256 public constant MAX_CLAIM = 8;

	// About a week
	uint256 public constant auctionLength = 45500;

	uint256 public constant MAX_EDGES = 6;
	uint256 public constant MAX_CONTENTS = 16;

	// IPFS hash
	string[MAX_ELEMENTS] public cellDescriptionIds;

	CellContent[MAX_ELEMENTS][MAX_CONTENTS] public cellContents;

	uint256[MAX_ELEMENTS][MAX_EDGES] public edges;

	uint256[MAX_ELEMENTS][MAX_EDGES] public edgesOffered;
	
	mapping (uint256 => EdgeOfferFrom[]) public edgeOffersReceived;

	struct CellContent {
		address contractAddress;
		uint256 tokenId;
		address sealOwner;
		uint256 sealValue;
	}

	struct EdgeOfferFrom {
		uint256 fromCellIndex;
		uint256 fromEdgeIndex;
	}

	string[] public terrainTypes = [
		"Mountain",
		"Grassland",
		"River",
		"Jungle",
		"Lake",
		"Sea",
		"Cave",
		"Desert",
		"Forest",
		"Tundra",
	];

	string[] public resourceTypes = [
		"Uranium-235",
		"Uranium-238",
		"Oil",
		"Coal",
		"Lithium",
		"Gold",
		"Silver",
		"Nickel",
		"Copper",
		"Zinc",
		"Tin",
		"Lead",
		"Iron",
		"Silicon",
		"Mithril",
		"Groundwater"
	];

	uint256[] public resourceAbundance = [
		1,
		10,
		4,
		10,
		4,
		8,
		8,
		8,
		8,
		8,
		8,
		8,
		10,
		10,
		1,
		4
	];
    
	bool private _paused = false;

	uint public auctionStartBlock;
	uint public auctionEndBlock;

	constructor() ERC721("Realm", "R") {
		_owner = _msgSender();
	}
	
	function pause() external {
		require(msg.sender == _owner);
		_paused = true;
	}

	function unpause() external {
		require(msg.sender == _owner);
		_paused = false;
	}

	// Assign an IPFS pointer to a description.
	function setCellDescriptionId(uint256 cellIndex, string memory descId) external {
		require(cellIndex < MAX_ELEMENTS, "Cell index");
		require(msg.sender == ownerOf(cellIndex), "Owner");
		cellDescriptionIds[cellIndex] = descId;
	}

	function _contentExists(uint256 cellIndex, uint256 contentIndex) internal view returns (bool) {
		return cellContents[cellIndex][contentIndex].sealOwner != address(0);
	}

	function putContent(uint256 cellIndex, uint256 contentIndex, address contractAddress, uint256 tokenId, uint256 sealValue) external nonReentrant {
		require(cellIndex < MAX_ELEMENTS, "Cell index");
		require(contentIndex < MAX_CONTENTS, "Content index");
		require(!_contentExists(cellIndex, contentIndex), "Content already");
		require(msg.sender == ownerOf(cellIndex), "Owner");

		IERC721 nft = IERC721(contractAddress);
		nft.safeTransferFrom(msg.sender, address(this), tokenId);
		cellContents[cellIndex][contentIndex] = CellContent(contractAddress, tokenId, msg.sender, sealValue);
		emit PutContent(cellIndex, contractAddress, tokenId, sealValue, msg.sender);
	}

	function takeContentAtPath(uint256 cellIndex, uint256 contentIndex) external payable nonReentrant {
		require(cellIndex < MAX_ELEMENTS, "Cell index");
		require(contentIndex < MAX_CONTENTS , "Content index");
		require(msg.sender == ownerOf(cellIndex), "Owner");
		require(_contentExists(cellIndex, contentIndex), "Nothing there");
		CellContent memory content = cellContents[cellIndex][contentIndex];
		require(msg.value >= content.sealValue, "Value too low");

		IERC721 nft = IERC721(content.contractAddress);
		nft.safeTransferFrom(address(this), msg.sender, content.tokenId);
		cellContents[cellIndex][contentIndex] = CellContent(address(0), 0, address(0), 0);
		emit TakeContent(cellIndex, content.contractAddress, content.tokenId, content.sealValue, content.sealOwner, msg.sender);
	}

	// Offer to connect one cell to another.
	function offerEdge(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex) external {
		require(fromCellIndex < MAX_ELEMENTS, "Cell index");
		require(fromEdgeIndex < MAX_EDGES, "Edge index");
		require(toCellIndex < MAX_ELEMENTS, "Cell index");
		require(msg.sender == ownerOf(fromCellIndex), "Owner");

		edgesOffered[fromCellIndex][fromEdgeIndex] = toCellIndex;
		
		uint noffers = edgeOffersReceived[toCellIndex].length;
		for (uint256 i = 0; i < noffers; i++) {
			if (edgeOffersReceived[toCellIndex][i].fromCellIndex == fromCellIndex && edgeOffersReceived[toCellIndex][i].fromEdgeIndex == fromEdgeIndex) return;
		}
		edgeOffersReceived[toCellIndex].push(EdgeOfferFrom(fromCellIndex, fromEdgeIndex));
		emit EdgeOffered(fromCellIndex, fromEdgeIndex, toCellIndex);
	}

	function withdrawEdgeOffer(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex) external {
		require(fromCellIndex < MAX_ELEMENTS, "Cell index");
		require(fromEdgeIndex < MAX_EDGES, "Edge index");
		require(toCellIndex < MAX_ELEMENTS, "Cell index");
		require(msg.sender == ownerOf(fromCellIndex), "Owner");

		_removeEdgeOffer(fromCellIndex, fromEdgeIndex);
		emit EdgeOfferWithdrawn(fromCellIndex, fromEdgeIndex, toCellIndex);
	}

	function _removeEdgeOffer(uint256 fromCellIndex, uint256 fromEdgeIndex) internal {
		if (edgesOffered[fromCellIndex][fromEdgeIndex] < MAX_ELEMENTS) {
			uint256 toCellIndex = edgesOffered[fromCellIndex][fromEdgeIndex];

			edgesOffered[fromCellIndex][fromEdgeIndex] = MAX_ELEMENTS;
		
			uint noffers = edgeOffersReceived[toCellIndex].length;
			for (uint256 i = 0; i < noffers; i++) {
				if (edgeOffersReceived[toCellIndex][i].fromCellIndex == fromCellIndex && edgeOffersReceived[toCellIndex][i].fromEdgeIndex == fromEdgeIndex) {
					edgeOffersReceived[toCellIndex][i] = EdgeOfferFrom(MAX_ELEMENTS, MAX_EDGES);
					return;
				}
			}
		}
	}

	function acceptEdgeOffer(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex) external {
		require(fromCellIndex < MAX_ELEMENTS, "Cell index");
		require(fromEdgeIndex < MAX_EDGES, "Edge index");
		require(toCellIndex < MAX_ELEMENTS, "Cell index");
		require(toEdgeIndex < MAX_EDGES, "Edge index");
		require(msg.sender == ownerOf(toCellIndex), "Owner");
		require(edgesOffered[fromCellIndex][fromEdgeIndex] == toCellIndex, "Offer withdrawn");

		_removeEdgeOffer(fromCellIndex, fromEdgeIndex);

		edges[fromCellIndex][fromEdgeIndex] = toCellIndex;
		edges[toCellIndex][toEdgeIndex] = fromCellIndex;
		emit EdgeCreated(fromCellIndex, fromEdgeIndex, toCellIndex, toEdgeIndex);
	}

	function destroyEdge(uint256 cellIndex, uint256 edgeIndex) external {
		require(cellIndex < MAX_ELEMENTS, "Cell index");
		require(edgeIndex < MAX_EDGES, "Edge index");
		require(msg.sender == ownerOf(cellIndex), "Owner");
		
		uint256 toCellIndex = edges[cellIndex][edgeIndex];
		uint256 toEdgeIndex;
		for (uint i = 0; i < MAX_EDGES; i++) {
			if (edges[toCellIndex][i] == cellIndex) toEdgeIndex = i;
		}

		edges[toCellIndex][toEdgeIndex] = MAX_ELEMENTS;
		edges[cellIndex][edgeIndex] = MAX_ELEMENTS;
		emit EdgeDestroyed(toCellIndex, toEdgeIndex, cellIndex, edgeIndex);
	}

	function withdrawAll() external payable {
		require(msg.sender == _owner);
		uint256 balance = address(this).balance;
		require(balance > 0);
		_widthdraw(_owner, address(this).balance);
	}

	function _widthdraw(address _address, uint256 _amount) internal {
		(bool success, ) = _address.call{value: _amount}("");
		require(success, "Transfer failed.");
  	}

  	function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override(ERC721) {
		super._beforeTokenTransfer(from, to, tokenId);
	}

	function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
		return super.supportsInterface(interfaceId);
	}

	function emitCellData(uint256 tokenId) public {
		uint256 rterr = uint256(keccak256(abi.encodePacked("TERRAIN", tokenId)));
		uint256 rnres = uint256(keccak256(abi.encodePacked("NRESOURCES", tokenId)));
		
		string memory terrain = terrainTypes[rterr % terrainTypes.length];
		string[2] memory resources;
		
		uint256 _n = 3;
		uint256 nres = 0;
		if (rnres % _n < 1) {
			nres = 2;		
			resources[0] = Util.pickResource(tokenId, "FIRST", resourceTypes, resourceAbundance, "");
			resources[1] = Util.pickResource(tokenId, "SECOND", resourceTypes, resourceAbundance, resources[0]);
		} else if (rnres % _n < 3) {
			nres = 1;
			resources[0] = Util.pickResource(tokenId, "FIRST", resourceTypes, resourceAbundance, "");
		}
		
		emit GenerateTokenURI(terrain, resources[0], resources[1]);
	}

	function tokenURI(uint256 tokenId) override public view returns (string memory) {
		uint256 rterr = uint256(keccak256(abi.encodePacked("TERRAIN", tokenId)));
		uint256 rnres = uint256(keccak256(abi.encodePacked("NRESOURCES", tokenId)));
		
		string memory terrain = terrainTypes[rterr % terrainTypes.length];
		string[2] memory resources;
		
		uint256 _n = 3;
		uint256 nres = 0;
		if (rnres % _n < 1) {
			nres = 2;		
			resources[0] = Util.pickResource(tokenId, "FIRST", resourceTypes, resourceAbundance, "");
			resources[1] = Util.pickResource(tokenId, "SECOND", resourceTypes, resourceAbundance, resources[0]);
		} else if (rnres % _n < 3) {
			nres = 1;
			resources[0] = Util.pickResource(tokenId, "FIRST", resourceTypes, resourceAbundance, "");
		}
		
		return Util._tokenURI(tokenId, terrain, resources, nres);
    }
	
	event CreateCell(uint256 indexed id);
	event EdgeOffered(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 indexed toCellIndex);
	event EdgeOfferWithdrawn(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 indexed toCellIndex);
	event EdgeCreated(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex);
	event EdgeDestroyed(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex);
	event PutContent(uint256 cellIndex, address indexed contractAddress, uint256 tokenId, uint256 sealValue, address indexed sealOwner);
	event TakeContent(uint256 cellIndex, address indexed contractAddress, uint256 tokenId, uint256 sealValue, address indexed sealOwner, address indexed takenBy);
	event GenerateTokenURI(string terrain, string resource0, string resource1);
}

