# BitCrackOsx
A tool for cracking Bitcoin private keys on Apple Silicon GPUs


## Architecture
The GPU is used for the heavy elliptic curve (secp256k1) computations, i.e. generating public keys and computing hashes (SHA256 + RIPEMD160) for massive numbers of private keys in parallel.

The CPU handles:
* Managing key ranges and work distribution to the GPU kernels.
* Maintaining and querying the Bloom filter, which stores the target addresses (or their hash160 values).
* Checking candidate hashes returned from the GPU against the Bloom filter to quickly discard non-matching results.
* False positive results from the bloomfilter will be checked against the blockchain (Can we configure the bloomfilter such that the probability is so low, that we don't need that? How is this done in BitCrack?)





# Endians

host-endian == little-endian

Input and output endiangs by shader:
host-endian --> SHA256    --> host-endian
host-endian --> RIPEMD160 --> host-endian

