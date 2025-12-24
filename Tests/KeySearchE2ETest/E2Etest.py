from bitcoinlib.keys import Key
import random
import subprocess
import os 

KEYS_PER_S = 150000000 # The max keys per second, that CryptKeySearch will check
TEST_DURATION_S = 30 # How long should the test take?
NUM_MATCHES = 5000

ADDR_FILE_PATH = f"{os.getcwd()}/test.tsv"
DB_FILE_PATH = f"{os.getcwd()}/test.sqlite3"

KEY_SEARCH_PATH = "../../build/Build/Products/Release/keysearch"

numKeysForTest = KEYS_PER_S * TEST_DURATION_S

startKey_hex = "3c7d7a4a2c30fe15479e47d3a3fbced151f77f19fe3bd912c072ba5ffa21b5f1" # Randomly generated start key
startKey = int(startKey_hex, 16)
endKey = startKey + numKeysForTest


randomKeys = set()
addresses = set()
for i in range(0, NUM_MATCHES):
    randomKey = random.randint(startKey, endKey)
    randomKeys.add(f"{format(randomKey,'064x').upper()}")
    k = Key(import_key=randomKey)
    addr = k.address()
    addresses.add(addr)
    # print(f"Key: {randomKey:064x} Legacy Addr Comp: {k.address()}")

with open(ADDR_FILE_PATH, "w", encoding="utf-8") as f:
    for a in addresses: 
        f.write(a + "\n")
        

print(f"{len(randomKeys)} test addresses generated")


# Create the DB file from addresses list
result = subprocess.run([KEY_SEARCH_PATH, "load", ADDR_FILE_PATH, "-d", DB_FILE_PATH], capture_output=True, text=True, check=True)
print(result.stdout)
print(result.stderr)
#print("Return code:", result.returncode)

result = subprocess.run([KEY_SEARCH_PATH, "run", "-s", f"{startKey_hex}:{endKey:064x}","-d", DB_FILE_PATH], capture_output=True, text=True, check=True)
print(result.stdout)
print(result.stderr)
#print("Return code:", result.returncode)

addrErrorCnt = 0 
keyErrorCnt = 0 
# Checking results
for key in randomKeys:
    if result.stdout.find(f"Private key found: {key}") == -1:
        print(f"FAILED: Private key not found: {key}")
        keyErrorCnt+=1
for a in addresses: 
    if result.stdout.find(f"{a}") == -1:
        print(f"FAILED: Address not found: {a}")
        addrErrorCnt+=1
        
if(addrErrorCnt > 0 or keyErrorCnt > 0):
    print("❌ FAILED")
else:
    print("✅ PASS")    
    
   
