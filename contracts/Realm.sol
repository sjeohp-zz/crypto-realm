// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Realm is ERC721, ReentrancyGuard {
	using SafeMath for uint256;

	address private _owner;

	uint256 public constant MAX_ELEMENTS = 808;
	uint256 public constant PRICE = 1 * 10**16;
	uint256 public constant MAX_CLAIM = 8;

	// About a week
	uint256 public constant auctionLength = 45500;

	uint256 public constant NUM_TERRAIN = 10;
	uint256 public constant NUM_RESOURCES = 16;
	uint256 public constant MAX_EDGES = 6;
	uint256 public constant MAX_CONTENTS = 16;

	uint256[MAX_ELEMENTS] public cellTerrain;
	uint256[MAX_ELEMENTS][3] public cellResources;
	
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

	string[NUM_RESOURCES] public resourceTypes = [
		"uranium-235",
		"uranium-238",
		"oil",
		"coal",
		"lithium",
		"gold",
		"silver",
		"nickel",
		"copper",
		"zinc",
		"tin",
		"lead",
		"iron",
		"silicon",
		"mithril",
		"groundwater"
	];

	uint256[NUM_RESOURCES] public resourceAbundance = [
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
		init();
	}
	
	function pause() external {
		require(msg.sender == _owner);
		_paused = true;
	}

	function unpause() external {
		require(msg.sender == _owner);
		_paused = false;
	}

	function init() internal {
		uint r = 0;		
		for (uint i=0; i<NUM_RESOURCES; i++) {
			r += resourceAbundance[i];
		}

		for (uint i=0; i<MAX_ELEMENTS; i++) {
			uint256 rand = uint256(keccak256(abi.encodePacked(i)));

			// Set terrain
			cellTerrain[i] = rand % r;
			
			// Number of resources
			uint256 _n = 6;
			uint nres = 0;
			if (rand % _n < 1) {
				nres = 2;
			} else if (rand % _n < 3) {
				nres = 1;
			}
			
			// Set resources
			for (uint x=0; x<nres; x++) {
				uint256 acc = 0;
				uint j = 0;
				while (acc < rand) {
					acc += resourceAbundance[j];
					j += 1;
				}
				cellResources[i][x] = j;
			}

			// Set remaining slots out of bounds
			for (uint x=nres; x<_n; x++) {
				cellResources[i][x] = NUM_RESOURCES;
			}
		}
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

	function _checkPath(uint256[] memory path) internal view returns (bool) {
		bool validEdges = true;
		for (uint i=0; i<path.length; i++) {
			require(i < MAX_ELEMENTS, "Cell index");
			bool validEdge = false;
			for (uint j=0; j<MAX_EDGES-1; j++) {
				if (edges[i][j] == path[i+1]) validEdge = true;
			}
			validEdges = validEdge;
		}
		return validEdges;
	}

	function takeContentAtPath(uint256[] memory path, uint256 contentIndex) external payable nonReentrant {
		require(path.length >= 0, "Path");
		require(msg.sender == ownerOf(path[0]), "Owner");
		require(contentIndex < MAX_CONTENTS , "Content index");
		require(_contentExists(path[path.length-1], contentIndex), "Nothing there");
		CellContent memory content = cellContents[path[path.length-1]][contentIndex];
		require(msg.value >= content.sealValue, "Value too low");
		require(_checkPath(path));

		IERC721 nft = IERC721(content.contractAddress);
		nft.safeTransferFrom(address(this), msg.sender, content.tokenId);
		cellContents[path[path.length-1]][contentIndex] = CellContent(address(0), 0, address(0), 0);
		emit TakeContent(path[path.length-1], content.contractAddress, content.tokenId, content.sealValue, content.sealOwner, msg.sender);
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

	function tokenURI(uint256 tokenId) override public view returns (string memory) {

		string[3] memory rt;
		uint256 nr = 0;
		if (cellResources[tokenId][1] < NUM_RESOURCES) {
			rt[0] = resourceTypes[cellResources[tokenId][0]];
			rt[1] = resourceTypes[cellResources[tokenId][1]];
			nr = 2;
		} else if (cellResources[tokenId][0] < NUM_RESOURCES) {
			rt[0] = resourceTypes[cellResources[tokenId][0]];
			nr = 1;
		}
		
		return Util._tokenURI(tokenId, terrainTypes[cellTerrain[tokenId]], rt, nr);
    }
	
	event CreateCell(uint256 indexed id);
	event EdgeOffered(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 indexed toCellIndex);
	event EdgeOfferWithdrawn(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 indexed toCellIndex);
	event EdgeCreated(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex);
	event EdgeDestroyed(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex);
	event PutContent(uint256 cellIndex, address indexed contractAddress, uint256 tokenId, uint256 sealValue, address indexed sealOwner);
	event TakeContent(uint256 cellIndex, address indexed contractAddress, uint256 tokenId, uint256 sealValue, address indexed sealOwner, address indexed takenBy);
}

library Util {
	function _tokenURI(uint256 tokenId, string memory _tt, string[3] memory _rt, uint256 _nr) public pure returns (string memory) {
        string[17] memory parts;
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';
        parts[1] = _tt;
		string memory output = string(abi.encodePacked(parts[0], parts[1]));
		if (_nr > 0) {
			parts[2] = '</text><text x="10" y="40" class="base">';
			parts[3] = _rt[0];
			output = string(abi.encodePacked(output, parts[2], parts[3]));
			if (_nr > 1) {
				parts[4] = '</text><text x="10" y="60" class="base">';
				parts[5] = _rt[1];
				output = string(abi.encodePacked(output, parts[4], parts[5]));
			}
		}
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Cell #', toString(tokenId), '", "description": "This is the REALM.", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        return string(abi.encodePacked('data:application/json;base64,', json));
    }
	
	function toString(uint256 value) public pure returns (string memory) {
    // Inspired by OraclizeAPI's implementation - MIT license
    // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

}

/// [MIT License]
/// @title Base64
/// @notice Provides a function for encoding some bytes in base64
/// @author Brecht Devos <brecht@loopring.org>
library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encodes some bytes to the base64 representation
    function encode(bytes memory data) public pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((len + 2) / 3);

        // Add some extra buffer at the end
        bytes memory result = new bytes(encodedLen + 32);

        bytes memory table = TABLE;

        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)

            for {
                let i := 0
            } lt(i, len) {

            } {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)

                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 0xFF))
                out := shl(224, out)

                mstore(resultPtr, out)

                resultPtr := add(resultPtr, 4)
            }

            switch mod(len, 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }

            mstore(result, encodedLen)
        }

        return string(result);
    }
}
