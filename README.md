# BitCrackOsx
A tool for cracking Bitcoin private keys on Apple Silicon GPUs


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

