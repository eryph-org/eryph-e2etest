# eryph-e2etest
Contains end-to-end tests for eryph.

## Run tests locally
You can run the tests locally as follows:
1. Install the Powershell modules `Pester` and `Posh-SSH`
2. Update the `settings.json` to reflect your local environment
3. Run `Setup-LocalGenePool.ps1`. This script will copy the necessary
   genes for testing into your local gene pool.
4. Start eryph-zero
5. Open this repository in VS Code as administrator
6. Make sure the Pester extension is installed. Visual Studio should prompt you.
7. Run the desired test(s) in the VS Code test explorer
