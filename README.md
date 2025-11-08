# CryptKeyFinder
A tool for solving Bitcoin puzzles on OSX. The application is build to run on Apple Silicon GPUs for high performance.
Other, similar tools like BitCrack stopped working entirely for OSX users since Apple switched to it's new Silicon Chips.
This application aims to be a better replacement for such legacy tools which have many limitations. 
Bitcrack for example only supports legacy addresses and has no support for modern Bitcoin addresses like Taproot or SegWit.

CryptKeyFinder is build entirely from scratch for OSX and utilizes Apples Metal framework for high performance.

**NOTE!**
- The application is still new and under heavy development.
- So far I have focussed on functionality and performance optimization still needs to be done.
- If something isn't working or you miss a certain feature, then please let me know so I can improve the project. Please open an [new Issue](https://github.com/eztam-/CryptKeyFinder/issues/new) in such cases.
- Support is very welcome, feel free to submit a merge request.
- I never programmed in Swift or Metal before starting this project. Therefore I'm also very happy for any code review or feedback. 
- This application was build for solving bitcoin puzzles. Any illegal usage is prohibited.

**Important**
Many hours of work went and will go into this project. If you like it and want to support it, please do:
- Give this Github repository a star. :star:
- Support development by contributing to the code :computer:
- Any, even small donation is welcome :money_with_wings: BTC: 39QmdfngkM3y4KJbwrgspNRQZvwow5BFpg

 

## Build

To build the application you need to install XCode from the App Store first.

Within the project directory run the following command

```
xcodebuild -scheme CryptKeySearch -destination 'platform=macOS' -configuration Release -derivedDataPath ./build
```
After a successfull build, you can run the application:
```
./build/Build/Products/Release/CryptKeyFinder
```

## Usage
Before we can start the key search, we must fill the database with a list of addresses we want to include in the private key search.
This is only required once and we can use the application afterwards for finding keys many thimes, without repeating this step.
Only you wan't to use a different address list, you have to repeat this step again.
The address list must be provided in a file, whereby each line contains exactly one address.

```
CryptKeySearch import _<path_to_your_file>_  
```

Once the database was popuated we can start the key search from a given start address:
```
CryptKeySearch keysearch -s 0000000000000000000000000000000000000000000000000000000000000001
```



## Architecture
The GPU is used for the heavy elliptic curve (secp256k1) computations, i.e. generating public keys and computing hashes (SHA256 + RIPEMD160) for massive numbers of private keys in parallel.

The CPU handles:
* Managing key ranges and work distribution to the GPU kernels.
* Maintaining and querying the Bloom filter, which stores the target addresses (or their hash160 values).
* Checking candidate hashes returned from the GPU against the Bloom filter to quickly discard non-matching results.
* False positive results from the bloomfilter will be checked against the blockchain (Can we configure the bloomfilter such that the probability is so low, that we don't need that? How is this done in BitCrack?)

### Address Types
|Type|Address Type|Starts With|Address Format|Public Key Format|Supported|
|----|------------|-----------|--------------|-----------------|---------|
|Legacy|P2PKH — Pay-to-PubKey-Hash|1|Base58Check|Compresses or Uncompressed|Yes|
|Legacy|P2SH — Pay-to-Script-Hash|3|Base58Check|Compresses or Uncompressed|TBD|
|SegWit|P2WPKH — Pay-to-Witness-PubKey-Hash|bc1q|Bech32|Compressed|TBD|
|SegWit|P2WSH — Pay-to-Witness-Script-Hash|bc1q|Bech32|Compressed|TBD|
|SegWit|P2SH-P2WPKH — Nested SegWit (Compatibility address)|3|Base58Check|Compressed|TBD|
|Taproot|P2TR — Pay-to-Taproot|bc1p|Bech32m|TBC|No|

### Address Calculation from Private Key
The following diagram shows the individual stepps to calculate a bitcoin address from a private key
<img src="https://raw.githubusercontent.com/eztam-/BitCrackOSX/refs/heads/main/img/calc_by_address_types.drawio.svg">

To make the cracking loop as efficient as possible, we only want the non-reversible calculations within the loop.
The reversible calculations will be reversed before inserting the addresses from the file into the bloomfilter. 
This leads us to the following application architecture:

<img src="https://raw.githubusercontent.com/eztam-/BitCrackOSX/refs/heads/main/img/architecture.drawio.svg">

The bloom filter ingestion only happens once during application start.

### Endians
host-endian == little-endian on Apple Silicon GPUs/CPUs<br>
For convenience I have kept all in- and outputs to GPU shaders in host-endian.<br>
Input and output endiangs by shader:<br>
host-endian --> SHA256    --> host-endian<br>
host-endian --> RIPEMD160 --> host-endian<br>



## Disclaimer

This software was developed **solely for educational purposes and solving Bitcoin puzzles**.  

**Important:** Any illegal use of this software is strictly prohibited. The authors **do not endorse or accept any liability** for misuse, including but not limited to unauthorized access to systems, theft of cryptocurrencies, or any other illegal activity.

By using this software, you agree to comply with all applicable laws in your jurisdiction.

Permission is granted to use, copy, modify, and distribute this software **only for legal purposes** and for educational purposes such as solving Bitcoin puzzles. Any illegal use is prohibited.

### AI-Generated Content

Parts of this application, including code and documentation, were **generated or assisted by AI tools**. All generated content was reviewed and integrated by the project author.
