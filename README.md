# Smart Contract Security Portfolio — Julián

Independent **Smart Contract Security Researcher** specializing in **DeFi protocols, state-machine analysis, economic invariants, and Foundry Proof-of-Concepts (PoCs)**.

I focus on uncovering high-impact vulnerabilities that threaten protocol solvency, user funds, and core accounting invariants before mainnet deployment.

---

## Core Competencies
* **Vulnerability Research:** State-machine flaws, broken economic invariants, access control bypasses, and accounting desynchronizations.
* **Testing & Verification:** End-to-end exploit reproduction, fuzzing, and invariant testing using **Foundry**.
* **Actionable Reporting:** Clear root-cause analysis, quantified financial impact, and production-ready mitigations.

---

## Selected High-Impact Findings

Below is a curated selection of logical vulnerabilities discovered during independent security reviews, each backed by a reproducible Foundry PoC.

| # | Severity | Protocol | Vulnerability Title | Economic Impact | Report & PoC |
| :- | :- | :- | :--- | :--- | :--- |
| **01** | **Critical** | `ConsensusRegistry` | Inverted struct parameters in `delegateStake` assign validator as delegator | Permanent loss of access to staked capital and rewards for delegators | [Report](./reports/01-consensus-registry-delegation-inversion.md) • [PoC](./pocs/01_DelegationInversion.t.sol) |
| **02** | **High** | `ConsensusRegistry` | Failed reward transfers revert ledger updates in `claimStakeRewards` | Breaks capital accounting invariant and inflates protocol liabilities | [Report](./reports/02-consensus-registry-ledger-desync.md) • [PoC](./pocs/02_LedgerNotUpdateOnClaimRevert.t.sol) |
| **03** | **High** | `SessionManager` | Unrestricted access to `assertResults` allows non-participants to claim rewards | Direct theft of game reward pools by arbitrary external addresses | [Report](./reports/03-session-manager-unauthorized-assert.md) • [PoC](./pocs/03_AnybodyCanAssertResults.t.sol) |
| **04** | **Medium** | `SessionManager` | Games with zero winners cannot transition to `Concluded` in `concludeGame` | Permanent lock of entry fees, sponsor deposits, and protocol fees | [Report](./reports/04-session-manager-locked-funds-no-winners.md) • [PoC](./pocs/04_FundsStuckByNoWinners.t.sol) |

---

## Audit Methodology

1. **Threat Modeling & Scope Alignment:** Mapping trust assumptions, privileged roles, and critical protocol invariants before reading code.
2. **State-Machine & Cash-Flow Tracing:** Auditing every entry and exit point of funds (`deposit`, `stake`, `claim`, `withdraw`, `refund`) across all lifecycle states.
3. **Exploit Verification (Foundry):** Building deterministic PoCs to prove real economic impact and validate proposed fixes.

---

## Work With Me (Private Security Reviews)

Building an MVP or preparing for mainnet? I offer **fast, focused private security audits (5–7 days)** tailored for early-stage DeFi, staking, escrow, and Web3 protocols.

* **Deliverables:** Comprehensive vulnerability report, Foundry PoC test suite, and post-fix verification review.
* **Contact:**
  * **X (Twitter):** `@JuCabMar`
  * **Telegram:** `[@TuHandle]`
  * **Email:** `juliancabmar@gmail.com`
