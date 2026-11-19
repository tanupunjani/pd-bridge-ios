# Contributing

This is a pre-release health-adjacent project. Please open an issue before proposing substantial changes. Use fictional data in issues, tests and screenshots; do not submit medical histories, credentials, recordings or private device logs. Keep changes focused, run the relevant checks, and describe the evidence in a pull request. Do not add clinical claims, automatic monitoring or network services without a separate product and safety review.

This repository currently has no open-source license. Contact the maintainer before using its code or assets in another project.

## Development workflow

1. Pull the latest `main` into your clean local checkout.
2. Create a focused feature branch. Do not commit signing credentials, patient data, real recordings, or private screenshots.
3. Run the relevant native contract checks and an unsigned Release build. Record what was not tested.
4. Commit and push the branch, then open a pull request against `main`.
5. Review the diff and wait for required CI checks before merging.
6. Pull the merged `main` locally. Tag only an actually tested release, and keep TestFlight/App Store distribution in a separately approved process.
