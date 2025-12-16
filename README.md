# CryptKeySearch
A tool for solving Bitcoin puzzles on OSX. The application is build and optimized to run on Apple Silicon GPUs for high performance.
Other, similar tools like BitCrack stopped working for OSX users since Apple switched to it's new Silicon Chips.
This application aims to be a better replacement that adds additional features like support for modern Bitcoin addresses like Taproot or SegWit.

CryptKeySearch is build entirely from scratch for OSX and utilizes Apples Metal framework for high performance. The project was heavily inspired from [BitCrack](https://github.com/brichard19/BitCrack) so kudos to brichard19.

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
- Donations are very welcome :money_with_wings: BTC: 39QmdfngkM3y4KJbwrgspNRQZvwow5BFpg

 

## Build

Don't run directly from XCode for other reasons than development, since it is significantly slower there and the ui is broken compared to creating a releasebuild and running it from terminal!

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
# Run with given start key
keysearch run -s 0000000000000000000000000000000000000000000000000000000000000001

# Run with random start key within a given range
keysearch run -s RANDOM:400000000000000000:7fffffffffffffffff 

# For more options see:
keysearch -h
keysearch load -h
keysearch run -h
```

## Fine Tuning
Major parameters to fine tune for a specific GPU:
- **Grid Size** This is the number of threads being submitted per batch. If choosen too high, the application will use up too much memory and might slow down the entire OS.
    
- **Keys per Thread** This should be choosen as high as possible. However if choosen too high, there will be memory overruns and the application will still appear running (seamingly even very fast) but is actually broken and doesn't macth anymore. So always thes if the app still matches keys when experimenting with this settings.

If both parameters are choosen too low, then the number of batches per second will go up which is also a limiting factor (see performance optimization below). You might want to increase the ring buffer size as well.


## Roadmap
- Improve performance
    - secp256k1 EC claculations are the main bottleneck and need o be improved. This will significantly improve the general performance
    - Put all the different pipeline steps into one commandBuffer to avoid back and forth between CPU and GPU between the different steps.
    - Switch to metal 4 classes which promise better performance
    - Improve tthe bloomfilter query performance and DB queries
- The loading of addresses from file into the DB and Bloomfilter is very slow, when loading large files >1GB. This needs to be improved
    - possible solutions
        - Disk-backed key/value store (LMDB / RocksDB / LevelDB)
        - Memory-mapped sorted file + binary search
        - In mem hash map? -> the limit is the memory
   
- Next
    - Remove private key increment from metal and do in in swift async. There is no need to do this on the GPU
    - Do the bloomfilter result check async (ring buffer?)
    - improve field_mul sinc it is the most used one
        
## Performance Improvement Notes
- One problematic bottleneck is the commandBuffer work submission to the GPU and the fact, that we can control the GPU saturation only ba the following parameters:
    - Properties.KEYS_PER_THREAD = 1024
    - Properties.GRID_SIZE = 1024 x 32
  On an M1 Pro GPU this is just OK but not perfect and on faster GPUs we will run into real issues here. If we increase these two parameters, then also the memory preasure will increase because of the X and Y point buffers which increase linearly.
  So we could become memory bound if we increase this values to high. On the other hand we must increase this values to keep the GPU busy and to avoid CPU overhead, since the command encoding takes some CPU time.
  Currently I have solved this issue by introducing a ring buffer which works OK with size 9 on M1 Pro. However the batches are processed even on M1 almost to fast which can be seen in the live stats (4-5 batches per second). 
  Looking at bitcracks CL code for a reference, there is just a CPU sided loop that calls the step kernel per iteration. But in Bitcrack OpenCL, there is almost no CPU overhead as we have in Metal 3 so we need to find a different solution.
  Possible solutions:
  1. Swith to Metal 4 which supports more efficient command encoding (this is partly done in branch "metal4").
  2. Increase the ring buffer size even further.
    
- Mixing Jacobian and Affine (“Mixed Addition”).
  this is what other high performance OpenCL based secp256k1 implementations like hashcats do as well and I have adopted this in my implementation already.<br>
    _If both points are in Jacobian form, addition is slower because both have Z ≠ 1._<br>
   _But in most scalar multiplication algorithms (like the precomputed-table method we're using), one point is fixed — e.g. (i+1)*G — and can be stored in affine form (x, y) with Z = 1._

- What should bring measurable performance improvement:
    - Replacing the current field_inv with Fermat's Little Theorem with an optimized addition chain as. e.g. done in bitcoin-core lib

Before merging some steps into one command buffer I measured the following performance. So secp256k1

## Known Issues
- Loading very large address sets (GBs) causes either the bloom filter to fail. Or what I rather suspect, is an issue with the DB query which might have concurrency issues.
  The problem shows itself, that each singe private key matches.
  
- After running the app for a few hours, the bloomfilter seems to crash. Theres suddenly the MAX amount of matches exceeded and the palse positive rate jumps and stays very high.

- Loading large address files takes very long, which could be improved.

- support for uncompressed keys has been temporary removed  

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
|Type|Address Type|Starts With|Address Format|Public Key Format|Supported|Hash Function|
|----|------------|-----------|--------------|-----------------|---------|-------------|
|Legacy|P2PKH — Pay-to-PubKey-Hash|1|Base58Check|Compresses or Uncompressed|Yes|RIPEMD160(SHA256(pubkey))|
|Legacy|P2SH — Pay-to-Script-Hash|3|Base58Check|Compresses or Uncompressed|TBD|RIPEMD160(SHA256(redeem_script))|
|SegWit|P2WPKH — Pay-to-Witness-PubKey-Hash|bc1q|Bech32|Compressed|Yes|RIPEMD160(SHA256(pubkey))|
|SegWit|P2WSH — Pay-to-Witness-Script-Hash|bc1q|Bech32|Compressed|TBD|SHA256(script)|
|SegWit|P2SH-P2WPKH — Nested SegWit (Compatibility address)|3|Base58Check|Compressed|TBD||
|Taproot|P2TR — Pay-to-Taproot|bc1p|Bech32m|TBC|No|SHA256(xonly_pubkey) → then tweak: `tweaked_pubkey = internal_pubkey + H_tapTweak(internal_pubkey|
|Wrapped SegWit|P2WPKH-P2SH|3||TBC|No|RIPEMD160(SHA256(witness_program))|

### Address Calculation from Private Key
The following diagram shows the individual stepps to calculate a bitcoin address from a private key
<img src="https://raw.githubusercontent.com/eztam-/BitCrackOSX/refs/heads/main/img/calc_by_address_types.drawio.svg">

To make the key search loop as efficient as possible, we only want the non-reversible calculations within the loop.
The reversible calculations will be reversed before inserting the addresses from the file into the bloomfilter. 
This leads us to the following application architecture:

<img src="https://raw.githubusercontent.com/eztam-/BitCrackOSX/refs/heads/main/img/architecture.drawio.svg">

The bloom filter ingestion only happens once during application start.

### Key Search Pipeline
In general, the main bottleneck are the secp256k1 EC calculations which are very compute heavy compared to the rest of the pipeline steps.
In order to make the secp256k1 EC calculations as efficient as possible we need to avoid calculating for each private key a point multiplication to get the corresponding private key.
Instead we run several pub to private key calculation per thread. Each thead then calculates just for the very first private key a costy point pultiplication.
For all consecutive private keys in the same thread we just do a point addition of G to the vreviously calculated point. This is about 30x faster.


### Endians
host-endian == little-endian on Apple Silicon GPUs/CPUs<br>
... TDB





## Stepping Model — Initialization, Hashing, and Batch Progression
The application follows a two-stage GPU processing model designed for maximum throughput:
1. Initialization (init_points_* kernel)
2. Repeated stepping (step_points_* kernel)
This design produces a characteristic and intentional pattern where each stepping pass hashes the current batch of points and then advances them to the next batch.

### 1. Initialization Kernel
The initialization kernel:
- Computes all starting public key points for the grid
- Computes the constant group-step increment ΔG = totalPoints × G
- Prepares chain buffers needed for efficient batch EC addition
**Important:**
The init kernel does not perform any hashing.
After initialization:
- xPtr/yPtr contain the points for batch 0
- No HASH160 results exist yet
This ensures that initialization remains lightweight and optimized.

### 2. Stepping Kernel
Each launch of the stepping kernel performs two operations:

#### A. Hash the current batch of points
For every point:
- Generate the public key (compressed or uncompressed)
- Compute SHA-256
- Compute RIPEMD-160
- Perform Bloom filter queries
- Write results to output buffers
These hash results always correspond to the current batch, i.e., the values in xPtr/yPtr before stepping occurs.

#### B. Advance all points by ΔG
After hashing, the kernel applies the batch-add algorithm:
`P_next = P_current + ΔG`
The updated points (P_next) are written back to xPtr/yPtr, becoming the starting points for the next batch.
This creates an intentional one-batch offset:
- Hash output → Batch N
- Updated xPtr/yPtr → Batch N+

### 3. Why this model is used
This behavior mirrors the original CUDA BitCrack implementation and is chosen because it:
- Maximizes GPU arithmetic reuse
- Keeps the inner loop simple and pipeline-friendly
- Avoids expensive hashing during initialization
- Ensures each stepping pass performs a full batch of search work
Because the initialization kernel does not hash batch 0, the first stepping kernel hashes batch 0, then advances the points to batch 1.

### Summary
- Initialization sets up batch 0 but does not hash it.
- Each stepping kernel launch performs:
  1. Hash current points → produces results for batch N
  2. Add ΔG → updates points to batch N+1
Therefore after each kernel execution:
- HASH160 results correspond to batch N,
- xPtr/yPtr contain the public key points for batch N+1.
This one-batch shift is intentional and an inherent part of the BitCrack GPU algorithm design.


## Disclaimer

This software was developed **solely for educational purposes and solving Bitcoin puzzles**.  

**Important:** Any illegal use of this software is strictly prohibited. The authors **do not endorse or accept any liability** for misuse, including but not limited to unauthorized access to systems, theft of cryptocurrencies, or any other illegal activity.

By using this software, you agree to comply with all applicable laws in your jurisdiction.

Permission is granted to use, copy, modify, and distribute this software **only for legal purposes** and for educational purposes such as solving Bitcoin puzzles. Any illegal use is prohibited.

### AI-Generated Content

Parts of this application, including code and documentation, were **generated or assisted by AI tools**. All generated content was reviewed and integrated by the project author.
