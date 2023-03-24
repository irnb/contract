# Contributor Guidelines

## How to contribute

1. Clone the repository
2. NOTICE: change git config if you want to contribute to the project anonymously
   ```
   git config user.name "Your Anon Name"
   git config user.email "your_anon@mail.com"
   ```
3. Create a new branch
   ```
   git checkout -b my-new-feature
   ```
4. Make your changes
5. Commit your changes
   ```
   git commit -am 'Add some feature'
   ```
6. Push to the branch
   ```
   git push origin my-new-feature
   ```
7. Create a new Pull Request
8. wait for review, discussion and merge

## How workspace is organized

- `ABI/` - ethers standard ABI files for contracts. these files are generated automatically when project get compiled by `hardhat`

- `contracts/` - all contracts are here

- `scripts/` - hardhat scripts for deployment and testing

- `test/` - all hardhat tests are here

- `test/foundry/` - foundry test

- `.env.example` - example of .env file you need this for running hardhat scripts

- `hardhat.config.ts` - hardhat config file

- `foundry.config.ts` - foundry config file

- `package.json` - npm package file

- `tsconfig.json` - typescript config file

- `remappings.txt` - remappings for vscode. this file is used for vscode solidity plugin to resolve imports correctly 

## Workspace commands

- setup workspace
  ```
  npm install
  forge install
  ```

- install dependencies
  ```
  HH:
  npm install package-name
  npm install --save-dev package-name

  Foundry:
  forge install package-name
  ```
  please after installing new dependencies run `forge remappings > remappings.txt` to update remappings file for vscode solidity plugin
- compile contracts
  ```
    HH:
    npx hardhat compile

    Foundry:
    forge build
    ```
- run tests
    ```
    HH:
    npx hardhat test
    
    Foundry:
    forge test
    ```
- deploy contracts
    ```
    HH:
    npx hardhat run --network <network> scripts/deploy_script_name.ts
    ```
- run gas snapshot
    ```
    HH:
    REPORT_GAS=true npx hardhat test

    Foundry:
    forge snapshot
    ```
- run coverage
    ```
    HH:
    npx hardhat coverage
    foundry coverage

    