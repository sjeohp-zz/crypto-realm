// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Base64.sol";

library Util {
    function pickResource(uint256 tokenId, string memory keyPrefix, string[] memory resources, uint256[] memory resourceAbundance) public pure returns (string memory) {
        uint resourceAbundanceSum = 0;		
		for (uint i=0; i<resourceAbundance.length; i++) {
			resourceAbundanceSum += resourceAbundance[i];
		}
		uint256 r = uint256(keccak256(abi.encodePacked(keyPrefix, tokenId))) % resourceAbundanceSum;
        uint256 acc = 0;
		uint x = 0;
		while (acc < r) {
			acc += resourceAbundance[x];
			x += 1;
		}
		return resources[x];
    }
    
	function _tokenURI(uint256 tokenId, string memory _tt, string[2] memory _rt, uint256 _nr) public pure returns (string memory) {
        string[8] memory parts;
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';
        parts[1] = _tt;
		string memory output = string(abi.encodePacked(parts[0], parts[1]));
		if (_nr > 0) {
			parts[2] = '</text><text x="10" y="40" class="base">[ ';
			parts[3] = _rt[0];
			parts[4] = ' ]</text>';
			output = string(abi.encodePacked(output, parts[2], parts[3], parts[4]));
			if (_nr > 1) {
			    parts[5] = '</text><text x="10" y="60" class="base">[ ';
				parts[6] = _rt[1];
				parts[7] = ' ]</text>';
				output = string(abi.encodePacked(output, parts[5], parts[6], parts[7]));
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

