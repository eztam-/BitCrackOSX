This is end to end test executing the application via comand line.

Installing dependencies:
```
brew install gmp
brew link gmp
Adjust paths belwo from previous output
CFLAGS=-I/opt/homebrew/Cellar/gmp/6.3.0/include LDFLAGS=-L/opt/homebrew/Cellar/gmp/6.3.0/lib uv add fastecdsa
uv add bitcoinlib 
```

