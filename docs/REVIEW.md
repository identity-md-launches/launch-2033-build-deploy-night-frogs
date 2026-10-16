# Local adversarial review

This is a builder's review of the delivered source and local tests, not an independent audit or a live-chain fork test. The independent launch review has not been replaced by these results. No signing, broadcasting, wallet configuration, explorer write, or factory transaction was performed.

## Findings addressed locally

- **Odd smallest-unit prices cannot split exactly.** Reject zero and odd prices. Bound the maximum so 500 paid mints at any allowed prices cannot overflow cumulative accounting. Verify the smallest allowed price and random even prices in tests.
- **An apparent token success may underpay or overcharge.** Use `SafeERC20`, check the payer's actual debit, check the collection's actual receipt, then verify both recipient increases and the unchanged preexisting collection balance. Mocks exercise missing/false returns, fees on collection/burn/treasury, excess sender debit and a reverting second payout. Every failure rolls back earlier transfers, counters and allowance spending.
- **Safe-mint callbacks and token calls are reentrancy surfaces.** Reserve supply and the caller's lifetime count before interacting, cache the payment price/treasury, and guard `mint`. Tests attempt mint reentry in both payment and NFT receipt, including a receiver forwarding each new NFT away during a batch.
- **Known seeds would let buyers select later sequential IDs.** Require sellout before requesting randomness. Accept exactly one authenticated fulfillment for the recorded request; never replace an accepted request or use timestamp/block-derived fallback entropy. Configuration failure and a reverted request remain recoverable before a successful request.
- **Rendering inside fulfillment could consume too much oracle callback gas.** Fulfillment only writes the seed and reveal flag and emits events. A test removes renderer code and still completes within the declared 120,000-gas callback budget.
- **Factory construction must not trap ownership or depend on live services.** Use the given owner constructor argument and immutable dependency references; deploy every application in a factory rehearsal with no IMD/coordinator code. Scan deployed application opcodes and bound both application and SSTORE2 data bytecode.
- **Art combinations must share anchors and remain visible.** Decode real contract SVGs, validate local references, inspect a 200 px contact sheet covering all 48 variants, and move the Genesis label to a visible side position so hats and crowns cannot cover it.

## Scope and limitations

The economic invariants are exact 50/50 distribution of successful payments, no retained mint proceeds, supply at most 500, lifetime wallet mints at most 10, and sum of NFT balances equal to supply. State-machine tests cover unconfigured, requesting, fulfilled and rejected callback paths. Rendering tests independently decode the actual base64 JSON and SVG and match every emitted trait name to its selected layer.

The production payment token and VRF coordinator are fixed trust dependencies. The token is required to have 18 decimals and standard conserved transfers. A hostile token could lie in all its balance queries; the contract cannot prove the implementation of another contract. There is no claim of supporting arbitrary ERC-20s. RPC reads confirmed the supplied IMD symbol and decimals; coordinator code was present and its address matched the official Ethereum table. No production subscription, proof delivery or LINK billing was exercised.

The owner can make minting economically unattractive by raising price, redirect future treasury proceeds, delay the reveal request, or misconfigure/unfund their subscription. Reveal stays unavailable before sellout; no refund or early-close mechanism exists. After a successful request, there is no retry with a new request, forced reveal, coordinator upgrade or owner-supplied seed. These are documented operational responsibilities and permanence tradeoffs, not hidden admin paths. Marketplace royalty enforcement is outside ERC-2981.

The art uses SVG filters and system monospace text; different viewers may render those details differently. The authored geometry and onchain strings are immutable. Apart from the reserved captain signature, uniqueness of randomly selected combinations and exact realized rarity counts are not guaranteed.

Foundry unit tests, fuzzing, stateful invariants, deployment rehearsal, runtime opcode scanning, formatting and offline art/preview checks were run. Slither and Mythril were not run. Release still requires the independent contributor review and the launch service's complete transaction simulation, dependency checks, confirmed address publication and source verification.
