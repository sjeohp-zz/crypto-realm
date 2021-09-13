// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./RealmTypes.sol";

contract Realm is ERC721Enumerable, ERC721Burnable, Ownable, Pausable {
	using SafeMath for uint256;

	uint256 public constant MAX_ELEMENTS = 808;
	uint256 public constant PRICE = 1 * 10**17;
	uint256 public constant MAX_CLAIM = 8;

	uint256 private nextCell = 0;

	uint public constant NUM_TERRAIN = 10;
	uint public constant MAX_EDGES = 6;
	uint public constant MAX_CONTENTS = 16;

	string[MAX_ELEMENTS] public cellTerrain;
	
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

	string[NUM_TERRAIN] public terrainTypes = [
		"mountain",
		"grassland",
		"river",
		"jungle",
		"lake",
		"sea",
		"cave",
		"desert",
		"forest",
		"tundra"
	];

	// TODO set cell terrain
	constructor() ERC721("Realm", "R") {
		
	}

	function random(string memory input) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(input)));
    }

	function _contentExists(uint256 cellIndex, uint256 contentIndex) internal view returns (bool) {
		return cellContents[cellIndex][contentIndex].sealOwner != address(0);
	}

	function putContent(uint256 cellIndex, uint256 contentIndex, address contractAddress, uint256 tokenId, uint256 sealValue) external payable {
		require(cellIndex < MAX_ELEMENTS, "Cell index");
		require(contentIndex < MAX_CONTENTS, "Content index");
		require(!_contentExists(cellIndex, contentIndex), "Content already");
		require(msg.sender == ownerOf(cellIndex), "Owner");

		IERC721 nft = IERC721(contractAddress);
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
		cellContents[cellIndex][contentIndex] = CellContent(contractAddress, tokenId, msg.sender, sealValue);
		emit RealmTypes.PutContent(cellIndex, contractAddress, tokenId, sealValue, msg.sender);
    }

	function takeContent(uint256 cellIndex, uint256 contentIndex) external payable whenNotPaused {
		require(cellIndex < MAX_ELEMENTS, "Cell index");
		require(contentIndex < MAX_CONTENTS , "Content index");

		CellContent memory content = cellContents[cellIndex][contentIndex];

		require(_contentExists(cellIndex, contentIndex), "Nothing there");
		require(msg.sender == ownerOf(cellIndex), "Owner");
		require(msg.value >= content.sealValue, "Value too low");

		IERC721 nft = IERC721(content.contractAddress);
		nft.safeTransferFrom(address(this), msg.sender, content.tokenId);
		cellContents[cellIndex][contentIndex] = CellContent(address(0), 0, address(0), 0);
		emit RealmTypes.TakeContent(cellIndex, content.contractAddress, content.tokenId, content.sealValue, content.sealOwner, msg.sender);
	}

	// Connect two cells you own.
	function createEdge(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex) external whenNotPaused {
		require(fromCellIndex < MAX_ELEMENTS, "Cell index");
		require(fromEdgeIndex < MAX_EDGES, "Edge index");
		require(toCellIndex < MAX_ELEMENTS, "Cell index");
		require(toEdgeIndex < MAX_EDGES, "Edge index");
		require(msg.sender == ownerOf(fromCellIndex), "Owner");
		require(msg.sender == ownerOf(toCellIndex), "Owner");

		_removeEdgeOffer(fromCellIndex, fromEdgeIndex);

		edges[fromCellIndex][fromEdgeIndex] = toCellIndex;
		edges[toCellIndex][toEdgeIndex] = fromCellIndex;
		emit RealmTypes.EdgeCreated(fromCellIndex, fromEdgeIndex, toCellIndex, toEdgeIndex);
	}

	// Offer to connect one cell to another.
	function offerEdge(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex) external whenNotPaused {
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
		emit RealmTypes.EdgeOffered(fromCellIndex, fromEdgeIndex, toCellIndex);
	}

	function withdrawEdgeOffer(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex) external whenNotPaused {
		require(fromCellIndex < MAX_ELEMENTS, "Cell index");
		require(fromEdgeIndex < MAX_EDGES, "Edge index");
		require(toCellIndex < MAX_ELEMENTS, "Cell index");
		require(msg.sender == ownerOf(fromCellIndex), "Owner");

		_removeEdgeOffer(fromCellIndex, fromEdgeIndex);
		emit RealmTypes.EdgeOfferWithdrawn(fromCellIndex, fromEdgeIndex, toCellIndex);
	}

	function _removeEdgeOffer(uint256 fromCellIndex, uint256 fromEdgeIndex) internal {
		require(fromCellIndex < MAX_ELEMENTS, "Cell index");
		require(fromEdgeIndex < MAX_EDGES, "Edge index");
		
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

	function acceptEdgeOffer(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex) external whenNotPaused {
		require(fromCellIndex < MAX_ELEMENTS, "Cell index");
		require(fromEdgeIndex < MAX_EDGES, "Edge index");
		require(toCellIndex < MAX_ELEMENTS, "Cell index");
		require(toEdgeIndex < MAX_EDGES, "Edge index");
		require(msg.sender == ownerOf(toCellIndex), "Owner");
		require(edgesOffered[fromCellIndex][fromEdgeIndex] == toCellIndex, "Offer withdrawn");

		_removeEdgeOffer(fromCellIndex, fromEdgeIndex);

		edges[fromCellIndex][fromEdgeIndex] = toCellIndex;
		edges[toCellIndex][toEdgeIndex] = fromCellIndex;
		emit RealmTypes.EdgeCreated(fromCellIndex, fromEdgeIndex, toCellIndex, toEdgeIndex);
	}

	function destroyEdge(uint256 toCellIndex, uint256 toEdgeIndex) external whenNotPaused {
		require(toCellIndex < MAX_ELEMENTS, "Cell index");
		require(toEdgeIndex < MAX_EDGES, "Edge index");
		require(msg.sender == ownerOf(toCellIndex), "Owner");
		
		uint256 fromCellIndex = edges[toCellIndex][toEdgeIndex];
		uint256 fromEdgeIndex;
		for (uint i = 0; i < MAX_EDGES; i++) {
			if (edges[fromCellIndex][i] == toCellIndex) fromEdgeIndex = i;
		}

		edges[fromCellIndex][fromEdgeIndex] = MAX_ELEMENTS;
		edges[toCellIndex][toEdgeIndex] = MAX_ELEMENTS;
		emit RealmTypes.EdgeDestroyed(fromCellIndex, fromEdgeIndex, toCellIndex, toEdgeIndex);
	}

	function claim(uint256 cellIndex, uint256 count) external payable whenNotPaused {
		require(cellIndex + count <= MAX_ELEMENTS, "Cell index");
        require(msg.value >= PRICE.mul(count), "Value too low");
		require(count <= MAX_CLAIM);
		for (uint i=0; i<count; i++) {
			require(ownerOf(cellIndex + i) == address(0), "Already claimed");
		}
		for (uint i=0; i<count; i++) {
			_safeMint(msg.sender, cellIndex + i);
			emit RealmTypes.CreateCell(cellIndex);
		}
		nextCell += count;
		while (ownerOf(nextCell) != address(0)) {
			nextCell += 1;
			if (nextCell == MAX_ELEMENTS) return;
		}
	}

	function claimNext() external payable whenNotPaused {
		require(nextCell < MAX_ELEMENTS, "Cell index");
        require(msg.value >= PRICE, "Value too low");
		require(ownerOf(nextCell) == address(0), "Already claimed");
		_safeMint(msg.sender, nextCell);
		emit RealmTypes.CreateCell(nextCell);
		nextCell += 1;
		while (ownerOf(nextCell) != address(0)) {
			nextCell += 1;
			if (nextCell == MAX_ELEMENTS) return;
		}
	}

    function cellsOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

	function pause() public onlyOwner whenNotPaused {
		_pause();
    }

	function unpause() public onlyOwner whenPaused {
		_unpause();
    }

    function withdrawAll() public payable onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0);
        _widthdraw(owner(), address(this).balance);
    }

    function _widthdraw(address _address, uint256 _amount) private {
        (bool success, ) = _address.call{value: _amount}("");
        require(success, "Transfer failed.");
    }

    function _beforeTokenTransfer(
		address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
