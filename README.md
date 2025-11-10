# CryptKeySearch
A tool for solving Bitcoin puzzles on OSX. The application is build and optimized to run on Apple Silicon GPUs for high performance.
Other, similar tools like BitCrack stopped working for OSX users since Apple switched to it's new Silicon Chips.
This application aims to be a better replacement for such legacy tools which have many limitations. 
Bitcrack for example only supports legacy addresses and has no support for modern Bitcoin addresses like Taproot or SegWit.

CryptKeySearch is build entirely from scratch for OSX and utilizes Apples Metal framework for high performance.

**NOTE!**
- The application is still new and under heavy development.
- So far I have focussed on functionality and performance optimization still needs to be done.
- If something isn't working or you miss a certain feature, then please let me know so I can improve the project. Please open an [new Issue](https://github.com/eztam-/CryptKeySearch/issues/new) in such cases.
- Support is very welcome, feel free to submit a merge request.
- I never programmed in Swift or Metal before starting this project. Therefore I'm also very happy for any code review or feedback. 
- This application was build for solving bitcoin puzzles. Any illegal usage is prohibited.

**Important**
Many hours of work went and will go into this project. If you like it and want to support it, please do:
- Give this Github repository a star. :star:
- Support development by contributing to the code :computer:
- Any, even small donation is welcome :money_with_wings: BTC: 39QmdfngkM3y4KJbwrgspNRQZvwow5BFpg

 

## Build

Don't run directly from XCode for other reasons than development, since it is significantly slower there compared to creating a releasebuild and running it from terminal!

To build the application you need to install XCode from the App Store first.

Within the project directory run the following command

```
xcodebuild -scheme CryptKeySearch -destination 'platform=macOS' -configuration Release -derivedDataPath ./build
```
After a successfull build, you can run the application:
```
cd ./build/Build/Products/Release/

./keysearch -h 
```

## Usage
Before we can start the key search, we must fill the database with a list of addresses we want to include in the private key search.
This is only required once and we can use the application afterwards for finding keys many thimes, without repeating this step.
Only you wan't to use a different address list, you have to repeat this step again.
The address list must be provided in a file, whereby each line contains exactly one address.

```
keysearch load <path_to_your_file> 
```

Once the database was popuated we can start the key search from a given start address:
```
keysearch run -s 0000000000000000000000000000000000000000000000000000000000000001
```

## Current State
- Only supporting compressed legacy keys at the moment (uncompressed and SegWit will be added later)
- Loading large address files (more than a GB) takes very long. (This will be improved)
- Performance depends on various factors like start address (one with many leading zeors perform 10x faster) -> will be improved by optimizing secp256k1 calc
- Maximum observed performance is 1M keys/s on M1 Pro and about 2M keys/s on a M4 Pro. This will be imprufed later by optimizing secp256k1 calc


## Roadmap
- Add better comand line iterface (replacing the command structure)
- Improve performance
    - secp256k1 EC claculations are the main bottleneck and need o be improved. This will significantly improve the general performance
    - Put all the different pipeline steps into one commandBuffer to avoid back and forth between CPU and GPU between the different steps.
    - Switch to metal 4 classes which promise better performance
    - Improve tthe bloomfilter query performance
- The loading of addresses from file into the DB and Bloomfilter is very slow, when loading large files >1GB. This needs to be improved
    - possible solutions
        - Disk-backed key/value store (LMDB / RocksDB / LevelDB)
        - Memory-mapped sorted file + binary search
        - In mem hash map? -> the limit is the memory
        
## secp256k1 Performance Improvement Notes
- Mixing Jacobian and Affine (“Mixed Addition”).
  this is what other high performance OpenCL omplementations like hashcats do as well and I have adopted this in my implementation already.<br>
    _If both points are in Jacobian form, addition is slower because both have Z ≠ 1._<br>
   _But in most scalar multiplication algorithms (like the precomputed-table method we're using), one point is fixed — e.g. (i+1)*G — and can be stored in affine form (x, y) with Z = 1._

## Architecture
The GPU is used for:
* Heavy elliptic curve (secp256k1) computations
* computing hashes (SHA256 + RIPEMD160)
* Iterating over a range of private keys
* Using a bloom filter to verify addresses existing in large datasets (serveral GB)

The CPU handles:
* Managing work distribution to the GPU kernels.
* Reverse calculating addresses to their public key hashes and inserting them into a local database
* Checking bloom filter results against the database to quickly discard false-positive results.


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
