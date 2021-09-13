// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library RealmTypes {

	event CreateCell(uint256 indexed id);
	event EdgeOffered(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex);
	event EdgeOfferWithdrawn(uint256 fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex);
	event EdgeCreated(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex);
	event EdgeDestroyed(uint256 indexed fromCellIndex, uint256 fromEdgeIndex, uint256 toCellIndex, uint256 toEdgeIndex);
	event PutContent(uint256 cellIndex, address indexed contractAddress, uint256 tokenId, uint256 sealValue, address indexed sealOwner);
	event TakeContent(uint256 cellIndex, address indexed contractAddress, uint256 tokenId, uint256 sealValue, address indexed sealOwner, address indexed takenBy);

}
