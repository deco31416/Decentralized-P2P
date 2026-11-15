# Contributing

Thanks for considering a contribution to CambiaCripto. This guide describes the basic workflow for proposing changes.

## Before you start

- Check existing issues and pull requests for related work.
- For substantial changes, open an issue first to discuss the scope.
- Do not include credentials, personal data, generated build output, or unrelated changes.

## Development setup

```bash
pnpm install
cp .env.example .env.local
pnpm dev
```

On Windows PowerShell, use `Copy-Item .env.example .env.local`. Add only the local values you need. Keep `.env.local`, contract `.env` files, private keys, seed phrases, and API secrets untracked.

## Changes and pull requests

1. Create a focused branch from the default branch.
2. Keep the change small and follow the existing formatting and naming conventions.
3. Run the relevant checks for the files you changed.
4. Open a pull request against the default branch and explain the motivation, implementation, and verification. Include screenshots for visible UI changes.
5. Call out any known limitations or contract/deployment implications.

Never include real funds, production credentials, or mainnet deployment artifacts in examples. Do not claim a contract or feature is secure or audited without independent evidence.

## Reporting security issues

Please do not publish exploitable vulnerability details in a public issue. Contact the maintainer privately through the contact method listed on the maintainer's GitHub profile.

## Code of conduct

Be respectful and constructive. Harassment, discrimination, and personal attacks are not acceptable.

