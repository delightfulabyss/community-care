<<<<<<< HEAD
# [community-care](https://github.com/filecoin-project/devgrants/issues/719)
=======
# Project Description 
>>>>>>> d31ff1f (Update readme)

This project is a prototype of a system to facilitate community giving and support. It contains two early-stage algorithms: one for splitting up a common pool of funds based on how many donations were previously given to each request and one for generating token rewards based on a donation-to-request ratio.

## How to Read This Repo
- Navigate to `packages/backend/contracts` for the smart contracts
- `packages/frontend` has boilerplate for a future front-end

## Quick Start Notes

1.  Run `yarn chain` or `npm run chain` to start a local hardhat environment
2.  Open another terminal and `cd` into the app's directory
3.  Run `yarn deploy` or `npm run deploy` to deploy the contracts locally
4.  Run `yarn dev` or `npm run dev` to start your Next dev environment

## Technologies

This project is built with the following open source libraries, frameworks and languages.
| Tech | Description |
| --------------------------------------------- | ------------------------------------------------------------------ |
| [Next.js](https://nextjs.org/) | React Framework |
| [Hardhat](https://hardhat.org/) | Ethereum development environment |
| [hardhat-deploy](https://www.npmjs.com/package/hardhat-deploy) | A Hardhat Plugin For Replicable Deployments And Easy Testing |
| [WAGMI](https://wagmi.sh/) | A set of React Hooks for Web3 |
| [RainbowKit](https://www.rainbowkit.com/docs/introduction) | RainbowKit is a React library that makes it easy to add wallet connection to your dapp. |
